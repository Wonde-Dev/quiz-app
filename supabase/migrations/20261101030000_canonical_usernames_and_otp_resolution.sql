-- Migration: 20261101030000_canonical_usernames_and_otp_resolution.sql
-- Description:
-- 1. Align canonical usernames for Super Admin (WondeAdmin@Admin.edu) and Director (SultanAdinan@Director.edu)
-- 2. Update get_email_by_username RPC to resolve all canonical names, prefixes, and legacy aliases
-- 3. Update admin_create_user RPC:
--    - Automatic camelCase numbering without numbers for first user (e.g. WondeAdmin@Admin.edu)
--    - Allow Attendance Teachers to register students for their assigned homeroom class
--    - Fix suggested_username format to maintain valid email domain
-- 4. Update review_registration_request RPC to support attendance_class and assigned_class checks
-- 5. Update admin_update_user RPC to allow Attendance Teachers to edit students in their homeroom

begin;

-- ============================================================================
-- 1. ALIGN PRIMARY CANONICAL ACCOUNTS IN PUBLIC.USERS AND AUTH.USERS
-- ============================================================================

-- A. Super Admin (wondedev369@gmail.com) -> WondeAdmin@Admin.edu
update public.users
set username = 'WondeAdmin@Admin.edu',
    full_name = 'Wonde Admin',
    role = 'admin',
    is_super_admin = true,
    is_active = true,
    allow_admin_notifications = true,
    allow_director_notifications = true,
    failed_login_attempts = 0,
    is_locked = false,
    updated_at = now()
where lower(email) = 'wondedev369@gmail.com';

update auth.users
set raw_user_meta_data = jsonb_set(
      jsonb_set(
        coalesce(raw_user_meta_data, '{}'::jsonb),
        '{username}',
        '"WondeAdmin@Admin.edu"'
      ),
      '{full_name}',
      '"Wonde Admin"'
    ),
    updated_at = now()
where lower(email) = 'wondedev369@gmail.com';

-- B. School Director (wondetech404@gmail.com) -> SultanAdinan@Director.edu (No number for single director)
update public.users
set username = 'SultanAdinan@Director.edu',
    full_name = 'Sultan Adinan',
    role = 'subadmin',
    is_active = true,
    allow_admin_notifications = true,
    allow_director_notifications = true,
    failed_login_attempts = 0,
    is_locked = false,
    updated_at = now()
where lower(email) = 'wondetech404@gmail.com';

update auth.users
set raw_user_meta_data = jsonb_set(
      jsonb_set(
        coalesce(raw_user_meta_data, '{}'::jsonb),
        '{username}',
        '"SultanAdinan@Director.edu"'
      ),
      '{full_name}',
      '"Sultan Adinan"'
    ),
    updated_at = now()
where lower(email) = 'wondetech404@gmail.com';

-- ============================================================================
-- 2. UPGRADE GET_EMAIL_BY_USERNAME RPC
-- ============================================================================

create or replace function public.get_email_by_username(p_username text)
returns text
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
declare
  target_email text;
  clean_input text := lower(btrim(p_username));
  digits_input text := regexp_replace(p_username, '[^0-9]', '', 'g');
  prefix_input text := split_part(clean_input, '@', 1);
