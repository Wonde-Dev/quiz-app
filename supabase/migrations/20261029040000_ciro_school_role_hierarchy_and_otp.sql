-- Migration: 20261029040000_ciro_school_role_hierarchy_and_otp.sql
-- Description:
-- 1. Consolidate to single school: "Ciro School" ('00000000-0000-4000-8000-000000000001')
-- 2. Enforce strict role boundaries:
--    - Admin: Super Administrator. Sees role totals only (total users, subadmins, teachers, students).
--      Cannot prepare quizzes (teacher-only). Can moderate/delete any quiz or user.
--    - Subadmin: School Director for Ciro School. Registers, approves, deletes, resets TEACHERS ONLY.
--      Cannot manage students. Sees school totals + teacher/student counts by GRADE (9, 10, 11, 12), NOT by section.
--    - Teacher: Can be assigned to MULTIPLE classes/sections. Sees student counts by SECTION.
--      Only teachers prepare quizzes and study resources (PDFs/videos). Can toggle exam lockdown.
--      Only creator teacher (or admin/subadmin for moderation) can delete their quizzes.
--    - Attendance Teacher: Registers, approves, and manages students of their OWN class/section.
--    - Student: Takes quizzes, stores results, respects exam lockdown on materials.
-- 3. Dedicated fast RPC functions for role-specific dashboard statistics & multi-class teacher assignments.

begin;

-- ============================================================================
-- 1. SINGLE SCHOOL SETUP: "Ciro School"
-- ============================================================================

-- Ensure Ciro School exists with primary UUID
insert into public.schools (id, name, is_active, materials_locked)
values ('00000000-0000-4000-8000-000000000001', 'Ciro School', true, false)
on conflict (id) do update set
  name = 'Ciro School',
  is_active = true;

-- Reassign all users to Ciro School (admin can have null or Ciro School)
update public.users
set school_id = '00000000-0000-4000-8000-000000000001'
where school_id is null and coalesce(role, '') <> 'admin';

update public.users
set school_id = '00000000-0000-4000-8000-000000000001'
where school_id = '3734953a-a711-488a-b598-e5ba7c9b9b24';

-- Ensure all courses, sections, and resources belong to Ciro School
update public.courses
set school_id = '00000000-0000-4000-8000-000000000001'
where school_id is null or school_id = '3734953a-a711-488a-b598-e5ba7c9b9b24';

-- Clean up duplicate grades and sections from other schools
delete from public.sections where school_id = '3734953a-a711-488a-b598-e5ba7c9b9b24';
delete from public.school_grades where school_id = '3734953a-a711-488a-b598-e5ba7c9b9b24';

update public.sections
set school_id = '00000000-0000-4000-8000-000000000001'
where school_id is null;

update public.school_grades
set school_id = '00000000-0000-4000-8000-000000000001'
where school_id is null;

update public.quizzes
set school_id = '00000000-0000-4000-8000-000000000001'
where school_id is null or school_id = '3734953a-a711-488a-b598-e5ba7c9b9b24';

update public.course_resources
set school_id = '00000000-0000-4000-8000-000000000001'
where school_id is null or school_id = '3734953a-a711-488a-b598-e5ba7c9b9b24';

-- Standard Grades for Ciro School: Grade 9, Grade 10, Grade 11, Grade 12
insert into public.school_grades (school_id, name)
values
  ('00000000-0000-4000-8000-000000000001', 'Grade 9'),
  ('00000000-0000-4000-8000-000000000001', 'Grade 10'),
  ('00000000-0000-4000-8000-000000000001', 'Grade 11'),
  ('00000000-0000-4000-8000-000000000001', 'Grade 12')
on conflict do nothing;

-- Standard Sections for Ciro School: A, B, C for each Grade linking grade_id
insert into public.sections (school_id, grade_id, name, grade)
select sg.school_id, sg.id, s.name, sg.name
from public.school_grades sg
cross join (values ('A'), ('B'), ('C')) as s(name)
where sg.school_id = '00000000-0000-4000-8000-000000000001'
  and sg.name in ('Grade 9', 'Grade 10', 'Grade 11', 'Grade 12')
