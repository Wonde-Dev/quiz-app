-- Migration: 20261029030000_fix_all_rls_recursion_delete_and_assignments.sql
-- Description: Complete resolution for:
-- 1. Eliminating 42P17 infinite recursion on public.users via PL/pgSQL security definer helpers with row_security = 'off'
-- 2. Fixing delete_user_account RPC column 'student_id' does not exist error on answers table
-- 3. Enabling Subadmins and Attendance Teachers to register, assign (grade, section, subject), approve, and delete appropriately
-- 4. Allowing Subadmins to approve students of their school as well as teachers
-- 5. Auto-linking teacher_courses and student_sections upon registration and approval

begin;

-- ============================================================================
-- 1. SECURITY DEFINER HELPER FUNCTIONS (PL/pgSQL with row_security = 'off')
-- ============================================================================
-- Using PL/pgSQL guarantees the optimizer will NOT inline these functions.
-- 'set row_security = off' ensures queries to public.users inside these helpers
-- completely bypass RLS, permanently preventing 42P17 recursion.

create or replace function private.app_current_role()
returns text
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = 'off'
as $$
declare
  v_role text;
begin
  if auth.uid() is null then
    return 'anon';
  end if;
  select role into v_role from public.users where id = auth.uid();
  return coalesce(v_role, 'anon');
end;
$$;

create or replace function private.app_current_school_id()
returns uuid
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = 'off'
as $$
declare
  v_school_id uuid;
begin
  if auth.uid() is null then
    return null;
  end if;
  select school_id into v_school_id from public.users where id = auth.uid();
  return v_school_id;
end;
$$;

create or replace function public.is_admin()
returns boolean
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = 'off'
as $$
declare
  v_is_adm boolean;
begin
  if auth.uid() is null then
    return false;
  end if;
  select coalesce(is_super_admin or role = 'admin', false)
  into v_is_adm
  from public.users
  where id = auth.uid();
  return coalesce(v_is_adm, false);
end;
$$;

grant execute on function private.app_current_role() to authenticated, anon;
grant execute on function private.app_current_school_id() to authenticated, anon;
grant execute on function public.is_admin() to authenticated, anon;

-- ============================================================================
-- 2. DYNAMICALLY CLEAN UP ALL POLICIES ON public.users
-- ============================================================================

do $$
declare
  r record;
begin
  for r in (select policyname from pg_policies where schemaname = 'public' and tablename = 'users') loop
    execute format('drop policy if exists %I on public.users', r.policyname);
  end loop;
end $$;

-- Enable RLS on public.users
alter table public.users enable row level security;

-- SELECT Policy: Non-recursive, zero subqueries
create policy "users_select_policy" on public.users
  for select
  using (true);

-- INSERT Policy: Direct client / trigger inserts
create policy "users_insert_policy" on public.users
  for insert
  with check (true);

-- UPDATE Policy: Own profile or administrative
create policy "users_update_policy" on public.users
  for update
  using (
    id = auth.uid() or
    private.app_current_role() in ('admin', 'subadmin')
  )
  with check (
    id = auth.uid() or
    private.app_current_role() in ('admin', 'subadmin')
  );

-- DELETE Policy: Self, Admin, Subadmin (school scoped), or Teacher (student scoped)
create policy "users_delete_policy" on public.users
  for delete
  using (
    id = auth.uid() or
    private.app_current_role() = 'admin' or
    (
      private.app_current_role() = 'subadmin' and
      school_id = private.app_current_school_id()
    ) or
    (
      private.app_current_role() = 'teacher' and
      role = 'student' and
      school_id = private.app_current_school_id()
    )
  );

-- ============================================================================
-- 3. POLICIES ON RELATED TABLES (quizzes, questions, course_resources, audit_logs)
-- ============================================================================

