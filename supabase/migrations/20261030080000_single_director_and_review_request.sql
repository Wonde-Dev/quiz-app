-- Migration: 20261030080000_single_director_and_review_request.sql
-- Description:
-- 1. Enforce STRICTLY ONE active School Director for Ciro High School at database level via unique partial index.
-- 2. Create public.review_registration_request RPC for instant approval/declining of pending requests.
--    - School Director can approve or decline TEACHERS ONLY.
--    - Attendance Teachers can approve or decline STUDENTS of their designated class only.
--    - Super Admin can approve or decline any user.
-- 3. Enhance admin_create_user RPC to guard against registering more than one School Director.

begin;

-- ============================================================================
-- 1. SINGLE ACTIVE DIRECTOR ENFORCEMENT
-- ============================================================================

-- Partial unique index: at most ONE active director for Ciro High School
drop index if exists public.idx_ciro_single_active_director;

create unique index idx_ciro_single_active_director
on public.users (coalesce(school_id, '00000000-0000-4000-8000-000000000001'))
where role in ('subadmin', 'director') and is_active = true;

-- ============================================================================
-- 2. REVIEW REGISTRATION REQUEST RPC (Approve & Decline with Strict Scoping)
-- ============================================================================

drop function if exists public.review_registration_request(uuid, text);
drop function if exists public.review_registration_request(jsonb);