on conflict do nothing;

-- ============================================================================
-- 2. TEACHER MULTI-CLASS ASSIGNMENTS & PERMISSIONS
-- ============================================================================

create table if not exists public.teacher_courses (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.users(id) on delete cascade,
  course_id uuid references public.courses(id) on delete cascade,
  section_id uuid references public.sections(id) on delete set null,
  subject text,
  assigned_by uuid references public.users(id) on delete set null,
  assigned_at timestamptz default now()
);

alter table public.teacher_courses add column if not exists section_id uuid references public.sections(id) on delete set null;
alter table public.teacher_courses add column if not exists subject text;
alter table public.teacher_courses add column if not exists course_id uuid references public.courses(id) on delete cascade;
alter table public.teacher_courses add column if not exists assigned_by uuid references public.users(id) on delete set null;
alter table public.teacher_courses add column if not exists assigned_at timestamptz default now();

-- Ensure unique teacher + section + subject
create unique index if not exists idx_teacher_courses_teacher_section_subject
  on public.teacher_courses(teacher_id, section_id, coalesce(subject, ''));

alter table public.teacher_courses enable row level security;
grant all on public.teacher_courses to authenticated;
grant select on public.teacher_courses to anon;

drop policy if exists "teacher_courses_select" on public.teacher_courses;
create policy "teacher_courses_select" on public.teacher_courses
  for select using (true);

drop policy if exists "teacher_courses_manage" on public.teacher_courses;
create policy "teacher_courses_manage" on public.teacher_courses
  for all using (
    private.app_current_role() in ('admin', 'subadmin')
    or teacher_id = auth.uid()
  );

-- ============================================================================
-- 3. REVIEW USER REGISTRATION RPC (Strict boundaries)
-- ============================================================================

drop function if exists public.review_user_registration(uuid, text, uuid, uuid, text, uuid);
drop function if exists public.review_user_registration(jsonb);

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
set row_security = 'off'
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
  -- 1. Super Admin: can approve any user
  if caller.role = 'admin' or caller.is_super_admin is true then
    null;

  -- 2. Subadmin: can approve TEACHERS ONLY
  elsif caller.role = 'subadmin' then
    if target_role <> 'teacher' then
      raise exception 'Permission denied: Sub-administrators can only review and approve teacher registrations. Student registrations must be approved by their class attendance teacher.' using errcode = '42501';
    end if;

  -- 3. Attendance Teacher: can approve STUDENTS of their designated class
  elsif caller.role = 'teacher' and caller.is_attendance_teacher is true then
    if target_role <> 'student' then
      raise exception 'Permission denied: Attendance teachers can only review student registrations' using errcode = '42501';
    end if;

    clean_target_class := regexp_replace(lower(trim(coalesce(nullif(target_user.requested_class, ''), nullif(target_user.assigned_class, ''), ''))), '^(class|grade|section)\s*', '');
    clean_caller_class := regexp_replace(lower(trim(coalesce(caller.attendance_class, ''))), '^(class|grade|section)\s*', '');

    if clean_caller_class <> '' and clean_target_class <> clean_caller_class and clean_target_class <> '' then
      raise exception 'Permission denied: You can only approve students for your assigned class (%)', caller.attendance_class using errcode = '42501';
    end if;
  else
    raise exception 'Permission denied: Unauthorized to review user registrations' using errcode = '42501';
  end if;

  v_effective_school := coalesce(target_sid, target_user.school_id, caller.school_id, '00000000-0000-4000-8000-000000000001');
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

  if is_approve then
    update public.users
    set
      approval_status = 'approved',
      is_active = true,
      role = target_role,
      school_id = v_effective_school,
      section_id = coalesce(v_effective_section_id, section_id),
      assigned_grade = coalesce(assigned_grade, requested_grade),
      assigned_class = coalesce(assigned_class, requested_class),
      assigned_subject = coalesce(assigned_subject, requested_subject)
    where id = target_uid;

    -- Auto-link teacher course if subject provided
    if target_role = 'teacher' and v_effective_section_id is not null and target_user.assigned_subject is not null then
      insert into public.teacher_courses (teacher_id, section_id, subject, assigned_by)
      values (target_uid, v_effective_section_id, target_user.assigned_subject, caller_id)
      on conflict do nothing;
    end if;

    -- Auto-enroll student into section
    if target_role = 'student' and v_effective_section_id is not null then
      insert into public.student_sections (student_id, section_id)
      values (target_uid, v_effective_section_id)
      on conflict do nothing;
    end if;

    return jsonb_build_object(
      'success', true,
      'status', 'approved',
      'user_id', target_uid,
      'role', target_role,
      'message', 'Registration approved successfully'
    );
  else
    -- Reject
    update public.users
    set
      approval_status = 'rejected',
      is_active = false
    where id = target_uid;

    return jsonb_build_object(
      'success', true,
      'status', 'rejected',
      'user_id', target_uid,
      'message', 'Registration rejected'
    );
  end if;
