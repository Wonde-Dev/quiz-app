begin;

-- 1. Grant table-level permissions on public.users to authenticated users
grant select, insert, update, delete on public.users to authenticated;

-- 2. Update RLS policies on public.users so administrators have full management capability
drop policy if exists users_admin_update on public.users;
create policy users_admin_update
  on public.users for update to authenticated
  using (
    id = (select auth.uid())
    or (select private.app_current_role()) = 'admin'
  )
  with check (
    id = (select auth.uid())
    or (select private.app_current_role()) = 'admin'
  );

drop policy if exists users_delete_authorized on public.users;
create policy users_delete_authorized
  on public.users for delete to authenticated
  using (
    (select private.app_current_role()) = 'admin'
    or (
      (select private.app_current_role()) = 'teacher'
      and role = 'student'
      and school_id = (select private.app_current_school_id())
    )
  );

-- 3. Dedicated security definer RPC function to review / approve / reject registration requests
create or replace function public.review_user_registration(
  p_user_id uuid,
  p_decision text,
  p_school_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
declare
  caller_id uuid := auth.uid();
  caller_role text;
  target_user record;
  is_approve boolean := (p_decision = 'approve');
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select role into caller_role from public.users where id = caller_id;
  if caller_role is null or caller_role <> 'admin' then
    raise exception 'Permission denied: only administrators can review account requests' using errcode = '42501';
  end if;

  select id, requested_role, school_id into target_user
  from public.users
  where id = p_user_id;

  if target_user.id is null then
    return jsonb_build_object('success', false, 'error', 'User not found');
  end if;

  update public.users
  set
    approval_status = case when is_approve then 'approved' else 'rejected' end,
    is_active = is_approve,
    role = case when is_approve and target_user.requested_role is not null then target_user.requested_role else role end,
    school_id = coalesce(p_school_id, school_id)
  where id = p_user_id;

  return jsonb_build_object('success', true, 'status', case when is_approve then 'approved' else 'rejected' end);
end;
$$;

grant execute on function public.review_user_registration(uuid, text, uuid) to authenticated;

-- 4. Dedicated security definer RPC function to safely delete user accounts with full cascade
create or replace function public.delete_user_account(
  user_id uuid default null,
  p_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
declare
  caller_id uuid := auth.uid();
  caller_role text;
  caller_school uuid;
  target_user record;
  target_id uuid := coalesce(user_id, p_user_id);
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if target_id is null then
    raise exception 'Target user id is required' using errcode = '23502';
  end if;

  select role, school_id into caller_role, caller_school from public.users where id = caller_id;
  if caller_role is null or caller_role not in ('admin', 'teacher') then
    raise exception 'Permission denied: only administrators and teachers can delete accounts' using errcode = '42501';
  end if;

  select id, role, school_id into target_user
  from public.users
  where id = target_id;

  if target_user.id is null then
    return jsonb_build_object('success', true, 'message', 'Account already deleted');
  end if;

  if caller_id = target_id then
    raise exception 'You cannot delete your own account' using errcode = '23514';
  end if;

  if caller_role = 'teacher' then
    if target_user.role <> 'student' then
      raise exception 'Teachers can only delete student accounts' using errcode = '42501';
    end if;
    if caller_school is not null and target_user.school_id is not null and target_user.school_id <> caller_school then
      raise exception 'Teachers can only delete students from their own school' using errcode = '42501';
    end if;
  end if;

  -- Cascade delete child records
  delete from public.answers where student_id = target_id;
  delete from public.quiz_attempts where student_id = target_id;
  delete from public.grades where student_id = target_id;
  delete from public.student_sections where student_id = target_id;
  delete from public.teacher_courses where teacher_id = target_id;
  delete from public.courses where teacher_id = target_id;
  delete from public.password_reset_requests where user_id = target_id;
  delete from public.audit_logs where user_id = target_id;

  -- Delete public user profile
  delete from public.users where id = target_id;

  -- Delete auth user account so user can never log in again
  delete from auth.users where id = target_id;

  return jsonb_build_object('success', true, 'id', target_id);
end;
$$;

grant execute on function public.delete_user_account(uuid, uuid) to authenticated;

-- 5. Dedicated security definer RPC function to reset password directly
create or replace function public.reset_user_password_admin(
  p_user_id uuid,
  p_password text
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'extensions', 'pg_temp'
as $$
declare
  caller_id uuid := auth.uid();
  caller_role text;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select role into caller_role from public.users where id = caller_id;
  if caller_role is null or caller_role not in ('admin', 'teacher') then
    raise exception 'Permission denied: only administrators and teachers can reset passwords' using errcode = '42501';
  end if;

  -- Update password in auth.users using pgcrypto crypt
  update auth.users
  set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
      updated_at = now()
  where id = p_user_id;

  -- Flag must change password in public.users
  update public.users
  set must_change_password = true
  where id = p_user_id;

  return jsonb_build_object('success', true, 'temporary_password', p_password);
end;
$$;

grant execute on function public.reset_user_password_admin(uuid, text) to authenticated;

-- 6. Dedicated security definer RPC function to update avatar URL
create or replace function public.update_user_avatar(
  p_user_id uuid,
  p_avatar_url text
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if auth.uid() <> p_user_id and (select role from public.users where id = auth.uid()) <> 'admin' then
    raise exception 'Permission denied' using errcode = '42501';
  end if;

  update public.users
  set avatar_url = p_avatar_url
  where id = p_user_id;

  return jsonb_build_object('success', true, 'avatar_url', p_avatar_url);
end;
$$;

grant execute on function public.update_user_avatar(uuid, text) to authenticated;

-- 7. Course Resources & Worksheets Table (PDF uploads by Teachers)
create table if not exists public.course_resources (
  id text primary key,
  title text not null,
  description text,
  file_name text not null,
  file_url text not null,
  file_type text not null default 'pdf',
  file_size bigint,
  school_id uuid references public.schools(id) on delete set null,
  teacher_id uuid references public.users(id) on delete cascade,
  teacher_name text,
  target_grade text,
  target_section text,
  created_at timestamptz not null default now()
);

grant select, insert, update, delete on public.course_resources to authenticated;

alter table public.course_resources enable row level security;

drop policy if exists course_resources_select on public.course_resources;
create policy course_resources_select
  on public.course_resources for select to authenticated
  using (true);

drop policy if exists course_resources_teacher_manage on public.course_resources;
create policy course_resources_teacher_manage
  on public.course_resources for all to authenticated
  using (
    (select private.app_current_role()) in ('teacher', 'admin')
  )
  with check (
    (select private.app_current_role()) in ('teacher', 'admin')
  );

-- 8. Storage bucket for course materials & exam PDFs
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'course-materials',
  'course-materials',
  true,
  52428800,
  array['application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'image/jpeg', 'image/png']
)
on conflict (id) do update set public = true;

drop policy if exists "course_materials_public_read" on storage.objects;
create policy "course_materials_public_read"
  on storage.objects for select to authenticated, anon
  using (bucket_id = 'course-materials');

drop policy if exists "course_materials_teacher_upload" on storage.objects;
create policy "course_materials_teacher_upload"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'course-materials');

commit;