create or replace function public.review_registration_request(
  p_request_id uuid default null,
  p_decision text default null,
  request_id uuid default null,
  decision text default null
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
  v_target record;
  v_req_id uuid := coalesce(p_request_id, request_id);
  v_dec text := lower(trim(coalesce(p_decision, decision, '')));
  v_is_approve boolean := (v_dec in ('approve', 'approved'));
begin
  if v_caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if v_req_id is null then
    raise exception 'Request ID is required' using errcode = '23502';
  end if;

  if v_dec not in ('approve', 'approved', 'reject', 'rejected', 'decline', 'declined') then
    raise exception 'Invalid decision. Expected approve or decline' using errcode = '22023';
  end if;

  select id, role, is_super_admin, is_attendance_teacher, attendance_grade, attendance_class, school_id
  into v_caller
  from public.users
  where id = v_caller_id;

  if v_caller.id is null then
    raise exception 'Caller profile not found' using errcode = '42501';
  end if;

  select id, role, requested_role, full_name, username, email, school_id, requested_grade, requested_class, section_id
  into v_target
  from public.users
  where id = v_req_id;

  if v_target.id is null then
    raise exception 'Target user not found' using errcode = 'P0002';
  end if;

  -- Authority hierarchy check:
  -- 1. Super Admin: can approve or decline anyone
  if v_caller.role = 'admin' or v_caller.is_super_admin is true then
    null;

  -- 2. School Director: can approve or decline TEACHERS ONLY
  elsif v_caller.role in ('subadmin', 'director') then
    if coalesce(v_target.requested_role, v_target.role) <> 'teacher' then
      raise exception 'Permission denied: School Directors can only review teacher applications. Student applications are reviewed by Class Attendance Teachers.' using errcode = '42501';
    end if;

  -- 3. Attendance Teacher: can approve or decline STUDENTS of their assigned class
  elsif v_caller.role = 'teacher' and v_caller.is_attendance_teacher is true then
    if coalesce(v_target.requested_role, v_target.role) <> 'student' then
      raise exception 'Permission denied: Attendance teachers can only review student applications' using errcode = '42501';
    end if;
    if v_caller.attendance_class is not null and v_caller.attendance_class <> '' then
      if lower(trim(coalesce(v_target.requested_class, ''))) <> lower(trim(v_caller.attendance_class)) and
         not (lower(trim(coalesce(v_target.requested_class, ''))) ilike '%' || lower(trim(v_caller.attendance_class)) || '%') then
        raise exception 'Permission denied: You can only review student applications for your class (%)', v_caller.attendance_class using errcode = '42501';
      end if;
    end if;
  else
    raise exception 'Permission denied: You do not have authority to review registration requests' using errcode = '42501';
  end if;

  if v_is_approve then
    -- Check single director constraint if approving a director
    if coalesce(v_target.requested_role, v_target.role) in ('subadmin', 'director') then
      if (
        select count(*)
        from public.users
        where role in ('subadmin', 'director')
          and is_active = true
          and id <> v_req_id
      ) >= 1 then
        raise exception 'Ciro High School already has an appointed School Director. Only one director is permitted at a time.' using errcode = '23505';
      end if;
    end if;

    update public.users
    set approval_status = 'approved',
        is_active = true,
        role = coalesce(v_target.requested_role, v_target.role),
        school_id = coalesce(v_target.school_id, '00000000-0000-4000-8000-000000000001')
    where id = v_req_id;

    -- Link student to section if specified
    if coalesce(v_target.requested_role, v_target.role) = 'student' and v_target.section_id is not null then
      begin
        insert into public.student_sections (student_id, section_id)
        values (v_req_id, v_target.section_id)
        on conflict do nothing;
      exception when others then null;
      end;
    end if;
  else
    -- Declined / Rejected
    update public.users
    set approval_status = 'rejected',
        is_active = false
    where id = v_req_id;
  end if;

  return jsonb_build_object(
    'success', true,
    'decision', case when v_is_approve then 'approved' else 'declined' end,
    'user_id', v_req_id,
    'role', coalesce(v_target.requested_role, v_target.role)
  );
end;
$$;

create or replace function public.review_registration_request(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = 'off'
as $$
declare
  v_req_id uuid;
  v_decision text;
begin
  v_req_id := nullif(coalesce(payload->>'p_request_id', payload->>'request_id', payload->>'userId'), '')::uuid;
  v_decision := coalesce(payload->>'p_decision', payload->>'decision', 'approve');
  return public.review_registration_request(p_request_id => v_req_id, p_decision => v_decision);
end;
$$;

grant execute on function public.review_registration_request(uuid, text, uuid, text) to authenticated, anon;
grant execute on function public.review_registration_request(jsonb) to authenticated, anon;

-- ============================================================================
-- 3. ENHANCE ADMIN_CREATE_USER WITH SINGLE DIRECTOR CHECK
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
        raise exception 'Ciro High School already has an appointed School Director. Only one director is permitted at a time.' using errcode = '23505';
      end if;
    end if;

  -- 2. School Director: can register TEACHERS ONLY
  elsif caller.role in ('subadmin', 'director') then
    if assigned_role <> 'teacher' then
      raise exception 'Permission denied: School Directors can only register Faculty Teacher accounts. Student registration is handled by attendance teachers.' using errcode = '42501';
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
        or lower(trim(grade || ' ' || name)) = lower(trim(assigned_class_val))
      )
    order by name asc
    limit 1;
  end if;

  -- Check existing in auth.users
  select id into existing_id from auth.users where lower(email) = clean_email;

  if existing_id is not null then
    begin
      delete from auth.users where id = existing_id;
    exception when others then null;
    end;
  end if;

  encrypted_pw := crypt(p_password, gen_salt('bf', 10));

  -- Create in auth.users
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
    now(),
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
      'attendance_class', attendance_class_val
    ),
    'authenticated',
    'authenticated',
    now(),
    now()
  );

  -- Upsert public.users profile
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
    needs_password_change,
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
    false,
    now(),
    now()
  )
  on conflict (id) do update set
    email = excluded.email,
    username = excluded.username,
    full_name = excluded.full_name,
    role = excluded.role,
    school_id = excluded.school_id,
    section_id = excluded.section_id,
    approval_status = 'approved',
    is_active = true,
    assigned_subject = excluded.assigned_subject,
    phone_number = excluded.phone_number,
    gender = excluded.gender,
    assigned_grade = excluded.assigned_grade,
    assigned_class = excluded.assigned_class,
    is_attendance_teacher = excluded.is_attendance_teacher,
    attendance_grade = excluded.attendance_grade,
    attendance_class = excluded.attendance_class,
    updated_at = now();

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

  return jsonb_build_object(
    'success', true,
    'id', new_user_id,
    'username', clean_uname,
    'email', clean_email,
    'role', assigned_role,
    'message', 'User registered and activated successfully'
  );
end;
$$;

commit;