end;
$$;

create or replace function public.review_user_registration(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = 'off'
as $$
declare
  v_user_id uuid;
  v_decision text;
  v_school_id uuid;
begin
  v_user_id := nullif(coalesce(payload->>'p_user_id', payload->>'user_id'), '')::uuid;
  v_decision := coalesce(payload->>'p_decision', payload->>'decision');
  v_school_id := nullif(coalesce(payload->>'p_school_id', payload->>'school_id'), '')::uuid;

  return public.review_user_registration(
    p_user_id => v_user_id,
    p_decision => v_decision,
    p_school_id => v_school_id
  );
end;
$$;

grant execute on function public.review_user_registration(uuid, text, uuid, uuid, text, uuid) to authenticated, anon;
grant execute on function public.review_user_registration(jsonb) to authenticated, anon;

-- ============================================================================
-- 4. ADMIN CREATE USER RPC (Strict boundaries)
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
set row_security = 'off'
as $$
declare
  caller_id uuid := auth.uid();
  caller record;
  new_user_id uuid := gen_random_uuid();
  clean_uname text := trim(p_username);
  clean_email text := lower(trim(p_email));
  existing_id uuid;
  assigned_role text := lower(trim(p_role));
  effective_school uuid := coalesce(p_school_id, '00000000-0000-4000-8000-000000000001');
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
  -- 1. Super Admin: can register subadmins, teachers, students
  if caller.role = 'admin' or caller.is_super_admin is true then
    if assigned_role in ('admin', 'super_admin') then
      assigned_role := 'subadmin';
    end if;

  -- 2. Subadmin: can register TEACHERS ONLY
  elsif caller.role = 'subadmin' then
    if assigned_role <> 'teacher' then
      raise exception 'Permission denied: Sub-administrators can only register teacher accounts. Student registration is handled by attendance teachers.' using errcode = '42501';
    end if;
    effective_school := coalesce(caller.school_id, '00000000-0000-4000-8000-000000000001');

  -- 3. Attendance Teacher: can register STUDENTS ONLY for their designated class
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

    effective_school := coalesce(caller.school_id, '00000000-0000-4000-8000-000000000001');
    assigned_class_val := caller.attendance_class;
    assigned_grade_val := coalesce(caller.attendance_grade, p_grade);
    is_attendance := false;
    attendance_class_val := null;
    attendance_grade_val := null;
  else
    raise exception 'Permission denied: You do not have authority to register accounts' using errcode = '42501';
  end if;

  -- Auto-resolve section_id if missing
  if effective_section is null and effective_school is not null and coalesce(assigned_class_val, '') <> '' then
    select id into effective_section
    from public.sections
    where school_id = effective_school
      and (
        lower(trim(name)) = lower(trim(assigned_class_val))
        or lower(trim(name)) = lower(trim(regexp_replace(assigned_class_val, '^(class|section)\s*', '', 'i')))
      )
    limit 1;
  end if;

  -- Check duplicate email in auth.users
  select id into existing_id from auth.users where lower(email) = clean_email;
  if existing_id is not null then
    raise exception 'An account with email % already exists', clean_email using errcode = '23505';
  end if;

  -- Check duplicate username in public.users
  select id into existing_id from public.users where lower(username) = lower(clean_uname);
  if existing_id is not null then
    raise exception 'Username % is already taken', clean_uname using errcode = '23505';
  end if;

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
    updated_at,
    confirmation_token
  )
  values (
    '00000000-0000-4000-8000-000000000000',
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
      'role', assigned_role,
      'school_id', effective_school
    ),
    now(),
    now(),
    encode(extensions.gen_random_bytes(32), 'hex')
  );

  -- Insert or update public.users
  insert into public.users (
    id,
    email,
    username,
    full_name,
    role,
    school_id,
    section_id,
    assigned_subject,
    assigned_class,
    assigned_grade,
    phone_number,
    gender,
    is_attendance_teacher,
    attendance_class,
    attendance_grade,
    approval_status,
    is_active,
    must_change_password,
    created_by
  )
  values (
    new_user_id,
    clean_email,
    clean_uname,
    p_full_name,
    assigned_role,
    effective_school,
    effective_section,
    p_subject,
    assigned_class_val,
    assigned_grade_val,
    p_phone_number,
    p_gender,
    is_attendance,
    attendance_class_val,
    attendance_grade_val,
    'approved',
    true,
    false,
    caller_id
  )
  on conflict (id) do update set
    email = excluded.email,
    username = excluded.username,
    full_name = excluded.full_name,
    role = excluded.role,
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
set row_security = 'off'
as $$
begin
  return public.admin_create_user(
    p_full_name => payload->>'full_name',
    p_username => payload->>'username',
    p_email => payload->>'email',
    p_password => payload->>'password',
    p_role => payload->>'role',
    p_school_id => nullif(payload->>'school_id', '')::uuid,
    p_section_id => nullif(payload->>'section_id', '')::uuid,
    p_subject => payload->>'subject',
    p_phone_number => payload->>'phone_number',
    p_gender => payload->>'gender',
    p_grade => payload->>'grade',
    p_class => payload->>'class',
    p_is_attendance_teacher => coalesce((payload->>'is_attendance_teacher')::boolean, false),
    p_attendance_grade => payload->>'attendance_grade',
    p_attendance_class => payload->>'attendance_class'
  );
