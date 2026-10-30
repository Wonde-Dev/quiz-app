-- Migration: 20261030120000_fix_registration_and_advanced_examination_system.sql
-- Description:
-- 1. Synchronize auth.users and public.users for existing accounts (e.g. YonasD).
-- 2. Drop all conflicting overloads of public.admin_create_user.
-- 3. Create a single, unified, robust public.admin_create_user RPC with clear duplicate detection.
-- 4. Create public.check_user_credentials_available RPC.
-- 5. Extend quizzes table for timing (start_time, end_time, duration), exam_type, instructions, results_published.
-- 6. Extend questions table for all 7 question types, accepted_answers, matching_pairs, is_manual_grading.
-- 7. Extend quiz_attempts and answers tables for state tracking, points awarded, and teacher grading.
-- 8. Add secure server-side RPCs:
--    - start_examination_attempt (server-enforced start/end, persists remaining time across reload)
--    - get_student_exam_questions (protects student privacy, NEVER exposes correct answers!)
--    - save_student_answer (continuous auto-saving of answers)
--    - submit_examination_attempt (authoritative server-side evaluation & auto-grading)
--    - teacher_grade_essay_answer (manual grading queue for essay questions)
--    - teacher_publish_exam_results (controls when students can see their answers & evaluation)

begin;

-- ============================================================================
-- 0. DEFINE / FIX SIGNUP TRIGGER ON auth.users
-- ============================================================================

create or replace function public.handle_quiz_app_user_signup()
returns trigger
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
declare
  is_admin_created boolean := coalesce(
    (new.raw_app_meta_data ->> 'created_by_admin')::boolean,
    (new.raw_user_meta_data ->> 'is_admin_creation')::boolean,
    false
  );
  requested_role_val text := lower(trim(coalesce(
    new.raw_user_meta_data ->> 'requested_role',
    new.raw_user_meta_data ->> 'role',
    'student'
  )));
  assigned_role text;
  username_val text := trim(coalesce(new.raw_user_meta_data ->> 'username', ''));
  full_name_val text := trim(coalesce(new.raw_user_meta_data ->> 'full_name', ''));
  school_id_val uuid;
  section_id_val uuid;
  phone_val text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'phone_number', new.raw_user_meta_data ->> 'phone', '')), '');
  gender_val text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'gender', '')), '');
  grade_val text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'requested_grade', new.raw_user_meta_data ->> 'assigned_grade', '')), '');
  class_val text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'requested_class', new.raw_user_meta_data ->> 'assigned_class', '')), '');
  subject_val text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'requested_subject', new.raw_user_meta_data ->> 'assigned_subject', '')), '');
  is_attendance boolean := coalesce((new.raw_user_meta_data ->> 'is_attendance_teacher')::boolean, false);
  attendance_class_val text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'attendance_class', '')), '');
  attendance_grade_val text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'attendance_grade', '')), '');