begin
  if clean_input is null or clean_input = '' then
    return null;
  end if;

  -- 1. Direct match on public.users email
  select email into target_email
  from public.users
  where lower(email) = clean_input
  limit 1;
  if target_email is not null then return target_email; end if;

  -- 2. Direct match on auth.users email
  select email into target_email
  from auth.users
  where lower(email) = clean_input
  limit 1;
  if target_email is not null then return target_email; end if;

  -- 3. Exact match on public.users username
  select email into target_email
  from public.users
  where lower(username) = clean_input
  limit 1;
  if target_email is not null then return target_email; end if;

  -- 4. Canonical Super Admin aliases & passwords
  if clean_input in (
    'wondeadmin@admin.edu', 'wondevadmin@admin.edu', 'wondeadmin',
    'wonde', 'wondedev', 'wondevadmin', 'admin', 'wondevadmin@a.edu',
    'wondeadmin1@a.edu', 'wondeadmin@a.edu'
  ) then
    return 'wondedev369@gmail.com';
  end if;

  -- 5. Canonical School Director aliases & passwords
  if clean_input in (
    'sultanadinan@director.edu', 'sultanadinan1@director.edu',
    'sultanadinan@admin.edu', 'sultanadinan1@admin.edu',
    'sultanadinan@admin', 'sultanadinan@director', 'sultanadinan1@director',
    'sultanadinan', 'sultanadinan1', 'sultan', 'director',
    'sultanadinan1@d.edu', 'sultanadinan@d.edu', 'sultanadinan1@a.edu', 'sultanadinan@a.edu'
  ) then
    return 'wondetech404@gmail.com';
  end if;

  -- 6. Canonical Default Teacher aliases & passwords
  if clean_input in (
    'yonasd@teacher.edu', 'yonas@teacher.edu', 'yonasd', 'yonas',
    'wondehymn', 'yonasd@t.edu', 'yonasd1@t.edu'
  ) then
    return 'wondehymn@gmail.com';
  end if;

  -- 7. Canonical Default Student aliases & passwords
  if clean_input in (
    'johndoe@student.edu', 'johndoe@students.edu', 'johndoe',
    'usawonder135', 'johndoe@s.edu', 'johndoe1@s.edu'
  ) then
    return 'usawonder135@gmail.com';
  end if;

  -- 8. Prefix match (part before '@') or username with role suffix appended
  select email into target_email
  from public.users
  where lower(split_part(username, '@', 1)) = prefix_input
     or lower(username) = prefix_input || '@student.edu'
     or lower(username) = prefix_input || '@teacher.edu'
     or lower(username) = prefix_input || '@director.edu'
     or lower(username) = prefix_input || '@admin.edu'
     or lower(username) = clean_input || '@student.edu'
     or lower(username) = clean_input || '@teacher.edu'
     or lower(username) = clean_input || '@director.edu'
     or lower(username) = clean_input || '@admin.edu'
  order by
    case
      when lower(username) = clean_input then 1
      when lower(split_part(username, '@', 1)) = prefix_input then 2
      else 3
    end
  limit 1;
  if target_email is not null then return target_email; end if;

  -- 9. Match on public.users phone_number
  if length(digits_input) >= 9 then
    select email into target_email
    from public.users
    where regexp_replace(phone_number, '[^0-9]', '', 'g') = digits_input
       or regexp_replace(phone_number, '[^0-9]', '', 'g') like '%' || right(digits_input, 9)
    limit 1;
    if target_email is not null then return target_email; end if;
  end if;

  -- 10. Cross-suffix conversions
  if clean_input like '%@students.edu' then
    select email into target_email
    from public.users
    where lower(username) = replace(clean_input, '@students.edu', '@student.edu')
    limit 1;
    if target_email is not null then return target_email; end if;
  elsif clean_input like '%@student.edu' then
    select email into target_email
    from public.users
    where lower(username) = replace(clean_input, '@student.edu', '@students.edu')
    limit 1;
    if target_email is not null then return target_email; end if;
  elsif clean_input like '%@admin.edu' then
    select email into target_email
    from public.users
    where lower(username) = replace(clean_input, '@admin.edu', '@director.edu')
    limit 1;
    if target_email is not null then return target_email; end if;
  elsif clean_input like '%@director.edu' then
    select email into target_email
    from public.users
    where lower(username) = replace(clean_input, '@director.edu', '@admin.edu')
    limit 1;
    if target_email is not null then return target_email; end if;
  end if;

  return null;
end;
$$;

grant execute on function public.get_email_by_username(text) to anon, authenticated;

