-- ==============================================================================
-- MIGRATION: 20261024000000_fix_admin_permissions_and_rpcs.sql
-- Role Hierarchy: Main Admin, Sub-Admin/Director, Teachers, Attendance Teachers (e.g. 9A), Students
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
alter table public.users add column if not exists is_super_admin boolean default false;
alter table public.users add column if not exists is_attendance_teacher boolean default false;
alter table public.users add column if not exists attendance_grade text;
alter table public.users add column if not exists attendance_class text;
alter table public.users add column if not exists assigned_grade text;
alter table public.users add column if not exists assigned_class text;
alter table public.users add column if not exists assigned_subject text;
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

-- 4. Mark existing Primary / Super Administrators
update public.users
set is_super_admin = true, role = 'admin'
where email in ('wondedev369@gmail.com', 'wondeadmin@admin.edu')
   or (role = 'admin' and is_super_admin is not true);

-- 5. Grant table-level permissions to authenticated and anon
grant usage on schema public to authenticated, anon;
grant select, insert, update, delete on public.users to authenticated;
grant select on public.users to anon;
grant all on all sequences in schema public to authenticated;

do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'schools') then
    execute 'grant select on public.schools to anon, authenticated';
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'sections') then
    execute 'grant select on public.sections to anon, authenticated';
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'student_sections') then
    execute 'grant select, insert, update, delete on public.student_sections to authenticated';
  end if;
end $$;

-- 6. Row Level Security on public.users
alter table public.users enable row level security;

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

-- Policy B: Admins and Sub-Admins / Directors have full access
create policy users_admin_all
  on public.users for all to authenticated
  using (
    (select role from public.users where id = auth.uid()) in ('admin', 'subadmin')
    or (select private.app_current_role()) in ('admin', 'subadmin')
  )
  with check (
    (select role from public.users where id = auth.uid()) in ('admin', 'subadmin')
    or (select private.app_current_role()) in ('admin', 'subadmin')
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

-- 7. RPC: admin_create_user
-- Supports Main Admin, Sub-Admin / Director, Teachers, Attendance Teachers, and Students
create or replace function public.admin_create_user(
  p_full_name text,
  p_username text,
  p_email text,
  p_password text,
  p_role text,
  p_school_id uuid default null,
  p_section_id uuid default null,
  p_subject text default null,
  p_grade text default null,
  p_class text default null,
  p_is_attendance_teacher boolean default false,
  p_attendance_grade text default null,
  p_attendance_class text default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'extensions', 'pg_temp'
as $$
declare
  caller_id uuid := auth.uid();
  caller record;
  new_id uuid := gen_random_uuid();
  clean_username text := trim(p_username);
  clean_email text := lower(trim(p_email));
  existing_id uuid;
  assigned_role text := lower(trim(p_role));
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select id, role, is_super_admin, is_attendance_teacher, attendance_grade, attendance_class, school_id
  into caller
  from public.users
  where id = caller_id;

  if caller.id is null then
    raise exception 'Caller profile not found' using errcode = '42501';
  end if;

  -- Ensure only ONE Super Admin exists: Any new admin registered is created as subadmin
  if assigned_role = 'admin' then
    assigned_role := 'subadmin';
  end if;

  -- Authority Validation:
  if caller.role in ('admin', 'subadmin') then
    -- Administrator can create subadmin, teacher, student
    null;
  elsif caller.role = 'teacher' and caller.is_attendance_teacher = true then
    -- Attendance Teacher can ONLY create students for their OWN attendance class (e.g. 9A)
    if assigned_role <> 'student' then
      raise exception 'Permission denied: Attendance teachers can only register students' using errcode = '42501';
    end if;
    if p_class is not null and caller.attendance_class is not null and lower(trim(p_class)) <> lower(trim(caller.attendance_class)) then
      raise exception 'Permission denied: You can only register students for your attendance class (%)', caller.attendance_class using errcode = '42501';
    end if;
  else
    raise exception 'Permission denied: You do not have permission to register accounts' using errcode = '42501';
  end if;

  -- Check duplicate username/email
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

  -- Create Auth User with email confirmed
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
      'role', assigned_role,
      'approval_status', 'approved',
      'is_active', true,
      'school_id', coalesce(p_school_id, caller.school_id),
      'section_id', p_section_id,
      'is_attendance_teacher', p_is_attendance_teacher,
      'attendance_class', p_attendance_class,
      'attendance_grade', p_attendance_grade
    ),
    now(),
    now(),
    'authenticated',
    'authenticated'
  );

  -- Insert Public User
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
    assigned_subject,
    requested_grade,
    assigned_grade,
    requested_class,
    assigned_class,
    is_attendance_teacher,
    attendance_grade,
    attendance_class,
    must_change_password
  ) values (
    new_id,
    clean_email,
    clean_username,
    p_full_name,
    assigned_role,
    'approved',
    true,
    coalesce(p_school_id, caller.school_id),
    p_section_id,
    p_subject,
    p_subject,
    coalesce(p_grade, p_attendance_grade),
    coalesce(p_grade, p_attendance_grade),
    coalesce(p_class, p_attendance_class),
    coalesce(p_class, p_attendance_class),
    p_is_attendance_teacher,
    p_attendance_grade,
    p_attendance_class,
    true
  ) on conflict (id) do update set
    approval_status = 'approved',
    is_active = true,
    must_change_password = true,
    is_attendance_teacher = p_is_attendance_teacher,
    attendance_class = p_attendance_class,
    attendance_grade = p_attendance_grade;

  if assigned_role = 'student' and p_section_id is not null then
    insert into public.student_sections (student_id, section_id)
    values (new_id, p_section_id)
    on conflict do nothing;
  end if;

  return jsonb_build_object(
    'success', true,
    'id', new_id,
    'username', clean_username,
    'email', clean_email,
    'role', assigned_role
  );