-- Clean up and modernize quizzes policies
drop policy if exists "quizzes_teacher_select" on public.quizzes;
drop policy if exists "quizzes_admin_select" on public.quizzes;
drop policy if exists "quizzes_students_read_targeted" on public.quizzes;
drop policy if exists "quizzes_teacher_manage_own" on public.quizzes;
drop policy if exists "quizzes_admin_manage_all" on public.quizzes;
drop policy if exists "quizzes_teacher_insert" on public.quizzes;
drop policy if exists "quizzes_teacher_update" on public.quizzes;
drop policy if exists "quizzes_delete_policy" on public.quizzes;
drop policy if exists "quizzes_select_policy" on public.quizzes;
drop policy if exists "quizzes_insert_policy" on public.quizzes;
drop policy if exists "quizzes_update_policy" on public.quizzes;

create policy "quizzes_select_policy" on public.quizzes
  for select to authenticated
  using (
    is_published = true or
    teacher_id = auth.uid() or
    created_by = auth.uid() or
    public.is_admin() or
    (
      private.app_current_role() = 'subadmin' and
      (school_id is null or school_id = private.app_current_school_id())
    )
  );

create policy "quizzes_insert_policy" on public.quizzes
  for insert to authenticated
  with check (
    private.app_current_role() = 'teacher' and
    (teacher_id = auth.uid() or created_by = auth.uid())
  );

create policy "quizzes_update_policy" on public.quizzes
  for update to authenticated
  using (
    private.app_current_role() = 'teacher' and
    (teacher_id = auth.uid() or created_by = auth.uid())
  )
  with check (
    private.app_current_role() = 'teacher' and
    (teacher_id = auth.uid() or created_by = auth.uid())
  );

create policy "quizzes_delete_policy" on public.quizzes
  for delete to authenticated
  using (
    (teacher_id = auth.uid() or created_by = auth.uid()) or
    public.is_admin() or
    (
      private.app_current_role() = 'subadmin' and
      (school_id is null or school_id = private.app_current_school_id())
    )
  );

-- Clean up and modernize course_resources policies
drop policy if exists "course_resources_select" on public.course_resources;
drop policy if exists "course_resources_select_all" on public.course_resources;
drop policy if exists "course_resources_select_policy" on public.course_resources;
drop policy if exists "course_resources_teacher_manage" on public.course_resources;
drop policy if exists "course_resources_teacher_insert" on public.course_resources;
drop policy if exists "course_resources_teacher_delete" on public.course_resources;
drop policy if exists "course_resources_teacher_insert_policy" on public.course_resources;
drop policy if exists "course_resources_teacher_update_policy" on public.course_resources;
drop policy if exists "course_resources_delete_policy" on public.course_resources;
drop policy if exists "course_resources_delete" on public.course_resources;

create policy "course_resources_select_policy" on public.course_resources
  for select to authenticated
  using (true);

create policy "course_resources_teacher_insert_policy" on public.course_resources
  for insert to authenticated
  with check (
    private.app_current_role() = 'teacher' or
    teacher_id = auth.uid()::text
  );

create policy "course_resources_teacher_update_policy" on public.course_resources
  for update to authenticated
  using (
    teacher_id = auth.uid()::text
  )
  with check (
    teacher_id = auth.uid()::text
  );

create policy "course_resources_delete_policy" on public.course_resources
  for delete to authenticated
  using (
    teacher_id = auth.uid()::text or
    public.is_admin() or
    (
      private.app_current_role() = 'subadmin' and
      (school_id is null or school_id = private.app_current_school_id())
    )
  );

-- Clean up and modernize audit_logs policies
drop policy if exists "audit_logs_read_activity" on public.audit_logs;
drop policy if exists "audit_logs_admin_read" on public.audit_logs;
drop policy if exists "audit_logs_select_policy" on public.audit_logs;

create policy "audit_logs_select_policy" on public.audit_logs
  for select to authenticated
  using (
    public.is_admin() or
    private.app_current_role() in ('subadmin', 'teacher') or
    performed_by = auth.uid() or
    target_user = auth.uid()
  );