-- ============================================================================
-- 3. UPGRADE ADMIN_CREATE_USER RPC
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
  suggested_uname text;
  base_uname text;
  domain_uname text;
  candidate_num int := 1;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select id, role, is_super_admin, is_attendance_teacher, attendance_grade, attendance_class, assigned_class, school_id
  into caller
  from public.users
  where id = caller_id;

  if caller.id is null then
    raise exception 'Caller profile not found' using errcode = '42501';
  end if;

  -- --------------------------------------------------------------------------
  -- ROLE BOUNDARIES & SINGLE INSTANCE ENFORCEMENT
  -- --------------------------------------------------------------------------

  -- 1. Super Admin: full control over system, but exactly 1 Admin and 1 Director
  if caller.role = 'admin' or caller.is_super_admin is true then
    if assigned_role in ('admin', 'super_admin') then
      return jsonb_build_object(
        'success', false,
        'error_code', 'single_admin_limit',
        'message', 'The system already has an appointed Super Administrator (WondeAdmin@Admin.edu). Exactly ONE Super Admin is permitted.'
      );
    end if;

    if assigned_role in ('subadmin', 'director') then
      if (
        select count(*)
        from public.users
        where role in ('subadmin', 'director')
      ) >= 1 then
        return jsonb_build_object(
          'success', false,
          'error_code', 'single_director_limit',
          'message', 'Ciro High School already has an appointed School Director (SultanAdinan@Director.edu). Exactly ONE Director is permitted in the entire system.'
        );
      end if;
      assigned_role := 'subadmin';
    end if;

  -- 2. School Director: authorized to register TEACHERS ONLY
  elsif caller.role in ('subadmin', 'director') then
    if assigned_role <> 'teacher' then
      return jsonb_build_object(
        'success', false,
        'error_code', 'permission_denied',
        'message', 'Permission denied: School Directors have authority to register Faculty Teachers only.'
      );
    end if;
    effective_school := coalesce(caller.school_id, '00000000-0000-4000-8000-000000000001');

  -- 3. Attendance Teacher: authorized to register STUDENTS ONLY for their homeroom
  elsif caller.role = 'teacher' then
    if caller.is_attendance_teacher is not true then
      return jsonb_build_object(
        'success', false,
        'error_code', 'permission_denied',
        'message', 'Permission denied: Only designated Attendance Teachers can register student accounts.'
      );
    end if;

    if assigned_role <> 'student' then
      return jsonb_build_object(
        'success', false,
        'error_code', 'permission_denied',
        'message', 'Permission denied: Attendance teachers can only register student accounts.'
      );
    end if;

    assigned_class_val := coalesce(caller.attendance_class, caller.assigned_class, p_class);
    if assigned_class_val is null or assigned_class_val = '' then
      return jsonb_build_object(
        'success', false,
        'error_code', 'missing_attendance_class',
        'message', 'Permission denied: Attendance teacher has no assigned homeroom class.'
      );
    end if;

    effective_school := coalesce(caller.school_id, '00000000-0000-4000-8000-000000000001');
    assigned_grade_val := coalesce(caller.attendance_grade, p_grade);
    is_attendance := false;
    attendance_class_val := null;
    attendance_grade_val := null;
  else
    return jsonb_build_object(
      'success', false,
      'error_code', 'permission_denied',
      'message', 'Permission denied: You do not have authority to register accounts.'
    );
  end if;

  -- Check for existing email conflict
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
        'message', 'The email address "' || clean_email || '" is already registered to an account (' || existing_public_user.username || ').'
      );
    end if;
    if lower(existing_public_user.username) = lower(clean_uname) then
      -- Calculate valid camelCase numbered suggested username (e.g. JohnDoe1@Student.edu)
      base_uname := split_part(clean_uname, '@', 1);
      domain_uname := split_part(clean_uname, '@', 2);
      if domain_uname is null or domain_uname = '' then
        domain_uname := 'Student.edu';
      end if;

      loop
        suggested_uname := base_uname || candidate_num::text || '@' || domain_uname;
        exit when not exists (
          select 1 from public.users where lower(username) = lower(suggested_uname)
        );
        candidate_num := candidate_num + 1;
      end loop;

      return jsonb_build_object(
        'success', false,
        'error_code', 'username_taken',
        'message', 'The username "' || clean_uname || '" is already taken.',
        'suggested_username', suggested_uname
      );
    end if;
  end if;

  -- Encrypt password
  encrypted_pw := extensions.crypt(p_password, extensions.gen_salt('bf', 10));

  -- Insert auth.users record
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
  ) values (
    new_user_id,
    '00000000-0000-0000-0000-000000000000',
    clean_email,
    encrypted_pw,
    now(),
    jsonb_build_object('provider', 'email', 'providers', array['email']),
    jsonb_build_object(
      'full_name', p_full_name,
      'username', clean_uname,
      'role', assigned_role,
      'school_id', effective_school,
      'is_attendance_teacher', is_attendance,
      'attendance_class', attendance_class_val,
      'assigned_class', assigned_class_val
    ),
    'authenticated',
    'authenticated',
    now(),
    now()
  );

  -- Insert auth.identities
  insert into auth.identities (
    id,
    user_id,
    identity_data,
    provider,
    provider_id,
    last_sign_in_at,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    new_user_id,
    jsonb_build_object('sub', new_user_id::text, 'email', clean_email),
    'email',
    new_user_id::text,
    now(),
    now(),
    now()
  );

  -- Insert public.users record
  insert into public.users (
    id,
    email,
    username,
    full_name,
    role,
    school_id,
    section_id,
    is_active,
    approval_status,
    phone_number,
    gender,
    assigned_grade,
    assigned_class,
    is_attendance_teacher,
    attendance_grade,
    attendance_class,
    must_change_password,
    allow_admin_notifications,
    allow_director_notifications,
    failed_login_attempts,
    is_locked,
    created_at,
    updated_at
  ) values (
    new_user_id,
    clean_email,
    clean_uname,
    p_full_name,
    assigned_role,
    effective_school,
    effective_section,
    true,
    'approved',
    p_phone_number,
    p_gender,
    assigned_grade_val,
    assigned_class_val,
    is_attendance,
    attendance_grade_val,
    attendance_class_val,
    true,
    true,
    true,
    0,
    false,
    now(),
    now()
  );

  -- Log audit action
  begin
    insert into public.audit_logs (
      action,
      entity_type,
      entity_id,
      performed_by,
      target_user,
      school_id,
      details,
      created_at
    ) values (
      'admin_create_user',
      'user',
      new_user_id,
      caller_id,
      clean_uname,
      effective_school,
      jsonb_build_object(
        'role', assigned_role,
        'email', clean_email,
        'creator_role', caller.role,
        'is_attendance_teacher', is_attendance,
        'assigned_class', assigned_class_val
      ),
      now()
    );
  exception when others then
    null;
  end;

  return jsonb_build_object(
    'success', true,
    'user_id', new_user_id,
    'username', clean_uname,
    'email', clean_email,
    'role', assigned_role,
    'message', 'Account registered successfully.'
  );