end;
$$;

grant execute on function public.admin_create_user(text, text, text, text, text, uuid, uuid, text, text, text, boolean, text, text) to authenticated;

-- Backwards-compatible overload with 8 parameters:
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
begin
  return public.admin_create_user(
    p_full_name,
    p_username,
    p_email,
    p_password,
    p_role,
    p_school_id,
    p_section_id,
    p_subject,
    null,
    null,
    false,
    null,
    null
  );
end;
$$;

grant execute on function public.admin_create_user(text, text, text, text, text, uuid, uuid, text) to authenticated;

-- 8. RPC: review_user_registration
-- Supports Main Admin, Sub-Admin / Director, and Class Attendance Teachers
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

  select id, role, is_super_admin, is_attendance_teacher, attendance_grade, attendance_class, school_id
  into caller
  from public.users
  where id = caller_id;

  select id, role, requested_role, school_id, section_id, requested_grade, requested_class
  into target_user
  from public.users
  where id = p_user_id;

  if target_user.id is null then
    return jsonb_build_object('success', false, 'error', 'User not found');
  end if;

  -- Permission Validation:
  if caller.role in ('admin', 'subadmin') then
    -- Admin and Sub-admin can approve any teacher or student request
    null;
  elsif caller.role = 'teacher' and caller.is_attendance_teacher = true then
    -- Attendance teacher can ONLY approve students of their OWN class (e.g. 9A)
    if coalesce(target_user.requested_role, target_user.role) <> 'student' then
      raise exception 'Attendance teachers can only approve student registrations' using errcode = '42501';
    end if;
    if caller.attendance_class is not null and
       (target_user.requested_class is null or lower(trim(target_user.requested_class)) <> lower(trim(caller.attendance_class))) then
      raise exception 'Permission denied: You can only approve students for your assigned class (%)', caller.attendance_class using errcode = '42501';
    end if;
  else
    raise exception 'Permission denied: Only administrators and designated attendance teachers can review registrations' using errcode = '42501';
  end if;

  -- Apply approval / rejection
  update public.users
  set
    approval_status = case when is_approve then 'approved' else 'rejected' end,
    is_active = is_approve,
    role = case when is_approve and target_user.requested_role is not null then target_user.requested_role else role end,
    school_id = coalesce(p_school_id, target_user.school_id, caller.school_id)
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

-- 9. RPC: delete_user_account
-- Protected against deleting Main Admin account by anyone (including sub-admins)
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
  caller record;
  target_user record;
  target_id uuid := coalesce(user_id, p_user_id);
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if target_id is null then
    raise exception 'Target user id is required' using errcode = '23502';
  end if;

  select id, role, is_super_admin, is_attendance_teacher, attendance_class, school_id
  into caller
  from public.users
  where id = caller_id;

  if caller.id is null or caller.role not in ('admin', 'subadmin', 'teacher') then
    raise exception 'Permission denied: Only administrators and authorized faculty can delete accounts' using errcode = '42501';
  end if;

  if caller_id = target_id then
    raise exception 'You cannot delete your own account' using errcode = '23514';
  end if;

  select id, email, role, is_super_admin, requested_class, school_id
  into target_user
  from public.users
  where id = target_id;

  if target_user.id is null then
    return jsonb_build_object('success', true, 'message', 'Account already deleted');
  end if;

  -- CRITICAL RULE: MAIN ADMIN ACCOUNT CAN NEVER BE DELETED BY ANYONE
  if target_user.is_super_admin = true or
     lower(target_user.email) in ('wondedev369@gmail.com', 'wondeadmin@admin.edu') or
     (target_user.role = 'admin' and caller.role = 'subadmin') then
    raise exception 'Permission denied: The Main Administrator account is protected and cannot be deleted' using errcode = '42501';
  end if;

  -- Role-specific deletion validation:
  if caller.role = 'teacher' then
    if target_user.role <> 'student' then
      raise exception 'Teachers can only delete student accounts' using errcode = '42501';
    end if;
    if caller.is_attendance_teacher = true and caller.attendance_class is not null and
       target_user.requested_class is not null and lower(trim(target_user.requested_class)) <> lower(trim(caller.attendance_class)) then
      raise exception 'Attendance teachers can only delete students of their assigned class (%)', caller.attendance_class using errcode = '42501';
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

  delete from public.users where id = target_id;
  delete from auth.users where id = target_id;

  return jsonb_build_object('success', true, 'id', target_id);