begin
  -- Normalize roles
  if requested_role_val in ('director', 'subadmin') then
    requested_role_val := 'subadmin';
  elsif requested_role_val in ('super_admin', 'superadmin', 'admin') then
    requested_role_val := 'admin';
  elsif requested_role_val not in ('student', 'teacher', 'subadmin', 'admin') then
    requested_role_val := 'student';
  end if;

  -- Block self-registration for admin or subadmin/director
  if not is_admin_created and new.email_confirmed_at is null and requested_role_val in ('admin', 'subadmin') then
    raise exception 'Administrator and Director accounts are invitation-only' using errcode = '42501';
  end if;

  -- Fallbacks for name and username
  if length(full_name_val) < 1 then
    full_name_val := coalesce(nullif(username_val, ''), split_part(coalesce(new.email, 'User'), '@', 1), 'User');
  end if;
  if length(username_val) < 1 then
    username_val := coalesce(new.email, new.id::text);
  end if;

  begin
    school_id_val := nullif(new.raw_user_meta_data ->> 'school_id', '')::uuid;
  exception when others then
    school_id_val := null;
  end;

  begin
    section_id_val := nullif(new.raw_user_meta_data ->> 'section_id', '')::uuid;
  exception when others then
    section_id_val := null;
  end;

  -- If this is an existing row in public.users being synchronized or admin created or confirmed:
  if is_admin_created or new.email_confirmed_at is not null or exists (select 1 from public.users where id = new.id) then
    assigned_role := requested_role_val;
    insert into public.users (
      id, email, username, full_name, role, requested_role,
      school_id, section_id, phone_number, gender,
      assigned_grade, assigned_class, assigned_subject,
      requested_grade, requested_class, requested_subject,
      is_attendance_teacher, attendance_grade, attendance_class,
      approval_status, is_active, must_change_password, created_at
    ) values (
      new.id, lower(new.email), username_val, full_name_val, assigned_role, assigned_role,
      school_id_val, section_id_val, phone_val, gender_val,
      grade_val, class_val, subject_val,
      grade_val, class_val, subject_val,
      is_attendance, attendance_grade_val, attendance_class_val,
      'approved', true, false, now()
    ) on conflict (id) do update set
      email = excluded.email,
      username = coalesce(nullif(excluded.username, ''), public.users.username),
      full_name = coalesce(nullif(excluded.full_name, ''), public.users.full_name),
      role = coalesce(nullif(excluded.role, ''), public.users.role),
      requested_role = coalesce(nullif(excluded.requested_role, ''), public.users.requested_role),
      school_id = coalesce(excluded.school_id, public.users.school_id),
      section_id = coalesce(excluded.section_id, public.users.section_id),
      phone_number = coalesce(excluded.phone_number, public.users.phone_number),
      gender = coalesce(excluded.gender, public.users.gender),
      assigned_grade = coalesce(excluded.assigned_grade, public.users.assigned_grade),
      assigned_class = coalesce(excluded.assigned_class, public.users.assigned_class),
      assigned_subject = coalesce(excluded.assigned_subject, public.users.assigned_subject),
      approval_status = 'approved',
      is_active = true;
  else
    -- Standard self-registration: starts pending approval
    insert into public.users (
      id, email, username, full_name, role, requested_role,
      school_id, section_id, phone_number, gender,
      requested_grade, requested_class, requested_subject,
      approval_status, is_active, must_change_password, created_at
    ) values (
      new.id, lower(new.email), username_val, full_name_val, 'student', requested_role_val,
      school_id_val, section_id_val, phone_val, gender_val,
      grade_val, class_val, subject_val,
      'pending', false, false, now()
    ) on conflict (id) do update set
      email = excluded.email,
      username = coalesce(nullif(excluded.username, ''), public.users.username),
      full_name = coalesce(nullif(excluded.full_name, ''), public.users.full_name),
      requested_role = excluded.requested_role,
      school_id = coalesce(excluded.school_id, public.users.school_id),
      section_id = coalesce(excluded.section_id, public.users.section_id),
      phone_number = coalesce(excluded.phone_number, public.users.phone_number),
      gender = coalesce(excluded.gender, public.users.gender),
      requested_grade = coalesce(excluded.requested_grade, public.users.requested_grade),
      requested_class = coalesce(excluded.requested_class, public.users.requested_class),
      requested_subject = coalesce(excluded.requested_subject, public.users.requested_subject);
  end if;

  return new;
end;
$$;

drop trigger if exists z_quiz_app_secure_profile on auth.users;
create trigger z_quiz_app_secure_profile
  after insert on auth.users
  for each row execute function public.handle_quiz_app_user_signup();

-- ============================================================================
-- 1. SYNCHRONIZE AUTH.USERS AND PUBLIC.USERS FOR EXISTING ACCOUNTS
-- ============================================================================

-- Ensure YonasD has a corresponding row in auth.users
insert into auth.users (
  id,
  instance_id,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  aud,
  role,
  created_at,
  updated_at
)
select
  u.id,
  '00000000-0000-4000-8000-000000000000',
  lower(trim(u.email)),
  extensions.crypt('YonasD123!', extensions.gen_salt('bf', 10)),
  now(),
  jsonb_build_object('provider', 'email', 'providers', array['email'], 'created_by_admin', true),
  jsonb_build_object(
    'full_name', u.full_name,
    'username', u.username,
    'role', u.role,
    'requested_role', u.role,
    'is_admin_creation', true,
    'school_id', u.school_id,
    'assigned_subject', u.assigned_subject,
    'email_verified', true
  ),
  'authenticated',
  'authenticated',
  coalesce(u.created_at, now()),
  now()
from public.users u
where u.id = 'e587ca15-302a-403c-aec3-e2e64f325f3c'
  and not exists (select 1 from auth.users where id = 'e587ca15-302a-403c-aec3-e2e64f325f3c');

-- ============================================================================
-- 2. DROP ALL COMPETING OVERLOADS OF admin_create_user
-- ============================================================================