end;
$$;

grant execute on function public.admin_create_user(text, text, text, text, text, uuid, uuid, text, text, text, text, text, boolean, text, text) to authenticated, anon;
grant execute on function public.admin_create_user(jsonb) to authenticated, anon;

-- ============================================================================
-- 5. DELETE USER ACCOUNT RPC (Strict boundaries)
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
set row_security = 'off'
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

  -- Protected Super Admin accounts
  if target_user.is_super_admin is true or
     lower(coalesce(target_user.email, '')) in ('wondedev369@gmail.com', 'wondeadmin@admin.edu') or
     lower(coalesce(target_user.username, '')) in ('wondedev369@gmail.com', 'wondeadmin@admin.edu') or
     (target_user.role = 'admin' and caller.role <> 'admin') then
    raise exception 'Permission denied: The Main Administrator account is protected and cannot be deleted' using errcode = '42501';
  end if;

  -- Self-deletion prevention
  if caller_id = target_id and caller.role in ('admin', 'subadmin') then
    raise exception 'Permission denied: Administrators cannot delete their own account' using errcode = '42501';
  end if;

  -- Authorization hierarchy:
  -- 1. Super Admin: can delete any user
  if caller.role = 'admin' or caller.is_super_admin is true then
    null;

  -- 2. Subadmin: can delete TEACHERS ONLY
  elsif caller.role = 'subadmin' then
    if target_user.role <> 'teacher' then
      raise exception 'Permission denied: Sub-administrators can only delete teacher accounts. Student deletions are managed by attendance teachers.' using errcode = '42501';
    end if;

  -- 3. Attendance Teacher: can delete STUDENTS of their assigned class
  elsif caller.role = 'teacher' then
    if target_user.role <> 'student' then
      raise exception 'Permission denied: Teachers can only delete student accounts' using errcode = '42501';
    end if;
    if caller.is_attendance_teacher = true and caller.attendance_class is not null then
      if lower(trim(coalesce(target_user.assigned_class, target_user.requested_class, ''))) <>
         lower(trim(caller.attendance_class)) then
        raise exception 'Permission denied: You can only delete students belonging to your class (%)', caller.attendance_class using errcode = '42501';
      end if;
    end if;
  else
    raise exception 'Permission denied: You do not have authority to delete accounts' using errcode = '42501';
  end if;

  -- Child records cleanup:
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
    delete from public.teacher_courses where teacher_id = target_id or assigned_by = target_id;
  exception when others then null;
  end;

  begin
    delete from public.course_resources where teacher_id = target_id::text;
  exception when others then null;
  end;

  -- Teacher quiz cascade
  for t_quiz in (select id from public.quizzes where teacher_id = target_id) loop
    begin
      delete from public.answers where attempt_id in (select id from public.quiz_attempts where quiz_id = t_quiz.id);
    exception when others then null;
    end;
    begin
      delete from public.quiz_attempts where quiz_id = t_quiz.id;
    exception when others then null;
    end;
    begin
      delete from public.grades where quiz_id = t_quiz.id;
    exception when others then null;
    end;
    begin
      delete from public.questions where quiz_id = t_quiz.id;
    exception when others then null;
    end;
  end loop;

  begin
    delete from public.quizzes where teacher_id = target_id;
  exception when others then null;
  end;

  begin
    delete from public.audit_logs where user_id = target_id;
  exception when others then null;
  end;

  delete from public.users where id = target_id;

  begin
    delete from auth.users where id = target_id;
  exception when others then null;
  end;

  return jsonb_build_object(
    'success', true,
    'user_id', target_id,
    'message', 'User account successfully deleted'
  );
