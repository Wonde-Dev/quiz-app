-- ==============================================================================
-- MIGRATION: 20261024000000_fix_admin_permissions_and_rpcs.sql
-- Fixed & Enhanced for Direct Supabase Migration
-- ==============================================================================

begin;

-- 1. Ensure required extensions exist
create extension if not exists "pgcrypto" with schema extensions;

-- 2. Create private schema and helper functions if they do not exist
create schema if not exists private;

create or replace function private.app_current_role()
returns text
language sql
stable
security definer
set search_path = 'public', 'pg_temp'
as $$
  select role from public.users where id = auth.uid();
$$;

create or replace function private.app_current_school_id()
returns uuid
language sql
stable
security definer
set search_path = 'public', 'pg_temp'
as $$
  select school_id from public.users where id = auth.uid();
$$;

grant usage on schema private to authenticated;
grant execute on function private.app_current_role() to authenticated;
grant execute on function private.app_current_school_id() to authenticated;

-- 3. Ensure all necessary columns exist on public.users
alter table public.users add column if not exists requested_role text;
alter table public.users add column if not exists requested_grade text;
alter table public.users add column if not exists requested_class text;
alter table public.users add column if not exists requested_subject text;
alter table public.users add column if not exists section_id uuid;
alter table public.users add column if not exists must_change_password boolean default false;
alter table public.users add column if not exists avatar_url text;
alter table public.users add column if not exists approval_status text default 'approved';
alter table public.users add column if not exists is_active boolean default true;
alter table public.users add column if not exists last_login timestamptz;

-- 4. Grant table-level permissions on public.users to authenticated and anon users
grant usage on schema public to authenticated, anon;
grant select, insert, update, delete on public.users to authenticated;
grant select on public.users to anon;
grant all on all sequences in schema public to authenticated;

-- If schools / sections tables exist, grant read access to anon
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'schools') then
    execute 'grant select on public.schools to anon, authenticated';
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'sections') then
    execute 'grant select on public.sections to anon, authenticated';
  end if;
end $$;

-- 5. Row Level Security on public.users
alter table public.users enable row level security;

-- Drop legacy conflicting policies
drop policy if exists users_select_all on public.users;
drop policy if exists users_select_authenticated on public.users;
drop policy if exists users_admin_update on public.users;
drop policy if exists users_admin_all on public.users;
drop policy if exists users_update_own on public.users;
drop policy if exists users_delete_authorized on public.users;
drop policy if exists users_teacher_delete_students on public.users;

-- Policy A: Everyone can view active profiles (needed for login and school directories)
create policy users_select_all
  on public.users for select
  using (true);

-- Policy B: Admins have full access (INSERT, UPDATE, DELETE)
create policy users_admin_all
  on public.users for all to authenticated
  using (
    (select role from public.users where id = auth.uid()) = 'admin'
    or (select private.app_current_role()) = 'admin'
  )
  with check (
    (select role from public.users where id = auth.uid()) = 'admin'
    or (select private.app_current_role()) = 'admin'
  );

-- Policy C: Users can update their own profile
create policy users_update_own
  on public.users for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Policy D: Teachers can delete student records
create policy users_teacher_delete_students
  on public.users for delete to authenticated
  using (
    (
      (select role from public.users where id = auth.uid()) = 'teacher'
      or (select private.app_current_role()) = 'teacher'
    )
    and role = 'student'
  );

-- 6. RPC: review_user_registration (Approve / Reject registration requests)
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

  select id, requested_role, school_id, section_id into target_user
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
    school_id = coalesce(p_school_id, target_user.school_id)
  where id = p_user_id;

  if is_approve then
    update auth.users
    set
      email_confirmed_at = coalesce(email_confirmed_at, now()),
      updated_at = now()
    where id = p_user_id;

    if target_user.section_id is not null then
      insert into public.student_sections (student_id, section_id)
      values (p_user_id, target_user.section_id)
      on conflict do nothing;
    end if;
  end if;

  return jsonb_build_object(
    'success', true,
    'status', case when is_approve then 'approved' else 'rejected' end,
    'id', p_user_id
  );
end;
$$;

grant execute on function public.review_user_registration(uuid, text, uuid) to authenticated;

-- 7. RPC: delete_user_account (Full cascade deletion of user and related records)
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

  -- Cascade delete dependent records safely
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

-- 8. RPC: reset_user_password_admin
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

  update auth.users
  set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
      updated_at = now()
  where id = p_user_id;

  update public.users
  set must_change_password = true
  where id = p_user_id;

  return jsonb_build_object('success', true, 'temporary_password', p_password);
end;
$$;

grant execute on function public.reset_user_password_admin(uuid, text) to authenticated;

-- 9. RPC: update_user_avatar
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