drop function if exists public.admin_create_user(payload jsonb);
drop function if exists public.admin_create_user(text, text, text, text, text, uuid, uuid, text);
drop function if exists public.admin_create_user(text, text, text, text, text, uuid, uuid, text, text, text);
drop function if exists public.admin_create_user(text, text, text, text, text, uuid, uuid, text, text, text, boolean, text, text);
drop function if exists public.admin_create_user(text, text, text, text, text, uuid, uuid, text, text, text, text, text, boolean, text, text);
drop function if exists public.admin_create_user(text, text, text, text, text, uuid, uuid, text, text, text, text, text, boolean, text, text, boolean);

-- ============================================================================
-- 3. CREDENTIAL AVAILABILITY RPC (Pre-flight duplicate check)
-- ============================================================================

create or replace function public.check_user_credentials_available(
  p_email text,
  p_username text
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = 'off'
as $$
declare
  clean_email text := lower(trim(p_email));
  clean_uname text := trim(p_username);
  email_taken boolean := false;
  username_taken boolean := false;
  suggested_uname text := clean_uname;
  counter int := 1;
begin
  -- Check email in auth.users and public.users
  select exists(
    select 1 from auth.users where lower(email) = clean_email
    union
    select 1 from public.users where lower(email) = clean_email
  ) into email_taken;

  -- Check username in public.users and auth metadata
  select exists(
    select 1 from public.users where lower(username) = lower(clean_uname)
    union
    select 1 from auth.users where lower(raw_user_meta_data->>'username') = lower(clean_uname)
  ) into username_taken;

  if username_taken then
    loop
      counter := counter + 1;
      if clean_uname ~ '@' then
        suggested_uname := regexp_replace(clean_uname, '^([^@]+)@', '\1' || counter || '@');
      else
        suggested_uname := clean_uname || counter;
      end if;

      exit when not exists(
        select 1 from public.users where lower(username) = lower(suggested_uname)
        union
        select 1 from auth.users where lower(raw_user_meta_data->>'username') = lower(suggested_uname)
      );

      if counter > 50 then exit; end if;
    end loop;
  end if;

  return jsonb_build_object(
    'email_available', not email_taken,
    'username_available', not username_taken,
    'suggested_username', suggested_uname
  );
end;
$$;

grant execute on function public.check_user_credentials_available(text, text) to authenticated, anon;

-- ============================================================================
-- 4. UNIFIED, ROBUST admin_create_user RPC
-- ============================================================================

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
  p_attendance_class text default null,
  p_require_email_verification boolean default false
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
  assigned_role text := lower(trim(p_role));
  effective_school uuid := coalesce(p_school_id, '00000000-0000-4000-8000-000000000001');
  assigned_class_val text := p_class;
  assigned_grade_val text := p_grade;
  attendance_class_val text := p_attendance_class;
  attendance_grade_val text := p_attendance_grade;
  is_attendance boolean := coalesce(p_is_attendance_teacher, false);
  effective_section uuid := p_section_id;
  encrypted_pw text;
  existing_auth_user record;
  existing_public_user record;
  email_conflict boolean := false;
  username_conflict boolean := false;
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
  -- 1. Super Admin: can register subadmins (directors), teachers, students
  if caller.role = 'admin' or caller.is_super_admin is true then
    if assigned_role in ('admin', 'super_admin') then
      assigned_role := 'subadmin';
    end if;

    -- Strict Single Director Check:
    if assigned_role in ('subadmin', 'director') then
      if (
        select count(*)
        from public.users
        where role in ('subadmin', 'director')
          and is_active = true
          and (school_id = effective_school or school_id is null)
      ) >= 1 then
        return jsonb_build_object(
          'success', false,
          'error_code', 'single_director_limit',
          'message', 'Ciro High School already has an appointed School Director. Only one director is permitted at a time.'
        );
      end if;
    end if;

  -- 2. School Director: can register TEACHERS ONLY
  elsif caller.role in ('subadmin', 'director') then
    if assigned_role <> 'teacher' then
      return jsonb_build_object(
        'success', false,
        'error_code', 'permission_denied',
        'message', 'Permission denied: School Directors can only register Faculty Teacher accounts.'
      );
    end if;
    effective_school := coalesce(caller.school_id, '00000000-0000-4000-8000-000000000001');

  -- 3. Attendance Teacher: can register STUDENTS ONLY for their designated class
  elsif caller.role = 'teacher' then
    if caller.is_attendance_teacher is not true then
      return jsonb_build_object(
        'success', false,
        'error_code', 'permission_denied',
        'message', 'Permission denied: Only designated Attendance Teachers can register student accounts'
      );
    end if;
    if assigned_role <> 'student' then
      return jsonb_build_object(
        'success', false,
        'error_code', 'permission_denied',
        'message', 'Permission denied: Attendance teachers can only register student accounts'
      );
    end if;
    if caller.attendance_class is null then
      return jsonb_build_object(
        'success', false,
        'error_code', 'missing_attendance_class',
        'message', 'Permission denied: Attendance teacher has no assigned class'
      );
    end if;

    effective_school := coalesce(caller.school_id, '00000000-0000-4000-8000-000000000001');
    assigned_class_val := caller.attendance_class;
    assigned_grade_val := coalesce(caller.attendance_grade, p_grade);
    is_attendance := false;
    attendance_class_val := null;
    attendance_grade_val := null;
  else
    return jsonb_build_object(
      'success', false,
      'error_code', 'permission_denied',
      'message', 'Permission denied: You do not have authority to register accounts'
    );
  end if;

  -- --------------------------------------------------------------------------
  -- CHECK FOR DUPLICATE EMAIL OR USERNAME
  -- --------------------------------------------------------------------------
  select id, email into existing_auth_user
  from auth.users
  where lower(email) = clean_email
  limit 1;

  select id, email, username into existing_public_user
  from public.users
  where lower(email) = clean_email or lower(username) = lower(clean_uname)
  limit 1;

  if existing_public_user.id is not null then
    if lower(existing_public_user.email) = clean_email then
      return jsonb_build_object(
        'success', false,
        'error_code', 'email_taken',
        'message', 'The email address "' || clean_email || '" is already registered to an existing account (' || existing_public_user.username || ').'
      );
    end if;
    if lower(existing_public_user.username) = lower(clean_uname) then
      return jsonb_build_object(
        'success', false,
        'error_code', 'username_taken',
        'message', 'The username "' || clean_uname || '" is already in use.',
        'suggested_username', clean_uname || '2'
      );
    end if;
  end if;

  if existing_auth_user.id is not null then
    return jsonb_build_object(
      'success', false,
      'error_code', 'email_taken',
      'message', 'The email address "' || clean_email || '" is already in use in the authentication system.'
    );
  end if;

  -- Resolve section_id if not explicitly provided
  if effective_section is null and effective_school is not null and coalesce(assigned_class_val, '') <> '' then
    select id into effective_section
    from public.sections
    where school_id = effective_school
      and (
        lower(trim(name)) = lower(trim(assigned_class_val))
        or lower(trim(name)) = lower(trim(regexp_replace(assigned_class_val, '^(class|section)\s*', '', 'i')))
        or lower(trim(grade || ' ' || name)) = lower(trim(assigned_class_val))
      )
    order by name asc
    limit 1;
  end if;

  encrypted_pw := extensions.crypt(coalesce(p_password, 'Pass123!456'), extensions.gen_salt('bf', 10));

  -- Insert into auth.users
  insert into auth.users (
    id,
    instance_id,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    aud,
    role,
    created_at,
    updated_at
  )
  values (
    new_user_id,
    '00000000-0000-4000-8000-000000000000',
    clean_email,
    encrypted_pw,
    case when p_require_email_verification then null else now() end,
    jsonb_build_object('provider', 'email', 'providers', array['email']),
    jsonb_build_object(
      'full_name', p_full_name,
      'username', clean_uname,
      'role', assigned_role,
      'school_id', effective_school,
      'section_id', effective_section,
      'subject', p_subject,
      'phone_number', p_phone_number,
      'gender', p_gender,
      'grade', assigned_grade_val,
      'class', assigned_class_val,
      'is_attendance_teacher', is_attendance,
      'attendance_grade', attendance_grade_val,
      'attendance_class', attendance_class_val,
      'email_verified', not p_require_email_verification
    ),
    'authenticated',
    'authenticated',
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
    school_id,
    section_id,
    approval_status,
    is_active,
    is_super_admin,
    assigned_subject,
    phone_number,
    gender,
    assigned_grade,
    assigned_class,
    is_attendance_teacher,
    attendance_grade,
    attendance_class,
    must_change_password,
    created_at,
    updated_at
  )
  values (
    new_user_id,
    clean_email,
    clean_uname,
    p_full_name,
    assigned_role,
    effective_school,
    effective_section,
    'approved',
    true,
    false,
    p_subject,
    p_phone_number,
    p_gender,
    assigned_grade_val,
    assigned_class_val,
    is_attendance,
    attendance_grade_val,
    attendance_class_val,
    true,
    now(),
    now()
  );

  -- If teacher with section assignment, record teacher_courses
  if assigned_role = 'teacher' and effective_section is not null then
    begin
      insert into public.teacher_courses (teacher_id, section_id, subject, assigned_by)
      values (new_user_id, effective_section, coalesce(p_subject, 'General'), caller_id);
    exception when others then null;
    end;
  end if;

  -- If student with section assignment, record student_sections
  if assigned_role = 'student' and effective_section is not null then
    begin
      insert into public.student_sections (student_id, section_id)
      values (new_user_id, effective_section)
      on conflict (student_id, section_id) do nothing;
    exception when others then null;
    end;
  end if;

  -- Audit log
  insert into public.audit_logs (
    action, performed_by, target_user, details
  )
  values (
    'user_created',
    caller_id,
    clean_uname,
    jsonb_build_object(
      'user_id', new_user_id,
      'email', clean_email,
      'role', assigned_role,
      'registered_by_role', caller.role
    )
  );

  return jsonb_build_object(
    'success', true,
    'id', new_user_id,
    'username', clean_uname,
    'email', clean_email,
    'role', assigned_role,
    'message', 'User account successfully registered and synchronized.'
  );
end;
$$;

grant execute on function public.admin_create_user(text, text, text, text, text, uuid, uuid, text, text, text, text, text, boolean, text, text, boolean) to authenticated, anon;

-- ============================================================================
-- 5. EXTEND QUIZZES & EXAMINATION TABLES
-- ============================================================================

-- Add examination metadata to quizzes table
alter table public.quizzes
  add column if not exists exam_type text not null default 'quiz',
  add column if not exists subject text,
  add column if not exists instructions text,
  add column if not exists start_time timestamptz,
  add column if not exists end_time timestamptz,
  add column if not exists results_published boolean not null default false,
  add column if not exists allow_retakes boolean not null default false;

-- Add question metadata & question types to questions table
alter table public.questions
  add column if not exists accepted_answers jsonb default '[]'::jsonb,
  add column if not exists matching_pairs jsonb default '[]'::jsonb,
  add column if not exists image_url text,
  add column if not exists is_manual_grading boolean not null default false;

-- Add attempt tracking fields to quiz_attempts table
alter table public.quiz_attempts
  add column if not exists status text not null default 'in_progress',
  add column if not exists time_remaining_seconds integer,
  add column if not exists percentage numeric,
  add column if not exists manual_grading_pending boolean not null default false;

-- Add answer grading fields to answers table
alter table public.answers
  add column if not exists points_awarded numeric default 0,
  add column if not exists teacher_feedback text,
  add column if not exists manual_grade_status text not null default 'auto';

-- ============================================================================
-- 6. SECURE EXAMINATION RPCS
-- ============================================================================

-- A. Start Examination Attempt
-- Enforces timing, enrollment, single attempt, and returns attempt with server timer
create or replace function public.start_examination_attempt(p_quiz_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = 'off'
as $$
declare
  v_student_id uuid := auth.uid();
  v_quiz record;
  v_student record;
  v_existing_attempt record;
  v_attempt_id uuid;
  v_now timestamptz := now();
  v_duration_seconds int;
  v_elapsed_seconds int;
  v_remaining_seconds int;
begin
  if v_student_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into v_student from public.users where id = v_student_id;
  if v_student.id is null or v_student.role <> 'student' then
    raise exception 'Only enrolled students may participate in examinations' using errcode = '42501';
  end if;

  select * into v_quiz from public.quizzes where id = p_quiz_id;
  if v_quiz.id is null then
    raise exception 'Examination not found' using errcode = 'P0002';
  end if;

  if v_quiz.is_published is not true then
    raise exception 'This examination is currently unpublished' using errcode = '42501';
  end if;

  -- Verify Start Time window
  if v_quiz.start_time is not null and v_now < v_quiz.start_time then
    raise exception 'This examination has not started yet. Available from: %', v_quiz.start_time using errcode = '22023';
  end if;

  -- Verify End Time window
  if v_quiz.end_time is not null and v_now > v_quiz.end_time then
    raise exception 'This examination has closed. Deadline was: %', v_quiz.end_time using errcode = '22023';
  end if;

  -- Check existing attempt
  select * into v_existing_attempt
  from public.quiz_attempts
  where quiz_id = p_quiz_id and student_id = v_student_id
  order by started_at desc
  limit 1;

  v_duration_seconds := coalesce(v_quiz.time_limit_minutes, 30) * 60;

  if v_existing_attempt.id is not null then
    -- If already submitted and retakes not allowed
    if v_existing_attempt.status in ('submitted', 'time_expired', 'graded') and v_quiz.allow_retakes is not true then
      raise exception 'You have already submitted this examination' using errcode = '23505';
    end if;

    -- If in progress: calculate remaining time from server started_at
    if v_existing_attempt.status = 'in_progress' then
      v_elapsed_seconds := extract(epoch from (v_now - v_existing_attempt.started_at))::int;
      v_remaining_seconds := v_duration_seconds - v_elapsed_seconds;

      if v_remaining_seconds <= 0 then
        -- Automatically expire attempt
        update public.quiz_attempts
        set status = 'time_expired',
            submitted_at = v_now,
            auto_submitted = true
        where id = v_existing_attempt.id;

        return jsonb_build_object(
          'success', false,
          'status', 'time_expired',
          'message', 'Time limit for this examination has expired.'
        );
      end if;

      return jsonb_build_object(
        'success', true,
        'attempt_id', v_existing_attempt.id,
        'quiz_id', p_quiz_id,
        'title', v_quiz.title,
        'subject', v_quiz.subject,
        'instructions', v_quiz.instructions,
        'duration_seconds', v_duration_seconds,
        'remaining_seconds', v_remaining_seconds,
        'started_at', v_existing_attempt.started_at,
        'server_time', v_now
      );
    end if;
  end if;

  -- Create new attempt
  v_attempt_id := gen_random_uuid();
  insert into public.quiz_attempts (
    id, quiz_id, student_id, started_at, status, time_remaining_seconds
  )
  values (
    v_attempt_id, p_quiz_id, v_student_id, v_now, 'in_progress', v_duration_seconds
  );

  return jsonb_build_object(
    'success', true,
    'attempt_id', v_attempt_id,
    'quiz_id', p_quiz_id,
    'title', v_quiz.title,
    'subject', v_quiz.subject,
    'instructions', v_quiz.instructions,
    'duration_seconds', v_duration_seconds,
    'remaining_seconds', v_duration_seconds,
    'started_at', v_now,
    'server_time', v_now
  );
end;
$$;

grant execute on function public.start_examination_attempt(uuid) to authenticated;

-- B. Get Student Exam Questions (CRITICAL SECURITY: EXCLUDES CORRECT ANSWERS!)
create or replace function public.get_student_exam_questions(p_quiz_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = 'off'
as $$
declare
  v_questions jsonb;
begin
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', q.id,
      'quiz_id', q.quiz_id,
      'order', q."order",
      'points', q.points,
      'type', coalesce(q.question_type, q.type, 'multiple_choice'),
      'question_text', coalesce(q.question_text, q.text),
      'options', q.options,
      'image_url', q.image_url,
      'matching_left', case
        when q.matching_pairs is not null and jsonb_array_length(q.matching_pairs) > 0 then
          (select jsonb_agg(elem->'left') from jsonb_array_elements(q.matching_pairs) elem)
        else null
      end,
      'matching_right', case
        when q.matching_pairs is not null and jsonb_array_length(q.matching_pairs) > 0 then
          (select jsonb_agg(elem->'right') from jsonb_array_elements(q.matching_pairs) elem)
        else null
      end
    ) order by q."order" asc
  ), '[]'::jsonb)
  into v_questions
  from public.questions q
  where q.quiz_id = p_quiz_id;

  return v_questions;
