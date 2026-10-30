-- Migration: 20261030160000_strict_single_admin_single_director_and_rbac.sql
-- Description:
-- 1. Sets SultanAdinan1@Admin.edu as the single Director account.
-- 2. Enforces exactly ONE Super Admin and ONE Director in the entire system.
-- 3. Grants Director full authority over Teachers (register, view, edit, delete, manage),
--    while completely blocking Director authority over Students and Admin accounts.
-- 4. Ensures Super Admin has complete control over the entire system.
-- 5. Restricts Director registration to Teachers only, and Teacher access to Student Registration.

begin;

-- ============================================================================
-- 1. ALIGN DIRECTOR AND ADMIN CREDENTIALS & ACCOUNTS
-- ============================================================================

-- Ensure WondevAdmin is the single active Super Admin
update public.users
set username = 'WondevAdmin@admin.edu',
    role = 'admin',
    is_super_admin = true,
    is_active = true,
    approval_status = 'approved',
    full_name = coalesce(full_name, 'Wondev Admin'),
    phone_number = coalesce(phone_number, '+251911000001')
where id = 'bf883616-97a1-4797-8455-1d8df34917fa'
   or lower(email) = 'wondedev369@gmail.com';

update auth.users
set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || '{"username": "WondevAdmin@admin.edu", "role": "admin", "is_super_admin": true}'::jsonb
where id = 'bf883616-97a1-4797-8455-1d8df34917fa'
   or lower(email) = 'wondedev369@gmail.com';

-- Appoint SultanAdinan1@Admin.edu as the single active School Director
update public.users
set username = 'SultanAdinan1@Admin.edu',
    role = 'subadmin',
    is_super_admin = false,
    is_active = true,
    approval_status = 'approved',
    full_name = coalesce(full_name, 'Sultan Adinan'),
    phone_number = coalesce(phone_number, '+251911000002')
where id = 'd557428f-aaf7-420f-a170-f6a081586b6f'
   or lower(email) = 'wondetech404@gmail.com'
   or lower(username) in ('sultanadinan@admin.edu', 'sultanadinan1@admin.edu');

update auth.users
set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || '{"username": "SultanAdinan1@Admin.edu", "role": "subadmin", "is_super_admin": false}'::jsonb
where id = 'd557428f-aaf7-420f-a170-f6a081586b6f'
   or lower(email) = 'wondetech404@gmail.com';

-- ============================================================================
-- 2. STRICT SYSTEM-WIDE CONSTRAINTS: EXACTLY 1 SUPER ADMIN & 1 DIRECTOR
-- ============================================================================

drop index if exists public.idx_single_active_super_admin;
drop index if exists public.idx_system_single_admin;
create unique index idx_system_single_admin
on public.users ((true))
where role in ('admin', 'super_admin');

drop index if exists public.idx_ciro_single_active_director;
drop index if exists public.idx_system_single_director;
create unique index idx_system_single_director
on public.users ((true))
where role in ('subadmin', 'director');

create or replace function public.check_single_admin_director()
returns trigger
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
begin
  if new.role in ('admin', 'super_admin') then
    if (
      select count(*)
      from public.users
      where role in ('admin', 'super_admin')
        and id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid)
    ) >= 1 then
      raise exception 'System constraint violated: exactly ONE Super Admin is permitted in the entire system.' using errcode = '23505';
    end if;
  end if;

  if new.role in ('subadmin', 'director') then
    if (
      select count(*)
      from public.users
      where role in ('subadmin', 'director')
        and id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid)
    ) >= 1 then
      raise exception 'System constraint violated: exactly ONE School Director is permitted in the entire system.' using errcode = '23505';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_check_single_admin_director on public.users;
create trigger trg_check_single_admin_director
before insert or update of role on public.users
for each row execute function public.check_single_admin_director();

