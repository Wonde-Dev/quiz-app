-- ==============================================================================
-- MIGRATION: 20261028190000_school_hierarchy_and_exam_system.sql
-- Description: Complete Multi-School Role Hierarchy, Safe User Approval,
--              Phone/Gender Fields, Overloaded RPC Signatures (PGRST202 Prevention),
--              and Exam System Persistence.
-- ==============================================================================

begin;

-- 1. Ensure required extensions
create extension if not exists "pgcrypto" with schema extensions;

-- 2. Schema private helpers
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

-- 3. Required User Columns (Full name, phone, gender, assignments, hierarchy)
alter table public.users add column if not exists phone_number text;
alter table public.users add column if not exists gender text;
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

-- Ensure role check constraints allow all hierarchy roles
alter table public.users drop constraint if exists users_role_check;
alter table public.users drop constraint if exists users_requested_role_check;
alter table public.users add constraint users_role_check
  check (role is null or role in ('super_admin', 'admin', 'subadmin', 'teacher', 'student'));
alter table public.users add constraint users_requested_role_check
  check (requested_role is null or requested_role in ('super_admin', 'admin', 'subadmin', 'teacher', 'student'));

-- Mark primary Super Administrator
update public.users
set is_super_admin = true, role = 'admin'
where email in ('wondedev369@gmail.com', 'wondeadmin@admin.edu')
   or (role = 'admin' and is_super_admin is not true);

-- 4. Audit Log Foreign Key & Nullability Safety
alter table public.audit_logs alter column performed_by drop not null;
alter table public.audit_logs drop constraint if exists audit_logs_performed_by_fkey;
alter table public.audit_logs add constraint audit_logs_performed_by_fkey
  foreign key (performed_by) references public.users(id) on delete set null;
alter table public.audit_logs drop constraint if exists audit_logs_target_user_fkey;
alter table public.audit_logs add constraint audit_logs_target_user_fkey
  foreign key (target_user) references public.users(id) on delete set null;

-- 5. Safe Unique Constraint on Schools
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'schools_name_unique') then
    alter table public.schools add constraint schools_name_unique unique (name);
  end if;
exception when others then null;
end $$;

-- 6. Permissions
grant usage on schema public to authenticated, anon;
grant select, insert, update, delete on public.users to authenticated;
grant select on public.users to anon;
grant all on all sequences in schema public to authenticated;
grant select on public.schools to anon, authenticated;
grant select on public.sections to anon, authenticated;

-- 7. Master Function: review_user_registration (Enforcing Full Multi-tier Hierarchy)
drop function if exists public.review_user_registration(uuid, text, uuid);
drop function if exists public.review_user_registration(jsonb);

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
  is_approve boolean := (lower(trim(p_decision)) in ('approve', 'approved'));
  target_role text;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  -- CRITICAL RULE: Self-approval is strictly forbidden
  if caller_id = p_user_id then
    raise exception 'Permission denied: Self-approval is strictly prohibited' using errcode = '42501';
  end if;

  select id, role, is_super_admin, is_attendance_teacher, attendance_grade, attendance_class, school_id
  into caller
  from public.users
  where id = caller_id;

  select id, role, requested_role, school_id, section_id, requested_grade, requested_class, full_name, email
  into target_user
  from public.users
  where id = p_user_id;

  if target_user.id is null then
    return jsonb_build_object('success', false, 'error', 'User registration not found');
  end if;

  target_role := coalesce(nullif(target_user.requested_role, ''), target_user.role, 'student');

  -- =========================================================================
  -- HIERARCHY VALIDATION:
  -- 1. Subadmins -> Super Admin ONLY
  -- 2. Teachers -> Subadmin of their school (or Super Admin)
  -- 3. Students -> Assigned class attendance teacher (or Subadmin / Super Admin)
  -- =========================================================================

  if caller.role = 'admin' or caller.is_super_admin is true then
    -- Super Admin can review and approve any account across all schools
    null;

  elsif caller.role = 'subadmin' then
    -- Subadmin cannot review other admins or subadmins
    if target_role in ('admin', 'subadmin') then
      raise exception 'Permission denied: Only the Super Administrator can review sub-administrator accounts' using errcode = '42501';
    end if;

    -- Subadmin must belong to an assigned school
    if caller.school_id is null then
      raise exception 'Permission denied: Sub-admin has no school assignment' using errcode = '42501';
    end if;

    -- Target must belong to subadmin's school (or be adopting it)
    if target_user.school_id is not null and target_user.school_id <> caller.school_id then
      raise exception 'Permission denied: Sub-admins can only review users from their own school' using errcode = '42501';
    end if;

  elsif caller.role = 'teacher' and caller.is_attendance_teacher is true then
    -- Attendance teacher can ONLY approve students of their designated class
    if target_role <> 'student' then
      raise exception 'Permission denied: Attendance teachers can only review student registrations' using errcode = '42501';
    end if;

    -- Match school if assigned
    if caller.school_id is not null and target_user.school_id is not null and target_user.school_id <> caller.school_id then
      raise exception 'Permission denied: You can only review students from your own school' using errcode = '42501';
    end if;

    -- Match assigned class (e.g. 9A)
    if caller.attendance_class is not null and
       (target_user.requested_class is null or
        lower(trim(target_user.requested_class)) <> lower(trim(caller.attendance_class))) then
      raise exception 'Permission denied: You can only approve students for your assigned class (%)', caller.attendance_class using errcode = '42501';
    end if;

  else
    raise exception 'Permission denied: Unauthorized to review user registrations' using errcode = '42501';
  end if;

  -- Apply approval or rejection to public.users
  update public.users
  set
    approval_status = case when is_approve then 'approved' else 'rejected' end,
    is_active = is_approve,
    role = case
      when is_approve and target_user.requested_role is not null then target_user.requested_role
      else role
    end,
    school_id = coalesce(p_school_id, target_user.school_id, caller.school_id)
  where id = p_user_id;

  if is_approve then
    -- Confirm email in auth.users so student/teacher can sign in immediately
    update auth.users
    set
      email_confirmed_at = coalesce(email_confirmed_at, now()),
      updated_at = now()
    where id = p_user_id;

    -- Auto-link section enrollment if target has section_id
    if target_user.section_id is not null then
      insert into public.student_sections (student_id, section_id)
      values (p_user_id, target_user.section_id)
      on conflict do nothing;
    end if;
  end if;

  return jsonb_build_object(
    'success', true,
    'status', case when is_approve then 'approved' else 'rejected' end,
    'id', p_user_id,
    'role', case when is_approve then target_role else target_user.role end
  );