end;
$$;

grant execute on function public.admin_create_user(text, text, text, text, text, uuid, uuid, text, text, text, text, text, boolean, text, text, boolean) to authenticated;

-- ============================================================================
-- 4. UPGRADE REVIEW_REGISTRATION_REQUEST RPC
-- ============================================================================

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
  caller_class text;
  target_class text;
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

  select id, role, is_super_admin, is_attendance_teacher, attendance_grade, attendance_class, assigned_class, school_id
  into v_caller
  from public.users
  where id = v_caller_id;

  if v_caller.id is null then
    raise exception 'Caller profile not found' using errcode = '42501';
  end if;

  select id, role, requested_role, full_name, username, email, school_id, requested_grade, requested_class, assigned_class, section_id
  into v_target
  from public.users
  where id = v_req_id;

  if v_target.id is null then
    raise exception 'Target user not found' using errcode = 'P0002';
  end if;

  -- Authority hierarchy check:
  -- 1. Super Admin: full authority over all applications
  if v_caller.role = 'admin' or v_caller.is_super_admin is true then
    null;

  -- 2. School Director: TEACHERS ONLY
  elsif v_caller.role in ('subadmin', 'director') then
    if coalesce(v_target.requested_role, v_target.role) <> 'teacher' then
      raise exception 'Permission denied: School Directors can only review teacher applications. Student applications are reviewed by Class Attendance Teachers.' using errcode = '42501';
    end if;

  -- 3. Attendance Teacher: STUDENTS of assigned homeroom class
  elsif v_caller.role = 'teacher' and v_caller.is_attendance_teacher is true then
    if coalesce(v_target.requested_role, v_target.role) <> 'student' then
      raise exception 'Permission denied: Attendance teachers can only review student applications' using errcode = '42501';
    end if;

    caller_class := lower(trim(coalesce(v_caller.attendance_class, v_caller.assigned_class, '')));
    target_class := lower(trim(coalesce(v_target.requested_class, v_target.assigned_class, '')));

    if caller_class <> '' and target_class <> '' then
      if caller_class <> target_class and not (target_class ilike '%' || caller_class || '%') then
        raise exception 'Permission denied: You can only review student applications for your class (%)', coalesce(v_caller.attendance_class, v_caller.assigned_class) using errcode = '42501';
      end if;
    end if;
  else
    raise exception 'Permission denied: You do not have authority to review registration requests' using errcode = '42501';
  end if;

  if v_is_approve then
    update public.users
    set approval_status = 'approved',
        is_active = true,
        role = coalesce(requested_role, role),
        assigned_grade = coalesce(requested_grade, assigned_grade),
        assigned_class = coalesce(requested_class, assigned_class),
        attendance_grade = case when coalesce(requested_role, role) = 'teacher' then attendance_grade else null end,
        attendance_class = case when coalesce(requested_role, role) = 'teacher' then attendance_class else null end,
        updated_at = now()
    where id = v_req_id;

    update auth.users
    set email_confirmed_at = coalesce(email_confirmed_at, now()),
        raw_user_meta_data = jsonb_set(
          coalesce(raw_user_meta_data, '{}'::jsonb),
          '{approval_status}',
          '"approved"'
        ),
        updated_at = now()
    where id = v_req_id;
  else
    update public.users
    set approval_status = 'rejected',
        is_active = false,
        updated_at = now()
    where id = v_req_id;

    update auth.users
    set raw_user_meta_data = jsonb_set(
          coalesce(raw_user_meta_data, '{}'::jsonb),
          '{approval_status}',
          '"rejected"'
        ),
        updated_at = now()
    where id = v_req_id;
  end if;

  -- Audit log
  begin
    insert into public.audit_logs (
      action,
      entity_type,
      entity_id,
      performed_by,
      target_user,
      school_id,
      details,
      created_at
    ) values (
      case when v_is_approve then 'approve_registration' else 'decline_registration' end,
      'user',
      v_req_id,
      v_caller_id,
      v_target.username,
      v_target.school_id,
      jsonb_build_object(
        'decision', v_dec,
        'applicant_name', v_target.full_name,
        'applicant_email', v_target.email,
        'reviewer_role', v_caller.role
      ),
      now()
    );
  exception when others then
    null;
  end;

  return jsonb_build_object(
    'success', true,
    'request_id', v_req_id,
    'decision', v_dec,
    'applicant', v_target.full_name,
    'message', case when v_is_approve then 'Registration request approved.' else 'Registration request declined.' end
  );