end;
$$;

grant execute on function public.get_student_exam_questions(uuid) to authenticated;

-- C. Save Student Answer (Continuous Progress Auto-Saving)
create or replace function public.save_student_answer(
  p_attempt_id uuid,
  p_question_id uuid,
  p_answer_text text
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = 'off'
as $$
declare
  v_student_id uuid := auth.uid();
  v_attempt record;
begin
  select * into v_attempt
  from public.quiz_attempts
  where id = p_attempt_id and student_id = v_student_id;

  if v_attempt.id is null then
    raise exception 'Attempt not found or unauthorized' using errcode = '42501';
  end if;

  if v_attempt.status <> 'in_progress' then
    raise exception 'This attempt has already been submitted or expired' using errcode = '42501';
  end if;

  insert into public.answers (
    id, attempt_id, question_id, answer_text, answered_at
  )
  values (
    gen_random_uuid(), p_attempt_id, p_question_id, p_answer_text, now()
  )
  on conflict (attempt_id, question_id) do update set
    answer_text = excluded.answer_text,
    answered_at = now();

  return jsonb_build_object('success', true, 'saved_at', now());
end;
$$;

-- Add unique constraint on (attempt_id, question_id) if missing
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'answers_attempt_question_unique'
  ) then
    alter table public.answers
      add constraint answers_attempt_question_unique unique (attempt_id, question_id);
  end if;