end;
$$;

-- 8. JSONB Overload to support alternate parameter names without PGRST202
create or replace function public.review_user_registration(
  payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
begin
  return public.review_user_registration(
    p_user_id => coalesce(
      nullif(payload->>'p_user_id', ''),
      nullif(payload->>'user_id', ''),
      nullif(payload->>'id', '')
    )::uuid,
    p_decision => coalesce(
      payload->>'p_decision',
      payload->>'decision'
    ),
    p_school_id => nullif(
      coalesce(payload->>'p_school_id', payload->>'school_id', ''),
      ''
    )::uuid
  );
end;
$$;

grant execute on function public.review_user_registration(uuid, text, uuid) to authenticated;

-- 9. Master Function: delete_user_account (Protected Main Admin & School Scoping)
drop function if exists public.delete_user_account(uuid, uuid);
drop function if exists public.delete_user_account(uuid);
drop function if exists public.delete_user_account(jsonb);

create or replace function public.delete_user_account(
  p_user_id uuid
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

  select id, role, is_super_admin, is_attendance_teacher, attendance_grade, attendance_class, school_id
  into caller
  from public.users
  where id = caller_id;

  select id, email, role, is_super_admin, requested_class, school_id
  into target_user
  from public.users
  where id = p_user_id;

  if target_user.id is null then
    return jsonb_build_object('success', true, 'message', 'Account already deleted');
  end if;

  -- CRITICAL RULE: MAIN ADMIN ACCOUNT CAN NEVER BE DELETED BY ANYONE
  if target_user.is_super_admin is true or
     lower(target_user.email) in ('wondedev369@gmail.com', 'wondeadmin@admin.edu') or
     (target_user.role = 'admin' and caller.role = 'subadmin') then
    raise exception 'Permission denied: The Main Administrator account is protected and cannot be deleted' using errcode = '42501';
  end if;

  -- Self-deletion prevention for admins
  if caller_id = p_user_id and caller.role in ('admin', 'subadmin') then
    raise exception 'Permission denied: Administrators cannot delete their own account' using errcode = '42501';
  end if;

  -- Role-specific deletion validation:
  if caller.role = 'subadmin' and caller.is_super_admin is not true then
    if caller.school_id is not null and target_user.school_id is not null and target_user.school_id <> caller.school_id then
      raise exception 'Permission denied: Sub-admins can only delete accounts from their own school' using errcode = '42501';
    end if;
  elsif caller.role = 'teacher' then
    if target_user.role <> 'student' then
      raise exception 'Permission denied: Teachers can only delete student accounts' using errcode = '42501';
    end if;
    if caller.is_attendance_teacher = true and caller.attendance_class is not null and
       target_user.requested_class is not null and lower(trim(target_user.requested_class)) <> lower(trim(caller.attendance_class)) then
      raise exception 'Permission denied: Attendance teachers can only delete students of their assigned class (%)', caller.attendance_class using errcode = '42501';
    end if;
  elsif caller.role <> 'admin' and caller.is_super_admin is not true then
    raise exception 'Permission denied: Unauthorized to delete user accounts' using errcode = '42501';
  end if;

  -- Delete cascade across all user relations safely
  delete from public.answers where student_id = p_user_id;
  delete from public.quiz_attempts where student_id = p_user_id;
  delete from public.grades where student_id = p_user_id;
  delete from public.student_sections where student_id = p_user_id;
  delete from public.teacher_courses where teacher_id = p_user_id;
  delete from public.courses where teacher_id = p_user_id;
  delete from public.password_reset_requests where user_id = p_user_id;
  delete from public.audit_logs where performed_by = p_user_id or target_user = p_user_id;

  delete from public.users where id = p_user_id;
  delete from auth.users where id = p_user_id;

  return jsonb_build_object('success', true, 'id', p_user_id);
end;
$$;

-- Overload with jsonb payload to support alternate parameter names
create or replace function public.delete_user_account(
  payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
begin
  return public.delete_user_account(
    p_user_id => coalesce(
      nullif(payload->>'p_user_id', ''),
      nullif(payload->>'user_id', ''),
      nullif(payload->>'id', '')
    )::uuid
  );
end;
$$;

grant execute on function public.delete_user_account(uuid) to authenticated;

-- 10. Admin Create User with Phone & Gender Support
drop function if exists public.admin_create_user(text, text, text, text, text, uuid, uuid, text);
drop function if exists public.admin_create_user(text, text, text, text, text, uuid, uuid, text, text, text);

create or replace function public.admin_create_user(
  p_full_name text,
  p_username text,
  p_email text,
  p_password text,
  p_role text,
  p_school_id uuid default null,
  p_section_id uuid default null,
  p_subject text default null,
  p_phone_number text default null,
  p_gender text default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'extensions', 'pg_temp'
as $$
declare
  caller_id uuid := auth.uid();
  caller record;
  new_user_id uuid := gen_random_uuid();
  encrypted_pw text;
  clean_email text := lower(trim(p_email));
  clean_uname text := trim(p_username);
  effective_school uuid;
  assigned_class_val text := null;
  assigned_grade_val text := null;
  is_attendance boolean := false;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select id, role, is_super_admin, school_id, is_attendance_teacher, attendance_grade, attendance_class
  into caller
  from public.users
  where id = caller_id;

  if caller.role not in ('admin', 'subadmin', 'teacher') and caller.is_super_admin is not true then
    raise exception 'Permission denied: Unauthorized to create user accounts' using errcode = '42501';
  end if;

  -- Subadmin cannot create super admins
  if caller.role = 'subadmin' and p_role in ('admin', 'super_admin') then
    raise exception 'Permission denied: Sub-admins cannot create administrator accounts' using errcode = '42501';
  end if;

  -- Teacher can only create students of their designated class
  if caller.role = 'teacher' then
    if p_role <> 'student' then
      raise exception 'Teachers can only register student accounts' using errcode = '42501';
    end if;
    if caller.is_attendance_teacher is true and caller.attendance_class is not null then
      assigned_class_val := caller.attendance_class;
      assigned_grade_val := caller.attendance_grade;
    end if;
  end if;

  effective_school := coalesce(p_school_id, caller.school_id);
  encrypted_pw := extensions.crypt(p_password, extensions.gen_salt('bf'));

  -- Insert into auth.users
  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  ) values (
    '00000000-0000-0000-0000-000000000000',
    new_user_id,
    'authenticated',
    'authenticated',
    clean_email,
    encrypted_pw,
    now(),
    jsonb_build_object('provider', 'email', 'providers', array['email']),
    jsonb_build_object(
      'full_name', p_full_name,
      'username', clean_uname,
      'role', p_role,
      'school_id', effective_school,
      'phone_number', p_phone_number,
      'gender', p_gender
    ),
    now(),
    now()
  );

  -- Insert or update public.users
  insert into public.users (
    id,
    email,
    username,
    full_name,
    role,
    requested_role,
    school_id,
    section_id,
    assigned_subject,
    assigned_class,
    assigned_grade,
    phone_number,
    gender,
    approval_status,
    is_active,
    must_change_password,
    created_at
  ) values (
    new_user_id,
    clean_email,
    clean_uname,
    p_full_name,
    p_role,
    p_role,
    effective_school,
    p_section_id,
    p_subject,
    assigned_class_val,
    assigned_grade_val,
    p_phone_number,
    p_gender,
    'approved',
    true,
    false,
    now()
  ) on conflict (id) do update set
    email = excluded.email,
    username = excluded.username,
    full_name = excluded.full_name,
    role = excluded.role,
    school_id = excluded.school_id,
    section_id = excluded.section_id,
    assigned_subject = excluded.assigned_subject,
    phone_number = excluded.phone_number,
    gender = excluded.gender,
    approval_status = 'approved',
    is_active = true;

  if p_section_id is not null and p_role = 'student' then
    insert into public.student_sections (student_id, section_id)
    values (new_user_id, p_section_id)
    on conflict do nothing;
  end if;

  return jsonb_build_object(
    'success', true,
    'user_id', new_user_id,
    'username', clean_uname,
    'email', clean_email
  );
end;
$$;

grant execute on function public.admin_create_user(text, text, text, text, text, uuid, uuid, text, text, text) to authenticated;

-- 11. Signup Trigger: All self-registered users wait for approval
-- Subadmins -> Super Admin
-- Teachers -> Subadmin of their school
-- Students -> Assigned Attendance Teacher (e.g. 9A)
create or replace function public.handle_quiz_app_user_signup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_role text := coalesce(new.raw_user_meta_data ->> 'requested_role', 'student');
  school_id_value uuid;
  section_id_value uuid;
  requested_grade_value text := nullif(
    btrim(coalesce(new.raw_user_meta_data ->> 'requested_grade', '')), ''
  );
  requested_class_value text := nullif(
    btrim(coalesce(new.raw_user_meta_data ->> 'requested_class', '')), ''
  );
  requested_subject_value text := nullif(
    btrim(coalesce(new.raw_user_meta_data ->> 'requested_subject', '')), ''
  );
  username_value text := btrim(coalesce(new.raw_user_meta_data ->> 'username', ''));
  full_name_value text := btrim(coalesce(new.raw_user_meta_data ->> 'full_name', ''));
  phone_value text := nullif(btrim(coalesce(new.raw_user_meta_data ->> 'phone_number', new.raw_user_meta_data ->> 'phone', '')), '');
  gender_value text := nullif(btrim(coalesce(new.raw_user_meta_data ->> 'gender', '')), '');
begin
  if requested_role in ('admin', 'super_admin') then
    raise exception 'Administrator accounts are invitation-only';
  elsif requested_role not in ('student', 'teacher', 'subadmin') then
    raise exception 'Unsupported account role request';
  end if;

  if length(full_name_value) < 3 or length(full_name_value) > 100
     or array_length(regexp_split_to_array(full_name_value, '[[:space:]]+'), 1) < 2 then
    raise exception 'Enter your first and last name';
  end if;

  school_id_value := nullif(new.raw_user_meta_data ->> 'school_id', '')::uuid;
  if requested_role = 'student' then
    section_id_value := nullif(new.raw_user_meta_data ->> 'section_id', '')::uuid;
  end if;

  insert into public.users (
    id, email, username, full_name, role, school_id, section_id,
    phone_number, gender,
    must_change_password, requested_role, approval_status, is_active,
    requested_grade, requested_class, requested_subject, created_at
  ) values (
    new.id, lower(new.email), username_value, full_name_value, 'student',
    school_id_value, section_id_value,
    phone_value, gender_value,
    false, requested_role,
    'pending', false,
    requested_grade_value, requested_class_value, requested_subject_value, now()
  )
  on conflict (id) do update
    set email = excluded.email,
        username = excluded.username,
        full_name = excluded.full_name,
        phone_number = coalesce(excluded.phone_number, public.users.phone_number),
        gender = coalesce(excluded.gender, public.users.gender),
        school_id = coalesce(excluded.school_id, public.users.school_id),
        section_id = coalesce(excluded.section_id, public.users.section_id),
        requested_grade = coalesce(excluded.requested_grade, public.users.requested_grade),
        requested_class = coalesce(excluded.requested_class, public.users.requested_class),
        requested_subject = coalesce(excluded.requested_subject, public.users.requested_subject);

  return new;
end;
$$;

-- 12. Reload schema cache for PostgREST
notify pgrst, 'reload schema';

commit;