-- ============================================================================
-- 3. RESOLVE EMAIL BY USERNAME (Supporting SultanAdinan1 & All Variations)
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

  -- 3. Match on public.users username
  select email into target_email
  from public.users
  where lower(username) = clean_input
  limit 1;
  if target_email is not null then return target_email; end if;

  -- 4. Match on public.users phone_number
  if length(digits_input) >= 9 then
    select email into target_email
    from public.users
    where regexp_replace(phone_number, '[^0-9]', '', 'g') = digits_input
       or regexp_replace(phone_number, '[^0-9]', '', 'g') like '%' || right(digits_input, 9)
    limit 1;
    if target_email is not null then return target_email; end if;
  end if;

  -- 5. Match on username suffix variants
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
  end if;

  -- 6. Prefix match without domain
  if clean_input not like '%@%' then
    select email into target_email
    from public.users
    where lower(username) in (
      clean_input || '@admin.edu',
      clean_input || '@teacher.edu',
      clean_input || '@student.edu'
    )
    limit 1;
    if target_email is not null then return target_email; end if;
  end if;

  -- 7. Full name match
  select email into target_email
  from public.users
  where lower(full_name) = clean_input
  limit 1;
  if target_email is not null then return target_email; end if;

  -- 8. Explicit Director and Admin aliases
  if clean_input in ('sultanadinan', 'sultanadinan1', 'sultanadinan@admin.edu', 'sultanadinan1@admin.edu', 'director') then
    return 'wondetech404@gmail.com';
  end if;

  if clean_input in ('wonde', 'wondedev', 'wondeadmin', 'wondevadmin@admin.edu', 'wondeadmin@admin.edu', 'superadmin', 'admin') then
    return 'wondedev369@gmail.com';
  end if;

  return null;
end;
$$;

grant execute on function public.get_email_by_username(text) to anon, authenticated;