end;
$$;

grant execute on function public.delete_user_account(uuid, uuid) to authenticated;

-- 10. RPC: admin_update_user
create or replace function public.admin_update_user(
  p_user_id uuid,
  p_full_name text default null,
  p_role text default null,
  p_school_id uuid default null,
  p_section_id uuid default null,
  p_is_active boolean default null,
  p_email text default null,
  p_is_attendance_teacher boolean default null,
  p_attendance_grade text default null,
  p_attendance_class text default null,
  p_assigned_subject text default null
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
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select id, role, is_super_admin into caller from public.users where id = caller_id;
  if caller.role not in ('admin', 'subadmin') then
    raise exception 'Permission denied: Only administrators can modify user profiles' using errcode = '42501';
  end if;

  select id, email, role, is_super_admin into target_user from public.users where id = p_user_id;

  -- Sub-admins cannot modify or demote the Main Admin account
  if caller.role = 'subadmin' and (target_user.is_super_admin = true or target_user.role = 'admin') then
    raise exception 'Permission denied: Sub-admins cannot modify the Main Administrator account' using errcode = '42501';
  end if;

  update public.users
  set
    full_name = coalesce(nullif(trim(p_full_name), ''), full_name),
    role = coalesce(p_role, role),
    school_id = coalesce(p_school_id, school_id),
    section_id = coalesce(p_section_id, section_id),
    is_active = coalesce(p_is_active, is_active),
    email = coalesce(nullif(lower(trim(p_email)), ''), email),
    is_attendance_teacher = coalesce(p_is_attendance_teacher, is_attendance_teacher),
    attendance_grade = coalesce(p_attendance_grade, attendance_grade),
    attendance_class = coalesce(p_attendance_class, attendance_class),
    assigned_subject = coalesce(p_assigned_subject, assigned_subject)
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
      'is_active', p_is_active,
      'is_attendance_teacher', p_is_attendance_teacher,
      'attendance_class', p_attendance_class
    )),
    updated_at = now()
  where id = p_user_id;

  return jsonb_build_object('success', true, 'id', p_user_id);
end;
$$;

grant execute on function public.admin_update_user(uuid, text, text, uuid, uuid, boolean, text, boolean, text, text, text) to authenticated;

-- Backwards-compatible overload with 7 parameters:
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
begin
  return public.admin_update_user(
    p_user_id,
    p_full_name,
    p_role,
    p_school_id,
    p_section_id,
    p_is_active,
    p_email,
    null,
    null,
    null,
    null
  );
end;
$$;

grant execute on function public.admin_update_user(uuid, text, text, uuid, uuid, boolean, text) to authenticated;

-- 11. RPC: reset_user_password_admin
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
  if caller_role is null or caller_role not in ('admin', 'subadmin', 'teacher') then
    raise exception 'Permission denied: Only administrators and faculty can reset passwords' using errcode = '42501';
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

-- 12. RPC: update_user_avatar
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

  if auth.uid() <> p_user_id and (select role from public.users where id = auth.uid()) not in ('admin', 'subadmin') then
    raise exception 'Permission denied' using errcode = '42501';
  end if;

  update public.users
  set avatar_url = p_avatar_url
  where id = p_user_id;

  return jsonb_build_object('success', true, 'avatar_url', p_avatar_url);
end;
$$;

grant execute on function public.update_user_avatar(uuid, text) to authenticated;

-- 13. Course Resources Table & RLS
create table if not exists public.course_resources (
  id text primary key,
  title text not null,
  description text,
  file_name text not null,
  file_url text not null,
  file_type text not null default 'pdf',
  file_size bigint default 0,
  video_url text,
  thumbnail_url text,
  school_id uuid,
  teacher_id text not null,
  teacher_name text not null default 'Instructor',
  target_grade text,
  target_section text,
  created_at timestamptz not null default now()
);

alter table public.course_resources add column if not exists video_url text;
alter table public.course_resources add column if not exists thumbnail_url text;

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
    (select role from public.users where id = auth.uid()) in ('teacher', 'admin', 'subadmin')
    or (select private.app_current_role()) in ('teacher', 'admin', 'subadmin')
  )
  with check (
    (select role from public.users where id = auth.uid()) in ('teacher', 'admin', 'subadmin')
    or (select private.app_current_role()) in ('teacher', 'admin', 'subadmin')
  );

-- 14. Storage bucket for course materials & exam PDFs
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
  raise notice 'Storage bucket notice: %', sqlerrm;
end $$;

-- 15. Reload PostgREST schema cache
notify pgrst, 'reload schema';

commit;