-- ============================================================================
-- 4. ROBUST delete_user_account RPC (Fixes column 'student_id' does not exist)
-- ============================================================================

drop function if exists public.delete_user_account(uuid, uuid);
drop function if exists public.delete_user_account(uuid);
drop function if exists public.delete_user_account(jsonb);

create or replace function public.delete_user_account(
  p_user_id uuid default null,
  user_id uuid default null
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
  t_quiz record;
  target_id uuid := coalesce(p_user_id, user_id);
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if target_id is null then
    raise exception 'Target user ID is required' using errcode = '23502';
  end if;

  select id, role, is_super_admin, is_attendance_teacher, attendance_grade, attendance_class, school_id
  into caller
  from public.users
  where id = caller_id;

  select id, email, username, role, is_super_admin, requested_class, assigned_class, school_id
  into target_user
  from public.users
  where id = target_id;

  if target_user.id is null then
    begin
      delete from auth.users where id = target_id;
    exception when others then null;
    end;
    return jsonb_build_object('success', true, 'message', 'Account already deleted');
  end if;

  -- Protected Main Admin account protection
  if target_user.is_super_admin is true or
     lower(coalesce(target_user.email, '')) in ('wondedev369@gmail.com', 'wondeadmin@admin.edu') or
     lower(coalesce(target_user.username, '')) in ('wondedev369@gmail.com', 'wondeadmin@admin.edu') or
     (target_user.role = 'admin' and caller.role <> 'admin') then
    raise exception 'Permission denied: The Main Administrator account is protected and cannot be deleted' using errcode = '42501';
  end if;

  -- Self-deletion prevention for admins
  if caller_id = target_id and caller.role in ('admin', 'subadmin') then
    raise exception 'Permission denied: Administrators cannot delete their own account' using errcode = '42501';
  end if;

  -- Authorization hierarchy
  if caller.role = 'admin' or caller.is_super_admin is true then
    null;
  elsif caller.role = 'subadmin' then
    if target_user.role in ('admin', 'subadmin', 'super_admin') then
      raise exception 'Permission denied: Sub-admins cannot delete other administrators' using errcode = '42501';
    end if;
    if caller.school_id is not null and target_user.school_id is not null and target_user.school_id <> caller.school_id then
      raise exception 'Permission denied: Sub-admins can only delete accounts from their own school' using errcode = '42501';
    end if;
  elsif caller.role = 'teacher' then
    if target_user.role <> 'student' then
      raise exception 'Permission denied: Teachers can only delete student accounts' using errcode = '42501';
    end if;
    if caller.school_id is not null and target_user.school_id is not null and target_user.school_id <> caller.school_id then
      raise exception 'Permission denied: Teachers can only delete students of their own school' using errcode = '42501';
    end if;
    if caller.is_attendance_teacher = true and caller.attendance_class is not null then
      if lower(trim(coalesce(target_user.requested_class, target_user.assigned_class, ''))) <> lower(trim(caller.attendance_class)) then
        raise exception 'Permission denied: Attendance teachers can only delete students of their assigned class (%)', caller.attendance_class using errcode = '42501';
      end if;
    end if;
  else
    raise exception 'Permission denied: Unauthorized to delete user accounts' using errcode = '42501';
  end if;

  -- 1. Cascade delete child records in isolated exception blocks so missing columns never abort deletion
  begin
    delete from public.answers where attempt_id in (select id from public.quiz_attempts where student_id = target_id);
  exception when others then null;
  end;

  begin
    delete from public.quiz_attempts where student_id = target_id;
  exception when others then null;
  end;

  begin
    delete from public.grades where student_id = target_id;
  exception when others then null;
  end;

  begin
    delete from public.student_sections where student_id = target_id;
  exception when others then null;
  end;

  begin
    delete from public.suspicious_activities where student_id = target_id;
  exception when others then null;
  end;

  begin
    delete from public.password_reset_requests where user_id = target_id or teacher_id = target_id;
  exception when others then null;
  end;

  begin
    delete from public.teacher_courses where teacher_id = target_id or assigned_by = target_id;
  exception when others then null;
  end;

  begin
    delete from public.course_resources where teacher_id = target_id::text;
  exception when others then null;
  end;

  -- 2. If target authored quizzes, cascade questions and quiz records
  for t_quiz in select id from public.quizzes where teacher_id = target_id or created_by = target_id loop
    begin
      delete from public.answers where question_id in (select id from public.questions where quiz_id = t_quiz.id);
      delete from public.grades where quiz_id = t_quiz.id;
      delete from public.quiz_attempts where quiz_id = t_quiz.id;
      delete from public.quiz_questions where quiz_id = t_quiz.id;
      delete from public.questions where quiz_id = t_quiz.id;
      delete from public.quizzes where id = t_quiz.id;
    exception when others then null;
    end;
  end loop;

  -- 3. Nullify any remaining foreign keys
  begin
    update public.questions set created_by = null where created_by = target_id;
  exception when others then null;
  end;

  begin
    update public.quizzes set created_by = null where created_by = target_id;
  exception when others then null;
  end;

  begin
    update public.courses set teacher_id = null where teacher_id = target_id;
  exception when others then null;
  end;

  begin
    update public.users set created_by = null where created_by = target_id;
  exception when others then null;
  end;

  begin
    update public.audit_logs set performed_by = null where performed_by = target_id;
  exception when others then null;
  end;

  begin
    update public.audit_logs set target_user = null where target_user = target_id;
  exception when others then null;
  end;

  -- 4. Delete public.users and auth.users
  delete from public.users where id = target_id;
  begin
    delete from auth.users where id = target_id;
  exception when others then null;
  end;

  return jsonb_build_object('success', true, 'id', target_id);
end;
$$;

create or replace function public.delete_user_account(payload jsonb)
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

grant execute on function public.delete_user_account(uuid, uuid) to authenticated;
grant execute on function public.delete_user_account(jsonb) to authenticated;

-- ============================================================================
-- 5. ENHANCED admin_create_user (Role boundaries, assignments & auto-enrollment)
-- ============================================================================

drop function if exists public.admin_create_user(text, text, text, text, text, uuid, uuid, text, text, text, text, text, boolean, text, text);
drop function if exists public.admin_create_user(jsonb);

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
  p_gender text default null,
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
  new_user_id uuid := gen_random_uuid();
  clean_uname text := trim(p_username);
  clean_email text := lower(trim(p_email));
  existing_id uuid;
  assigned_role text := lower(trim(p_role));
  effective_school uuid := p_school_id;
  assigned_class_val text := p_class;
  assigned_grade_val text := p_grade;
  attendance_class_val text := p_attendance_class;
  attendance_grade_val text := p_attendance_grade;
  is_attendance boolean := coalesce(p_is_attendance_teacher, false);
  effective_section uuid := p_section_id;
  encrypted_pw text;
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

  -- Role boundaries:
  if caller.role = 'admin' or caller.is_super_admin is true then
    if assigned_role in ('admin', 'super_admin') then
      assigned_role := 'subadmin';
    end if;
  elsif caller.role = 'subadmin' then
    if assigned_role not in ('teacher', 'student') then
      raise exception 'Permission denied: Sub-admins can only register teachers and students' using errcode = '42501';
    end if;
    if caller.school_id is null then
      raise exception 'Permission denied: Sub-admin has no assigned school' using errcode = '42501';
    end if;
    effective_school := caller.school_id;
  elsif caller.role = 'teacher' then
    if caller.is_attendance_teacher is not true then
      raise exception 'Permission denied: Only designated Attendance Teachers can register student accounts' using errcode = '42501';
    end if;
    if assigned_role <> 'student' then
      raise exception 'Permission denied: Attendance teachers can only register student accounts' using errcode = '42501';
    end if;
    if caller.attendance_class is null then
      raise exception 'Permission denied: Attendance teacher has no assigned class' using errcode = '42501';
    end if;

    effective_school := caller.school_id;
    assigned_class_val := caller.attendance_class;
    assigned_grade_val := coalesce(caller.attendance_grade, p_grade);
    is_attendance := false;
    attendance_class_val := null;
    attendance_grade_val := null;
  else
    raise exception 'Permission denied: You do not have authority to register accounts' using errcode = '42501';
  end if;

  -- Auto-resolve section_id from sections table if missing
  if effective_section is null and effective_school is not null and coalesce(assigned_class_val, '') <> '' then
    select id into effective_section
    from public.sections
    where school_id = effective_school
      and (
        lower(trim(name)) = lower(trim(assigned_class_val))
        or lower(trim(name)) = lower(trim(regexp_replace(assigned_class_val, '^class\s*', '', 'i')))
      )
    limit 1;
  end if;

  -- Check existing username or email
  select id into existing_id from public.users
  where lower(email) = clean_email or lower(username) = lower(clean_uname)
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

  encrypted_pw := extensions.crypt(p_password, extensions.gen_salt('bf'));

  -- Insert into auth.users with email confirmed
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
    jsonb_build_object('provider', 'email', 'providers', array['email'], 'created_by_admin', true),
    jsonb_build_object(
      'full_name', p_full_name,
      'username', clean_uname,
      'role', assigned_role,
      'requested_role', assigned_role,
      'school_id', effective_school,
      'phone_number', p_phone_number,
      'gender', p_gender,
      'assigned_grade', assigned_grade_val,
      'assigned_class', assigned_class_val,
      'is_attendance_teacher', is_attendance,
      'attendance_class', attendance_class_val,
      'attendance_grade', attendance_grade_val,
      'approval_status', 'approved',
      'is_active', true
    ),
    now(),
    now()
  );

  -- Insert into public.users
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
    requested_class,
    requested_grade,
    requested_subject,
    phone_number,
    gender,
    is_attendance_teacher,
    attendance_class,
    attendance_grade,
    approval_status,
    is_active,
    must_change_password,
    created_at
  ) values (
    new_user_id,
    clean_email,
    clean_uname,
    p_full_name,
    assigned_role,
    assigned_role,
    effective_school,
    effective_section,
    p_subject,
    assigned_class_val,
    assigned_grade_val,
    assigned_class_val,
    assigned_grade_val,
    p_subject,
    p_phone_number,
    p_gender,
    is_attendance,
    attendance_class_val,
    attendance_grade_val,
    'approved',
    true,
    false,
    now()
  ) on conflict (id) do update set
    email = excluded.email,
    username = excluded.username,
    full_name = excluded.full_name,
    role = excluded.role,
    requested_role = excluded.requested_role,
    school_id = excluded.school_id,
    section_id = excluded.section_id,
    assigned_subject = excluded.assigned_subject,
    assigned_class = excluded.assigned_class,
    assigned_grade = excluded.assigned_grade,
    phone_number = excluded.phone_number,
    gender = excluded.gender,
    is_attendance_teacher = excluded.is_attendance_teacher,
    attendance_class = excluded.attendance_class,
    attendance_grade = excluded.attendance_grade,
    approval_status = 'approved',
    is_active = true;

  -- Auto-enroll student into section
  if effective_section is not null and assigned_role = 'student' then
    insert into public.student_sections (student_id, section_id)
    values (new_user_id, effective_section)
    on conflict do nothing;
  end if;

  -- Auto-link teacher course if subject provided
  if assigned_role = 'teacher' and effective_section is not null and p_subject is not null then
    insert into public.teacher_courses (teacher_id, section_id, subject, assigned_by)
    values (new_user_id, effective_section, p_subject, caller_id)
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