-- ============================================================================
-- 4. AUTHORITATIVE ADMIN_CREATE_USER RPC
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

  -- --------------------------------------------------------------------------
  -- ROLE BOUNDARIES & SINGLE INSTANCE ENFORCEMENT
  -- --------------------------------------------------------------------------

  -- 1. Super Admin: full control over system, but exactly 1 Admin and 1 Director
  if caller.role = 'admin' or caller.is_super_admin is true then
    if assigned_role in ('admin', 'super_admin') then
      return jsonb_build_object(
        'success', false,
        'error_code', 'single_admin_limit',
        'message', 'The system already has an appointed Super Administrator (WondevAdmin@admin.edu). Exactly ONE Super Admin is permitted.'
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
          'message', 'Ciro High School already has an appointed School Director (SultanAdinan1@Admin.edu). Exactly ONE Director is permitted in the entire system.'
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

  -- 3. Teacher: Attendance Teachers can register STUDENTS ONLY
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

    if caller.attendance_class is null then
      return jsonb_build_object(
        'success', false,
        'error_code', 'missing_attendance_class',
        'message', 'Permission denied: Attendance teacher has no assigned homeroom class.'
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
      'message', 'Permission denied: You do not have authority to register accounts.'
    );
  end if;

  -- Check for existing email or username conflicts
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
      return jsonb_build_object(
        'success', false,
        'error_code', 'username_taken',
        'message', 'The username "' || clean_uname || '" is already taken.',
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

  -- Insert into auth.users with correct instance_id and non-null tokens
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
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change,
    reauthentication_token,
    created_at,
    updated_at
  )
  values (
    new_user_id,
    '00000000-0000-0000-0000-000000000000',
    clean_email,
    encrypted_pw,
    now(),
    '{"provider": "email", "providers": ["email"]}'::jsonb,
    jsonb_build_object(
      'full_name', trim(p_full_name),
      'username', clean_uname,
      'role', assigned_role,
      'is_super_admin', false,
      'school_id', effective_school
    ),
    'authenticated',
    'authenticated',
    '',
    '',
    '',
    '',
    '',
    now(),
    now()
  );

  -- Ensure identity exists in auth.identities
  insert into auth.identities (
    id,
    user_id,
    identity_data,
    provider,
    provider_id,
    last_sign_in_at,
    created_at,
    updated_at
  )
  values (
    new_user_id,
    new_user_id,
    jsonb_build_object('sub', new_user_id::text, 'email', clean_email),
    'email',
    new_user_id::text,
    now(),
    now(),
    now()
  )
  on conflict (provider, provider_id) do nothing;

  -- Insert profile in public.users
  insert into public.users (
    id,
    full_name,
    username,
    email,
    role,
    school_id,
    section_id,
    phone_number,
    gender,
    assigned_subject,
    assigned_grade,
    assigned_class,
    requested_grade,
    requested_class,
    is_attendance_teacher,
    attendance_grade,
    attendance_class,
    approval_status,
    is_active,
    must_change_password,
    created_at,
    updated_at
  )
  values (
    new_user_id,
    trim(p_full_name),
    clean_uname,
    clean_email,
    assigned_role,
    effective_school,
    effective_section,
    nullif(trim(p_phone_number), ''),
    coalesce(p_gender, 'Male'),
    case when assigned_role = 'teacher' then nullif(trim(p_subject), '') else null end,
    assigned_grade_val,
    assigned_class_val,
    assigned_grade_val,
    assigned_class_val,
    is_attendance,
    attendance_grade_val,
    attendance_class_val,
    'approved',
    true,
    false,
    now(),
    now()
  );

  -- Link course section if teacher
  if assigned_role = 'teacher' and effective_section is not null then
    insert into public.teacher_courses (teacher_id, section_id, subject)
    values (new_user_id, effective_section, coalesce(nullif(trim(p_subject), ''), 'General'))
    on conflict do nothing;
  end if;

  -- Link student section if student
  if assigned_role = 'student' and effective_section is not null then
    insert into public.student_sections (student_id, section_id)
    values (new_user_id, effective_section)
    on conflict do nothing;
  end if;

  -- Audit log
  insert into public.audit_logs (action, performed_by, target_user, details)
  values (
    'user_registered',
    caller_id,
    clean_uname,
    jsonb_build_object(
      'registered_user_id', new_user_id,
      'username', clean_uname,
      'email', clean_email,
      'role', assigned_role,
      'school_id', effective_school,
      'performed_by_role', caller.role
    )
  );

  return jsonb_build_object(
    'success', true,
    'user_id', new_user_id,
    'username', clean_uname,
    'email', clean_email,
    'role', assigned_role,
    'temporary_password', coalesce(p_password, 'Pass123!456')
  );
end;
$$;

grant execute on function public.admin_create_user(text, text, text, text, text, uuid, uuid, text, text, text, text, text, boolean, text, text, boolean) to authenticated;

-- ============================================================================
-- 5. AUTHORITATIVE ADMIN_UPDATE_USER RPC (Role Boundary Check)
-- ============================================================================

drop function if exists public.admin_update_user(uuid, text, text, uuid, uuid, boolean, text);
drop function if exists public.admin_update_user(uuid, text, text, uuid, uuid, boolean, text, boolean, text, text, text);

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
set row_security = 'off'
as $$
declare
  caller_id uuid := auth.uid();
  caller record;
  target_user record;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select id, role, is_super_admin, school_id into caller from public.users where id = caller_id;
  if caller.role not in ('admin', 'subadmin', 'director') and caller.is_super_admin is not true then
    raise exception 'Permission denied: Only administrators can modify user profiles' using errcode = '42501';
  end if;

  select id, email, username, role, is_super_admin, school_id into target_user from public.users where id = p_user_id;
  if target_user.id is null then
    raise exception 'Target user not found' using errcode = 'P0002';
  end if;

  -- Protect Super Admin account
  if (target_user.is_super_admin is true or target_user.role = 'admin') and caller.id <> target_user.id and caller.is_super_admin is not true then
    raise exception 'Permission denied: The Main Administrator account is protected and cannot be modified' using errcode = '42501';
  end if;

  -- Director can modify TEACHERS ONLY
  if caller.role in ('subadmin', 'director') and caller.is_super_admin is not true then
    if target_user.role <> 'teacher' then
      raise exception 'Permission denied: School Directors have authority to modify Faculty Teachers only. Directors cannot modify Students or Administrators.' using errcode = '42501';
    end if;

    -- Director cannot change a teacher's role to admin or director
    if p_role is not null and p_role <> 'teacher' then
      raise exception 'Permission denied: School Directors cannot change a teacher to another role.' using errcode = '42501';
    end if;
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
    email = coalesce(nullif(lower(trim(p_email)), ''), email),
    is_attendance_teacher = coalesce(p_is_attendance_teacher, is_attendance_teacher),
    attendance_grade = case when p_is_attendance_teacher = true then coalesce(p_attendance_grade, attendance_grade) else attendance_grade end,
    attendance_class = case when p_is_attendance_teacher = true then coalesce(p_attendance_class, attendance_class) else attendance_class end,
    assigned_subject = coalesce(nullif(trim(p_assigned_subject), ''), assigned_subject),
    updated_at = now()
  where id = p_user_id;

  -- Sync auth.users if email or name changed
  if p_email is not null and trim(p_email) <> '' then
    update auth.users
    set email = lower(trim(p_email)),
        updated_at = now()
    where id = p_user_id;
  end if;

  return jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'message', 'User account updated successfully'
  );