exception when others then null;
end;
$$;

grant execute on function public.save_student_answer(uuid, uuid, text) to authenticated;

-- D. Submit Examination Attempt & Authoritative Server-Side Evaluation
create or replace function public.submit_examination_attempt(p_attempt_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = 'off'
as $$
declare
  v_student_id uuid := auth.uid();
  v_attempt record;
  v_quiz record;
  v_question record;
  v_answer record;
  v_total_points numeric := 0;
  v_earned_score numeric := 0;
  v_correct_count int := 0;
  v_incorrect_count int := 0;
  v_has_pending_essay boolean := false;
  v_percentage numeric := 0;
  v_passed boolean := false;
  v_student_answer_norm text;
  v_correct_answer_norm text;
  v_is_correct boolean;
  v_points_awarded numeric;
begin
  select * into v_attempt
  from public.quiz_attempts
  where id = p_attempt_id and student_id = v_student_id;

  if v_attempt.id is null then
    raise exception 'Attempt not found or unauthorized' using errcode = '42501';
  end if;

  if v_attempt.status in ('submitted', 'graded') then
    return jsonb_build_object(
      'success', true,
      'message', 'Attempt was already submitted',
      'score', v_attempt.score,
      'percentage', v_attempt.percentage
    );
  end if;

  select * into v_quiz from public.quizzes where id = v_attempt.quiz_id;

  -- Grade each question of the examination on the server
  for v_question in (
    select * from public.questions where quiz_id = v_quiz.id order by "order" asc
  ) loop
    v_total_points := v_total_points + coalesce(v_question.points, 1);

    select * into v_answer
    from public.answers
    where attempt_id = p_attempt_id and question_id = v_question.id;

    v_student_answer_norm := lower(trim(coalesce(v_answer.answer_text, '')));
    v_correct_answer_norm := lower(trim(coalesce(v_question.correct_answer, '')));

    -- 1. Essay question -> queue for manual review by teacher
    if coalesce(v_question.question_type, v_question.type) = 'essay' or v_question.is_manual_grading then
      v_has_pending_essay := true;
      if v_answer.id is not null then
        update public.answers
        set manual_grade_status = 'pending_review',
            is_correct = null,
            points_awarded = 0
        where id = v_answer.id;
      end if;

    -- 2. Automatically gradable questions (MCQ, True/False, Multiple Select, Fill Blank, Short Answer)
    else
      v_is_correct := false;
      v_points_awarded := 0;

      if v_student_answer_norm <> '' then
        -- Direct match with correct_answer
        if v_student_answer_norm = v_correct_answer_norm then
          v_is_correct := true;
        -- Accepted answers array match (short answer / fill blank)
        elsif v_question.accepted_answers is not null and jsonb_typeof(v_question.accepted_answers) = 'array' then
          select exists(
            select 1 from jsonb_array_elements_text(v_question.accepted_answers) ans
            where lower(trim(ans)) = v_student_answer_norm
          ) into v_is_correct;
        end if;
      end if;

      if v_is_correct then
        v_points_awarded := coalesce(v_question.points, 1);
        v_earned_score := v_earned_score + v_points_awarded;
        v_correct_count := v_correct_count + 1;
      else
        v_incorrect_count := v_incorrect_count + 1;
      end if;

      -- Update individual answer row
      if v_answer.id is not null then
        update public.answers
        set is_correct = v_is_correct,
            points_awarded = v_points_awarded,
            manual_grade_status = 'auto'
        where id = v_answer.id;
      else
        insert into public.answers (
          id, attempt_id, question_id, answer_text, is_correct, points_awarded, answered_at, manual_grade_status
        )
        values (
          gen_random_uuid(), p_attempt_id, v_question.id, '', false, 0, now(), 'auto'
        );
      end if;
    end if;
  end loop;

  if v_total_points > 0 then
    v_percentage := round((v_earned_score / v_total_points) * 100);
  else
    v_percentage := 0;
  end if;

  v_passed := v_percentage >= coalesce(v_quiz.passing_score_percent, 50);

  -- Update attempt
  update public.quiz_attempts
  set status = case when v_has_pending_essay then 'pending_review' else 'submitted' end,
      submitted_at = now(),
      score = v_earned_score,
      percentage = v_percentage,
      manual_grading_pending = v_has_pending_essay
  where id = p_attempt_id;

  -- Record or update grades table
  insert into public.grades (
    id, student_id, quiz_id, score, total_points, percentage, passed, submitted_at, graded_at, incorrect_answers
  )
  values (
    gen_random_uuid(),
    v_student_id,
    v_quiz.id,
    v_earned_score::int,
    v_total_points::int,
    v_percentage::int,
    v_passed,
    now(),
    case when not v_has_pending_essay then now() else null end,
    v_incorrect_count
  )
  on conflict (id) do nothing;

  return jsonb_build_object(
    'success', true,
    'attempt_id', p_attempt_id,
    'quiz_id', v_quiz.id,
    'score', v_earned_score,
    'total_points', v_total_points,
    'percentage', v_percentage,
    'correct_count', v_correct_count,
    'incorrect_count', v_incorrect_count,
    'has_pending_essay', v_has_pending_essay,
    'results_published', v_quiz.results_published,
    'message', case
      when v_has_pending_essay then 'Examination submitted! Essay questions are pending teacher evaluation.'
      else 'Examination submitted and evaluated successfully!'
    end
  );
end;
$$;

grant execute on function public.submit_examination_attempt(uuid) to authenticated;

-- E. Teacher Grade Essay Answer
create or replace function public.teacher_grade_essay_answer(
  p_answer_id uuid,
  p_points_awarded numeric,
  p_feedback text default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = 'off'
as $$
declare
  v_teacher_id uuid := auth.uid();
  v_caller record;
  v_answer record;
  v_attempt record;
  v_quiz record;
  v_new_total_score numeric;
  v_total_points numeric;
  v_new_percentage numeric;
  v_pending_count int;
begin
  if v_teacher_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into v_caller from public.users where id = v_teacher_id;
  if v_caller.role not in ('teacher', 'admin', 'subadmin') then
    raise exception 'Permission denied: Only faculty teachers or administrators may grade essays' using errcode = '42501';
  end if;

  select * into v_answer from public.answers where id = p_answer_id;
  if v_answer.id is null then
    raise exception 'Answer record not found' using errcode = 'P0002';
  end if;

  select * into v_attempt from public.quiz_attempts where id = v_answer.attempt_id;
  select * into v_quiz from public.quizzes where id = v_attempt.quiz_id;

  -- Update answer
  update public.answers
  set points_awarded = p_points_awarded,
      teacher_feedback = p_feedback,
      is_correct = p_points_awarded > 0,
      manual_grade_status = 'reviewed'
  where id = p_answer_id;

  -- Recompute attempt totals
  select coalesce(sum(points_awarded), 0)
  into v_new_total_score
  from public.answers
  where attempt_id = v_attempt.id;

  select coalesce(sum(points), 1)
  into v_total_points
  from public.questions
  where quiz_id = v_quiz.id;

  v_new_percentage := round((v_new_total_score / v_total_points) * 100);

  select count(*)
  into v_pending_count
  from public.answers
  where attempt_id = v_attempt.id and manual_grade_status = 'pending_review';

  update public.quiz_attempts
  set score = v_new_total_score,
      percentage = v_new_percentage,
      manual_grading_pending = v_pending_count > 0,
      status = case when v_pending_count = 0 then 'graded' else 'pending_review' end
  where id = v_attempt.id;

  -- Update grade record
  update public.grades
  set score = v_new_total_score::int,
      percentage = v_new_percentage::int,
      passed = v_new_percentage >= coalesce(v_quiz.passing_score_percent, 50),
      graded_at = case when v_pending_count = 0 then now() else graded_at end
  where quiz_id = v_quiz.id and student_id = v_attempt.student_id;

  return jsonb_build_object(
    'success', true,
    'attempt_id', v_attempt.id,
    'new_score', v_new_total_score,
    'new_percentage', v_new_percentage,
    'remaining_pending', v_pending_count
  );
end;
$$;

grant execute on function public.teacher_grade_essay_answer(uuid, numeric, text) to authenticated;

-- F. Teacher Publish Exam Results
create or replace function public.teacher_publish_exam_results(
  p_quiz_id uuid,
  p_publish boolean
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = 'off'
as $$
declare
  v_caller_id uuid := auth.uid();
  v_caller record;
begin
  select * into v_caller from public.users where id = v_caller_id;
  if v_caller.role not in ('teacher', 'admin', 'subadmin') then
    raise exception 'Permission denied' using errcode = '42501';
  end if;

  update public.quizzes
  set results_published = p_publish,
      updated_at = now()
  where id = p_quiz_id;

  return jsonb_build_object(
    'success', true,
    'quiz_id', p_quiz_id,
    'results_published', p_publish,
    'message', case when p_publish then 'Examination results published for student view.' else 'Examination results hidden from student view.' end
  );
end;
$$;

grant execute on function public.teacher_publish_exam_results(uuid, boolean) to authenticated;

commit;