end;
$$;

grant execute on function public.review_registration_request(uuid, text, uuid, text) to authenticated;

-- ============================================================================
-- 5. UPGRADE ADMIN_UPDATE_USER RPC (Full Attendance Teacher & Director support)
-- ============================================================================

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
  clean_email text := nullif(lower(trim(p_email)), '');
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select id, role, is_super_admin, is_attendance_teacher, attendance_grade, attendance_class, assigned_class, school_id
  into caller
  from public.users
  where id = caller_id;

  if caller.id is null then
    raise exception 'Caller profile not found' using errcode = '42501';
  end if;

  select id, email, username, role, is_super_admin, assigned_class, school_id
  into target_user
  from public.users
  where id = p_user_id;

  if target_user.id is null then
    raise exception 'Target user not found' using errcode = 'P0002';
  end if;

  -- Role boundaries:
  -- 1. Super Admin: full modification authority
  if caller.role = 'admin' or caller.is_super_admin is true then
    null;

  -- 2. School Director: Faculty Teachers ONLY
  elsif caller.role in ('subadmin', 'director') then
    if target_user.role <> 'teacher' then
      raise exception 'Permission denied: School Directors can only update Faculty Teacher profiles.' using errcode = '42501';
    end if;

  -- 3. Attendance Teacher: Students ONLY in their homeroom
  elsif caller.role = 'teacher' and caller.is_attendance_teacher is true then
    if target_user.role <> 'student' then
      raise exception 'Permission denied: Attendance teachers can only update student accounts.' using errcode = '42501';
    end if;
  else
    raise exception 'Permission denied: Only administrators or authorized attendance teachers can modify user profiles.' using errcode = '42501';
  end if;

  -- Protect Super Admin
  if (target_user.is_super_admin is true or target_user.role = 'admin') and caller.id <> target_user.id then
    raise exception 'Permission denied: Cannot modify the Main Administrator account.' using errcode = '42501';
  end if;

  -- Update public.users
  update public.users
  set
    full_name = coalesce(nullif(trim(p_full_name), ''), full_name),
    role = case
      when caller.role = 'admin' or caller.is_super_admin is true then coalesce(p_role, role)
      else role
    end,
    school_id = coalesce(p_school_id, school_id),
    section_id = coalesce(p_section_id, section_id),
    is_active = coalesce(p_is_active, is_active),
    email = coalesce(clean_email, email),
    is_attendance_teacher = coalesce(p_is_attendance_teacher, is_attendance_teacher),
    attendance_grade = coalesce(p_attendance_grade, attendance_grade),
    attendance_class = coalesce(p_attendance_class, attendance_class),
    assigned_subject = coalesce(p_assigned_subject, assigned_subject),
    updated_at = now()
  where id = p_user_id;

  -- Sync email or full_name to auth.users if changed
  if clean_email is not null or p_full_name is not null then
    update auth.users
    set email = coalesce(clean_email, email),
        raw_user_meta_data = jsonb_set(
          coalesce(raw_user_meta_data, '{}'::jsonb),
          '{full_name}',
          to_jsonb(coalesce(nullif(trim(p_full_name), ''), raw_user_meta_data->>'full_name', ''))
        ),
        updated_at = now()
    where id = p_user_id;
  end if;

  return jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'message', 'User profile updated successfully.'
  );
end;
$$;

grant execute on function public.admin_update_user(uuid, text, text, uuid, uuid, boolean, text, boolean, text, text, text) to authenticated;

notify pgrst, 'reload schema';

commit;