end;
$$;

grant execute on function public.admin_update_user(uuid, text, text, uuid, uuid, boolean, text, boolean, text, text, text) to authenticated;

-- ============================================================================
-- 6. AUTHORITATIVE DELETE_USER_ACCOUNT RPC (Role Boundaries)
-- ============================================================================

drop function if exists public.delete_user_account(uuid);
drop function if exists public.delete_user_account(uuid, uuid);

create or replace function public.delete_user_account(
  p_user_id uuid
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
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select id, role, is_super_admin, is_attendance_teacher, attendance_grade, attendance_class, school_id
  into caller
  from public.users
  where id = caller_id;

  select id, email, username, role, is_super_admin, requested_class, school_id
  into target_user
  from public.users
  where id = p_user_id;

  if target_user.id is null then
    return jsonb_build_object('success', true, 'message', 'Account already deleted');
  end if;

  -- CRITICAL: MAIN ADMIN ACCOUNT CAN NEVER BE DELETED BY ANYONE
  if target_user.is_super_admin is true or
     lower(target_user.email) in ('wondedev369@gmail.com', 'wondeadmin@admin.edu') or
     target_user.role = 'admin' then
    raise exception 'Permission denied: The Main Administrator account is protected and cannot be deleted.' using errcode = '42501';
  end if;

  -- Prevent self-deletion
  if caller_id = p_user_id then
    raise exception 'Permission denied: You cannot delete your own account.' using errcode = '42501';
  end if;

  -- Role boundary check:
  -- 1. Super Admin: can delete teachers, students, director
  if caller.role = 'admin' or caller.is_super_admin is true then
    null;

  -- 2. School Director: can delete TEACHERS ONLY. NO authority over students or admins!
  elsif caller.role in ('subadmin', 'director') then
    if target_user.role <> 'teacher' then
      raise exception 'Permission denied: School Directors have authority to delete Faculty Teachers only. Directors cannot delete Students or Administrators.' using errcode = '42501';
    end if;

  -- 3. Attendance Teacher: can delete STUDENTS ONLY for their designated class
  elsif caller.role = 'teacher' then
    if target_user.role <> 'student' then
      raise exception 'Permission denied: Teachers can only delete student accounts.' using errcode = '42501';
    end if;
    if caller.is_attendance_teacher is not true then
      raise exception 'Permission denied: Only designated Attendance Teachers can delete student accounts.' using errcode = '42501';
    end if;
  else
    raise exception 'Permission denied: Unauthorized to delete user accounts.' using errcode = '42501';
  end if;

  -- Cascade delete child records
  delete from public.answers where student_id = p_user_id;
  delete from public.quiz_attempts where student_id = p_user_id;
  delete from public.grades where student_id = p_user_id;
  delete from public.student_sections where student_id = p_user_id;
  delete from public.teacher_courses where teacher_id = p_user_id;
  delete from public.courses where teacher_id = p_user_id;
  delete from public.course_resources where teacher_id = p_user_id;
  delete from public.teacher_academic_activities where teacher_id = p_user_id::text;
  delete from public.password_reset_requests where user_id = p_user_id;
  delete from public.audit_logs where performed_by = p_user_id or target_user = target_user.username;

  delete from auth.identities where user_id = p_user_id;
  delete from public.users where id = p_user_id;
  delete from auth.users where id = p_user_id;

  return jsonb_build_object('success', true, 'id', p_user_id, 'message', 'Account permanently deleted');
end;
$$;

grant execute on function public.delete_user_account(uuid) to authenticated;

-- Overload with alternate parameter name
create or replace function public.delete_user_account(user_id uuid, p_user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = 'off'
as $$
begin
  return public.delete_user_account(coalesce(p_user_id, user_id));
end;
$$;

grant execute on function public.delete_user_account(uuid, uuid) to authenticated;

-- ============================================================================
-- 7. AUTHORITATIVE RESET_USER_PASSWORD_ADMIN RPC
-- ============================================================================

create or replace function public.reset_user_password_admin(
  p_user_id uuid,
  p_password text
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
  target_user record;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select id, role, is_super_admin into caller from public.users where id = caller_id;
  select id, role, is_super_admin, username, email into target_user from public.users where id = p_user_id;

  if target_user.id is null then
    raise exception 'Target user not found' using errcode = 'P0002';
  end if;

  -- Protect Super Admin
  if (target_user.is_super_admin is true or target_user.role = 'admin') and caller.id <> target_user.id then
    raise exception 'Permission denied: Cannot reset password for Main Administrator account.' using errcode = '42501';
  end if;

  -- Role boundary check:
  if caller.role = 'admin' or caller.is_super_admin is true then
    null;
  elsif caller.role in ('subadmin', 'director') then
    if target_user.role <> 'teacher' then
      raise exception 'Permission denied: School Directors have authority to reset passwords for Faculty Teachers only.' using errcode = '42501';
    end if;
  elsif caller.role = 'teacher' then
    if target_user.role <> 'student' then
      raise exception 'Permission denied: Teachers can only reset passwords for student accounts.' using errcode = '42501';
    end if;
  else
    raise exception 'Permission denied: Unauthorized to reset passwords.' using errcode = '42501';
  end if;

  update auth.users
  set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf', 10)),
      updated_at = now()
  where id = p_user_id;

  update public.users
  set must_change_password = true,
      updated_at = now()
  where id = p_user_id;

  return jsonb_build_object('success', true, 'temporary_password', p_password);
end;
$$;

grant execute on function public.reset_user_password_admin(uuid, text) to authenticated;

-- ============================================================================
-- 8. RLS POLICIES ON PUBLIC.USERS (Strict Role Scoping)
-- ============================================================================

drop policy if exists "users_update_policy" on public.users;
create policy "users_update_policy" on public.users
  for update
  using (
    id = auth.uid() or
    private.app_current_role() = 'admin' or
    (
      private.app_current_role() in ('subadmin', 'director') and
      role = 'teacher' and
      school_id = private.app_current_school_id()
    )
  )
  with check (
    id = auth.uid() or
    private.app_current_role() = 'admin' or
    (
      private.app_current_role() in ('subadmin', 'director') and
      role = 'teacher' and
      school_id = private.app_current_school_id()
    )
  );

drop policy if exists "users_delete_policy" on public.users;
create policy "users_delete_policy" on public.users
  for delete
  using (
    id = auth.uid() or
    private.app_current_role() = 'admin' or
    (
      private.app_current_role() in ('subadmin', 'director') and
      role = 'teacher' and
      school_id = private.app_current_school_id()
    ) or
    (
      private.app_current_role() = 'teacher' and
      role = 'student' and
      school_id = private.app_current_school_id()
    )
  );

commit;
