-- ==============================================================================
-- CONSOLIDATED ADMIN FIXES: REGISTRATION, APPROVAL, DELETION, AND UPDATES
-- Run this in the Supabase Dashboard SQL Editor (https://supabase.com/dashboard)
-- ==============================================================================

begin;

-- 1. Ensure required extensions exist
create extension if not exists "pgcrypto" with schema extensions;

-- 2. Ensure all columns exist on public.users
alter table public.users add column if not exists requested_grade text;
alter table public.users add column if not exists requested_class text;
alter table public.users add column if not exists requested_subject text;
alter table public.users add column if not exists section_id uuid;
alter table public.users add column if not exists must_change_password boolean default false;
alter table public.users add column if not exists avatar_url text;

-- 3. Ensure course_resources table exists
create table if not exists public.course_resources (
  id text primary key,
  title text not null,
  description text,
  file_name text not null,
  file_url text not null,
  file_type text not null default 'pdf',
  file_size integer not null default 0,
  school_id uuid references public.schools(id) on delete set null,
  teacher_id text not null,
  teacher_name text not null,
  target_grade text not null,
  target_section text not null,
  created_at timestamp with time zone not null default now()
);

-- 4. Grant table privileges to authenticated and anon roles
grant usage on schema public to authenticated, anon;
grant all on all tables in schema public to authenticated;
grant all on all sequences in schema public to authenticated;
grant select on public.users to anon;
grant select on public.schools to anon;
grant select on public.sections to anon;

-- 5. Row-Level Security on public.users
alter table public.users enable row level security;

-- Drop any conflicting legacy policies on public.users
drop policy if exists users_select_all on public.users;
drop policy if exists users_select_authenticated on public.users;
drop policy if exists users_admin_all on public.users;
drop policy if exists users_update_own on public.users;
drop policy if exists users_teacher_delete_students on public.users;
drop policy if exists users_delete_authorized on public.users;

-- Policy A: Everyone can view active profiles (needed for login, directories, rosters)
create policy users_select_all
  on public.users for select
  using (true);

-- Policy B: Administrators have full access (INSERT, UPDATE, DELETE) to any user row
create policy users_admin_all
  on public.users for all to authenticated
  using (
    (select role from public.users where id = auth.uid()) = 'admin'
  )
  with check (
    (select role from public.users where id = auth.uid()) = 'admin'
  );

-- Policy C: Users can update their own profile details
create policy users_update_own
  on public.users for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Policy D: Teachers can delete student records from their school
create policy users_teacher_delete_students
  on public.users for delete to authenticated
  using (
    (select role from public.users where id = auth.uid()) = 'teacher'
    and role = 'student'
  );

-- 6. SECURITY DEFINER RPC: Admin Create User (Instant email confirmation & pre-approval)
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
  -- Validate caller has administrator privileges
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select role into caller_role from public.users where id = caller_id;
  if caller_role is null or caller_role <> 'admin' then
    raise exception 'Permission denied: only administrators can directly register accounts' using errcode = '42501';
  end if;

  -- Check for conflicting email or username in public.users
  select id into existing_id from public.users
  where lower(email) = clean_email or lower(username) = lower(clean_username)
  limit 1;

  if existing_id is not null then
    return jsonb_build_object('success', false, 'error', 'An account with this email or username already exists');
  end if;

  -- Check for conflicting email in auth.users
  select id into existing_id from auth.users
  where lower(email) = clean_email
  limit 1;

  if existing_id is not null then
    -- If orphan exists in auth.users without public.users, clean it up
    delete from auth.users where id = existing_id;
  end if;

  -- Create entry in auth.users with email confirmed immediately
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

  -- Create entry in public.users
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

  -- Auto-enroll student into section if requested
  if p_role = 'student' and p_section_id is not null then
    insert into public.student_sections (student_id, section_id)
    values (new_id, p_section_id)
    on conflict do nothing;
  end if;

  -- Auto-link teacher course if subject provided
  if p_role = 'teacher' and p_section_id is not null and p_subject is not null then
    insert into public.teacher_courses (teacher_id, section_id, subject)
    values (new_id, p_section_id, p_subject)
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

-- 7. SECURITY DEFINER RPC: Review User Registration (Approve or Reject)
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
  caller record;
  target_user record;
  is_approve boolean := (p_decision = 'approve');
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if caller_id = p_user_id then
    raise exception 'Permission denied: Self-approval is prohibited' using errcode = '42501';
  end if;

  select id, role, is_super_admin, is_attendance_teacher, attendance_grade, attendance_class, school_id
  into caller
  from public.users
  where id = caller_id;

  select id, role, requested_role, school_id, section_id, requested_grade, requested_class
  into target_user
  from public.users
  where id = p_user_id;

  if target_user.id is null then
    return jsonb_build_object('success', false, 'error', 'User record not found');
  end if;

  -- Role Hierarchy Validation:
  if caller.role = 'admin' or caller.is_super_admin is true then
    -- Super Admin can review any account across all schools
    null;
  elsif caller.role = 'subadmin' then
    if coalesce(target_user.requested_role, target_user.role) in ('admin', 'subadmin') then
      raise exception 'Permission denied: Only the Super Administrator can review administrator accounts' using errcode = '42501';
    end if;
    if caller.school_id is not null and target_user.school_id is not null and target_user.school_id <> caller.school_id then
      raise exception 'Permission denied: Sub-admins can only review accounts for their own school' using errcode = '42501';
    end if;
  elsif caller.role = 'teacher' and caller.is_attendance_teacher is true then
    if coalesce(target_user.requested_role, target_user.role) <> 'student' then
      raise exception 'Permission denied: Attendance teachers can only review student registrations' using errcode = '42501';
    end if;
    if caller.attendance_class is not null and
       (target_user.requested_class is null or lower(trim(target_user.requested_class)) <> lower(trim(caller.attendance_class))) then
      raise exception 'Permission denied: You can only review students for your designated class (%)', caller.attendance_class using errcode = '42501';
    end if;
  else
    raise exception 'Permission denied: You do not have permission to review registrations' using errcode = '42501';
  end if;

  -- Update public.users record
  update public.users
  set
    approval_status = case when is_approve then 'approved' else 'rejected' end,
    is_active = is_approve,
    role = case when is_approve and target_user.requested_role is not null then target_user.requested_role else role end,
    school_id = coalesce(p_school_id, target_user.school_id)
  where id = p_user_id;

  -- Confirm email in auth.users so the account is active immediately
  if is_approve then
    update auth.users
    set
      email_confirmed_at = coalesce(email_confirmed_at, now()),
      updated_at = now()
    where id = p_user_id;

    -- If student has section_id, link it in student_sections
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

-- 8. SECURITY DEFINER RPC: Delete User Account (Hard delete from public & auth with cascades)
drop function if exists public.delete_user_account(uuid, uuid);
drop function if exists public.delete_user_account(uuid);
drop function if exists public.delete_user_account(jsonb);

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
    raise exception 'Target user ID is required' using errcode = '23502';
  end if;

  select role, school_id into caller_role, caller_school from public.users where id = caller_id;
  if caller_role is null or caller_role not in ('admin', 'teacher') then
    raise exception 'Permission denied: only administrators and teachers can delete accounts' using errcode = '42501';
  end if;

  if caller_id = target_id then
    raise exception 'You cannot delete your own account' using errcode = '23514';
  end if;

  select id, role, school_id into target_user
  from public.users
  where id = target_id;

  if caller_role = 'teacher' then
    if target_user.id is not null and target_user.role <> 'student' then
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

  -- Delete public.users record
  delete from public.users where id = target_id;

  -- Delete auth.users account
  delete from auth.users where id = target_id;

  return jsonb_build_object('success', true, 'id', target_id);
end;
$$;

grant execute on function public.delete_user_account(uuid, uuid) to authenticated;

-- 9. SECURITY DEFINER RPC: Admin Update User (Update profile details, role, school, status)
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

  -- Update public.users
  update public.users
  set
    full_name = coalesce(nullif(trim(p_full_name), ''), full_name),
    role = coalesce(p_role, role),
    school_id = coalesce(p_school_id, school_id),
    section_id = coalesce(p_section_id, section_id),
    is_active = coalesce(p_is_active, is_active),
    email = coalesce(nullif(lower(trim(p_email)), ''), email)
  where id = p_user_id;

  -- If section_id was provided and user is student, link into student_sections
  if p_section_id is not null then
    insert into public.student_sections (student_id, section_id)
    values (p_user_id, p_section_id)
    on conflict do nothing;
  end if;

  -- Update metadata in auth.users
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

-- 10. Refresh PostgREST schema cache
notify pgrst, 'reload schema';

commit;