-- 10. RPC: admin_create_user (Instant pre-approved user registration without logging out admin)
create or replace function public.admin_create_user(
  p_full_name text,
  p_username text,
  p_email text,
  p_password text,
  p_role text,
  p_school_id uuid default null,
  p_section_id uuid default null,
  p_subject text default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'extensions', 'pg_temp'
as $$
declare
  caller_id uuid := auth.uid();
  caller_role text;
  new_id uuid := gen_random_uuid();
  clean_username text := trim(p_username);
  clean_email text := lower(trim(p_email));
  existing_id uuid;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select role into caller_role from public.users where id = caller_id;
  if caller_role is null or caller_role <> 'admin' then
    raise exception 'Permission denied: only administrators can directly register accounts' using errcode = '42501';
  end if;

  select id into existing_id from public.users
  where lower(email) = clean_email or lower(username) = lower(clean_username)
  limit 1;

  if existing_id is not null then
    return jsonb_build_object('success', false, 'error', 'An account with this email or username already exists');
  end if;

  select id into existing_id from auth.users
  where lower(email) = clean_email
  limit 1;

  if existing_id is not null then
    delete from auth.users where id = existing_id;
  end if;

  insert into auth.users (
    id,
    instance_id,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    aud,
    role
  ) values (
    new_id,
    '00000000-0000-0000-0000-000000000000'::uuid,
    clean_email,
    extensions.crypt(p_password, extensions.gen_salt('bf')),
    now(),
    jsonb_build_object('provider', 'email', 'providers', array['email']),
    jsonb_build_object(
      'full_name', p_full_name,
      'username', clean_username,
      'role', p_role,
      'approval_status', 'approved',
      'is_active', true,
      'school_id', p_school_id,
      'section_id', p_section_id
    ),
    now(),
    now(),
    'authenticated',
    'authenticated'
  );

  insert into public.users (
    id,
    email,
    username,
    full_name,
    role,
    approval_status,
    is_active,
    school_id,
    section_id,
    requested_subject,
    must_change_password
  ) values (
    new_id,
    clean_email,
    clean_username,
    p_full_name,
    p_role,
    'approved',
    true,
    p_school_id,
    p_section_id,
    p_subject,
    true
  ) on conflict (id) do update set
    approval_status = 'approved',
    is_active = true,
    must_change_password = true;

  if p_role = 'student' and p_section_id is not null then
    insert into public.student_sections (student_id, section_id)
    values (new_id, p_section_id)
    on conflict do nothing;
  end if;

  return jsonb_build_object(
    'success', true,
    'id', new_id,
    'username', clean_username,
    'email', clean_email
  );
end;
$$;

grant execute on function public.admin_create_user(text, text, text, text, text, uuid, uuid, text) to authenticated;

-- 11. RPC: admin_update_user (Edit user profiles directly)
create or replace function public.admin_update_user(
  p_user_id uuid,
  p_full_name text default null,
  p_role text default null,
  p_school_id uuid default null,
  p_section_id uuid default null,
  p_is_active boolean default null,
  p_email text default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
declare
  caller_id uuid := auth.uid();
  caller_role text;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select role into caller_role from public.users where id = caller_id;
  if caller_role is null or caller_role <> 'admin' then
    raise exception 'Permission denied: only administrators can edit user profiles' using errcode = '42501';
  end if;

  update public.users
  set
    full_name = coalesce(nullif(trim(p_full_name), ''), full_name),
    role = coalesce(p_role, role),
    school_id = coalesce(p_school_id, school_id),
    section_id = coalesce(p_section_id, section_id),
    is_active = coalesce(p_is_active, is_active),
    email = coalesce(nullif(lower(trim(p_email)), ''), email)
  where id = p_user_id;

  if p_section_id is not null then
    insert into public.student_sections (student_id, section_id)
    values (p_user_id, p_section_id)
    on conflict do nothing;
  end if;

  update auth.users
  set
    email = coalesce(nullif(lower(trim(p_email)), ''), email),
    raw_user_meta_data = raw_user_meta_data || jsonb_strip_nulls(jsonb_build_object(
      'full_name', nullif(trim(p_full_name), ''),
      'role', p_role,
      'school_id', p_school_id,
      'is_active', p_is_active
    )),
    updated_at = now()
  where id = p_user_id;

  return jsonb_build_object('success', true, 'id', p_user_id);
end;
$$;

grant execute on function public.admin_update_user(uuid, text, text, uuid, uuid, boolean, text) to authenticated;

-- 12. Course Resources & Worksheets Table (PDF uploads by Teachers)
create table if not exists public.course_resources (
  id text primary key,
  title text not null,
  description text,
  file_name text not null,
  file_url text not null,
  file_type text not null default 'pdf',
  file_size bigint default 0,
  school_id uuid,
  teacher_id text not null,
  teacher_name text not null default 'Instructor',
  target_grade text,
  target_section text,
  created_at timestamptz not null default now()
);

grant all on public.course_resources to authenticated;
grant select on public.course_resources to anon;

alter table public.course_resources enable row level security;

drop policy if exists course_resources_select on public.course_resources;
create policy course_resources_select
  on public.course_resources for select
  using (true);

drop policy if exists course_resources_teacher_manage on public.course_resources;
create policy course_resources_teacher_manage
  on public.course_resources for all to authenticated
  using (
    (select role from public.users where id = auth.uid()) in ('teacher', 'admin')
    or (select private.app_current_role()) in ('teacher', 'admin')
  )
  with check (
    (select role from public.users where id = auth.uid()) in ('teacher', 'admin')
    or (select private.app_current_role()) in ('teacher', 'admin')
  );

-- 13. Storage bucket for course materials & exam PDFs (handled safely)
do $$
begin
  if exists (select 1 from information_schema.schemata where schema_name = 'storage') then
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

    drop policy if exists "course_materials_teacher_delete" on storage.objects;
    create policy "course_materials_teacher_delete"
      on storage.objects for delete to authenticated
      using (bucket_id = 'course-materials');
  end if;
exception when others then
  raise notice 'Storage bucket setup warning: %', sqlerrm;
end $$;

-- 14. Notify PostgREST to immediately refresh its schema cache
notify pgrst, 'reload schema';

commit;