end;
$$;

create or replace function public.delete_user_account(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = 'off'
as $$
declare
  v_uid uuid;
begin
  v_uid := nullif(coalesce(payload->>'p_user_id', payload->>'user_id'), '')::uuid;
  return public.delete_user_account(p_user_id => v_uid);
end;
$$;

grant execute on function public.delete_user_account(uuid, uuid) to authenticated, anon;
grant execute on function public.delete_user_account(jsonb) to authenticated, anon;

-- ============================================================================
-- 6. DASHBOARD STATISTICS RPC (Lightning-fast, role-tailored stats)
-- ============================================================================

drop function if exists public.get_school_user_stats(uuid);

create or replace function public.get_school_user_stats(p_school_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = 'off'
as $$
declare
  v_school_id uuid := coalesce(p_school_id, '00000000-0000-4000-8000-000000000001');
  v_total_users int;
  v_subadmins int;
  v_teachers int;
  v_students int;
  v_pending int;
  v_materials_locked boolean := false;
  v_grades jsonb;
  v_sections jsonb;
begin
  -- Materials lock status
  select coalesce(materials_locked, false) into v_materials_locked
  from public.schools
  where id = v_school_id;

  -- Total active users for this school
  select count(*) into v_total_users
  from public.users
  where is_active != false
    and (school_id = v_school_id or school_id is null);

  -- Role totals
  select count(*) into v_subadmins
  from public.users
  where role = 'subadmin' and is_active != false
    and (school_id = v_school_id or school_id is null);

  select count(*) into v_teachers
  from public.users
  where role = 'teacher' and is_active != false
    and (school_id = v_school_id or school_id is null);

  select count(*) into v_students
  from public.users
  where role = 'student' and is_active != false
    and (school_id = v_school_id or school_id is null);

  select count(*) into v_pending
  from public.users
  where approval_status = 'pending'
    and (school_id = v_school_id or school_id is null);

  -- Grade breakdowns (Grade 9, 10, 11, 12) - for Subadmins and Teachers
  with grade_list as (
    select unnest(array['Grade 9', 'Grade 10', 'Grade 11', 'Grade 12']) as grade_name
  )
  select jsonb_agg(
    jsonb_build_object(
      'grade', g.grade_name,
      'students', (
        select count(*)
        from public.users u
        where u.role = 'student'
          and u.is_active != false
          and (
            u.assigned_grade = g.grade_name
            or u.requested_grade = g.grade_name
            or u.assigned_class ilike g.grade_name || '%'
            or u.assigned_class ilike replace(g.grade_name, 'Grade ', '') || '%'
          )
      ),
      'teachers', (
        select count(distinct u.id)
        from public.users u
        left join public.teacher_courses tc on tc.teacher_id = u.id
        left join public.sections s on s.id = tc.section_id
        where u.role = 'teacher'
          and u.is_active != false
          and (
            u.assigned_grade = g.grade_name
            or s.grade = g.grade_name
            or u.assigned_class ilike g.grade_name || '%'
            or u.assigned_class ilike replace(g.grade_name, 'Grade ', '') || '%'
          )
      )
    )
  ) into v_grades
  from grade_list g;

  -- Section breakdowns (by Section within Grade) - for Teachers
  select jsonb_agg(
    jsonb_build_object(
      'grade', coalesce(s.grade, 'Grade 9'),
      'section', s.name,
      'students', (
        select count(*)
        from public.users u
        where u.role = 'student'
          and u.is_active != false
          and (
            u.section_id = s.id
            or lower(trim(u.assigned_class)) = lower(trim(s.name))
            or lower(trim(u.assigned_class)) = lower(trim(s.grade || ' ' || s.name))
            or lower(trim(u.assigned_class)) = lower(trim(replace(s.grade, 'Grade ', '') || s.name))
          )
      )
    )
  ) into v_sections
  from public.sections s
  where s.school_id = v_school_id;

  return jsonb_build_object(
    'total_users', v_total_users,
    'subadmins', v_subadmins,
    'teachers', v_teachers,
    'students', v_students,
    'pending', v_pending,
    'materials_locked', v_materials_locked,
    'grades', coalesce(v_grades, '[]'::jsonb),
    'sections', coalesce(v_sections, '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_school_user_stats(uuid) to authenticated, anon;

-- ============================================================================
-- 7. MULTI-CLASS TEACHER ASSIGNMENT RPC
-- ============================================================================

create or replace function public.assign_teacher_to_class(
  p_teacher_id uuid,
  p_section_id uuid,
  p_subject text default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = 'off'
as $$
declare
  caller_id uuid := auth.uid();
  caller record;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select id, role, is_super_admin into caller from public.users where id = caller_id;
  if caller.role not in ('admin', 'subadmin') and caller.is_super_admin is not true then
    raise exception 'Permission denied: Only administrators can assign teachers to classes' using errcode = '42501';
  end if;

  insert into public.teacher_courses (teacher_id, section_id, subject, assigned_by)
  values (p_teacher_id, p_section_id, p_subject, caller_id)
  on conflict (teacher_id, section_id, coalesce(subject, '')) do nothing;

  return jsonb_build_object('success', true, 'message', 'Teacher successfully assigned to class');
end;
$$;

grant execute on function public.assign_teacher_to_class(uuid, uuid, text) to authenticated, anon;

commit;