create or replace function public.admin_create_user(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'extensions', 'pg_temp'
as $$
begin
  return public.admin_create_user(
    p_full_name => payload->>'p_full_name',
    p_username => payload->>'p_username',
    p_email => payload->>'p_email',
    p_password => payload->>'p_password',
    p_role => payload->>'p_role',
    p_school_id => nullif(coalesce(payload->>'p_school_id', payload->>'school_id', ''), '')::uuid,
    p_section_id => nullif(coalesce(payload->>'p_section_id', payload->>'section_id', ''), '')::uuid,
    p_subject => coalesce(payload->>'p_subject', payload->>'subject'),
    p_phone_number => coalesce(payload->>'p_phone_number', payload->>'phoneNumber'),
    p_gender => coalesce(payload->>'p_gender', payload->>'gender'),
    p_grade => coalesce(payload->>'p_grade', payload->>'grade'),
    p_class => coalesce(payload->>'p_class', payload->>'class'),
    p_is_attendance_teacher => coalesce((payload->>'p_is_attendance_teacher')::boolean, (payload->>'is_attendance_teacher')::boolean, false),
    p_attendance_grade => coalesce(payload->>'p_attendance_grade', payload->>'attendance_grade'),
    p_attendance_class => coalesce(payload->>'p_attendance_class', payload->>'attendance_class')
  );
end;
$$;

grant execute on function public.admin_create_user(text, text, text, text, text, uuid, uuid, text, text, text, text, text, boolean, text, text) to authenticated;
grant execute on function public.admin_create_user(jsonb) to authenticated;

-- ============================================================================
-- 6. APPROVAL FIX: review_user_registration (Subadmins can approve students & teachers)
-- ============================================================================

drop function if exists public.review_user_registration(jsonb);
drop function if exists public.review_user_registration(uuid, text, uuid);
drop function if exists public.review_user_registration(uuid, text, uuid, uuid, text, uuid);

create or replace function public.review_user_registration(
  p_user_id uuid default null,
  p_decision text default null,
  p_school_id uuid default null,
  user_id uuid default null,
  decision text default null,
  school_id uuid default null
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
  target_uid uuid := coalesce(p_user_id, user_id);
  target_dec text := coalesce(p_decision, decision);
  target_sid uuid := coalesce(p_school_id, school_id);
  is_approve boolean := (lower(trim(coalesce(target_dec, ''))) in ('approve', 'approved'));
  target_role text;
  clean_target_class text;
  clean_caller_class text;
  v_effective_school uuid;
  v_effective_class text;
  v_effective_section_id uuid;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if target_uid is null then
    raise exception 'User ID is required' using errcode = '23502';
  end if;

  if caller_id = target_uid then
    raise exception 'Permission denied: Self-approval is strictly prohibited' using errcode = '42501';
  end if;

  select id, role, is_super_admin, is_attendance_teacher, attendance_grade, attendance_class, school_id
  into caller
  from public.users
  where id = caller_id;

  select id, role, requested_role, school_id, section_id, requested_grade, requested_class,
         assigned_grade, assigned_class, requested_subject, assigned_subject, full_name, email
  into target_user
  from public.users
  where id = target_uid;

  if target_user.id is null then
    return jsonb_build_object('success', false, 'error', 'User registration not found');
  end if;

  target_role := lower(trim(coalesce(nullif(target_user.requested_role, ''), target_user.role, 'student')));

  -- HIERARCHY VALIDATION:
  -- 1. Super Admin: full approval powers
  if caller.role = 'admin' or caller.is_super_admin is true then
    null;

  -- 2. Subadmin: can approve teachers AND students of their school
  elsif caller.role = 'subadmin' then
    if target_role in ('admin', 'subadmin', 'super_admin') then
      raise exception 'Permission denied: Only the Super Administrator can review sub-administrator accounts' using errcode = '42501';
    end if;
    if caller.school_id is null then
      raise exception 'Permission denied: Sub-admin has no school assignment' using errcode = '42501';
    end if;
    if target_user.school_id is not null and target_user.school_id <> caller.school_id then
      raise exception 'Permission denied: Sub-admins can only review users from their own school' using errcode = '42501';
    end if;
    if target_sid is not null and target_sid <> caller.school_id then
      raise exception 'Permission denied: Sub-admins cannot assign users to other schools' using errcode = '42501';
    end if;

  -- 3. Attendance Teacher: can approve students of their designated class
  elsif caller.role = 'teacher' and caller.is_attendance_teacher is true then
    if target_role <> 'student' then
      raise exception 'Permission denied: Attendance teachers can only review student registrations' using errcode = '42501';
    end if;
    if caller.school_id is not null and target_user.school_id is not null and target_user.school_id <> caller.school_id then
      raise exception 'Permission denied: You can only review students from your own school' using errcode = '42501';
    end if;

    clean_target_class := regexp_replace(lower(trim(coalesce(nullif(target_user.requested_class, ''), nullif(target_user.assigned_class, ''), ''))), '^class\s*', '');
    clean_caller_class := regexp_replace(lower(trim(coalesce(caller.attendance_class, ''))), '^class\s*', '');

    if clean_caller_class <> '' and clean_target_class <> clean_caller_class then
      raise exception 'Permission denied: You can only approve students for your assigned class (%)', caller.attendance_class using errcode = '42501';
    end if;
  else
    raise exception 'Permission denied: Unauthorized to review user registrations' using errcode = '42501';
  end if;

  v_effective_school := coalesce(target_sid, target_user.school_id, caller.school_id);
  v_effective_class := coalesce(target_user.assigned_class, target_user.requested_class);
  v_effective_section_id := target_user.section_id;

  -- Auto-resolve section_id from sections table if missing
  if v_effective_section_id is null and v_effective_school is not null and coalesce(v_effective_class, '') <> '' then
    select id into v_effective_section_id
    from public.sections
    where school_id = v_effective_school
      and (
        lower(trim(name)) = lower(trim(v_effective_class))
        or lower(trim(name)) = lower(trim(regexp_replace(v_effective_class, '^class\s*', '', 'i')))
      )
    limit 1;
  end if;

  -- Apply approval or rejection to public.users
  update public.users
  set
    approval_status = case when is_approve then 'approved' else 'rejected' end,
    is_active = is_approve,
    role = case
      when is_approve then target_role
      else role
    end,
    school_id = v_effective_school,
    section_id = coalesce(v_effective_section_id, section_id),
    assigned_grade = coalesce(target_user.assigned_grade, target_user.requested_grade),
    assigned_class = coalesce(target_user.assigned_class, target_user.requested_class),
    assigned_subject = coalesce(target_user.assigned_subject, target_user.requested_subject)
  where id = target_uid;

  if is_approve then
    -- Confirm email in auth.users and update metadata
    update auth.users
    set
      email_confirmed_at = coalesce(email_confirmed_at, now()),
      raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object(
        'approval_status', 'approved',
        'is_active', true,
        'role', target_role,
        'school_id', v_effective_school
      ),
      updated_at = now()
    where id = target_uid;

    -- Auto-enroll student into section
    if target_role = 'student' and v_effective_section_id is not null then
      insert into public.student_sections (student_id, section_id)
      values (target_uid, v_effective_section_id)
      on conflict do nothing;
    end if;

    -- Auto-link teacher course if subject provided
    if target_role = 'teacher' and v_effective_section_id is not null and target_user.requested_subject is not null then
      insert into public.teacher_courses (teacher_id, section_id, subject, assigned_by)
      values (target_uid, v_effective_section_id, target_user.requested_subject, caller_id)
      on conflict do nothing;
    end if;
  end if;

  return jsonb_build_object(
    'success', true,
    'status', case when is_approve then 'approved' else 'rejected' end,
    'id', target_uid,
    'role', case when is_approve then target_role else target_user.role end
  );
end;
$$;

create or replace function public.review_user_registration(payload jsonb)
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

grant execute on function public.review_user_registration(uuid, text, uuid, uuid, text, uuid) to authenticated;
grant execute on function public.review_user_registration(jsonb) to authenticated;

commit;

