begin;

-- 1. Helper function for anon & authenticated users to find matching usernames for auto-increment numbering
create or replace function public.get_matching_usernames(p_prefix text)
returns table(username text)
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $$
begin
  return query
  select u.username
  from public.users u
  where u.username ilike trim(p_prefix) || '%';
end;
$$;

grant execute on function public.get_matching_usernames(text) to anon, authenticated;

-- 2. Helper function to check if email or username is already taken
create or replace function public.check_user_exists(p_email text, p_username text)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $$
declare
  clean_email text := lower(trim(p_email));
  clean_uname text := lower(trim(p_username));
  email_exists boolean := false;
  username_exists boolean := false;
begin
  select exists(select 1 from public.users where lower(email) = clean_email) into email_exists;
  select exists(select 1 from public.users where lower(username) = clean_uname) into username_exists;

  return jsonb_build_object(
    'email_taken', email_exists,
    'username_taken', username_exists
  );
end;
$$;

grant execute on function public.check_user_exists(text, text) to anon, authenticated;

-- 3. Dedicated security definer RPC function for Admin to create users with confirmed / approved email
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
  caller record;
  caller_role text;
  new_id uuid := gen_random_uuid();
  clean_email text := lower(trim(p_email));
  clean_username text := trim(p_username);
  existing_id uuid;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select role into caller_role from public.users where id = caller_id;
  if caller_role is null or caller_role <> 'admin' then
    raise exception 'Permission denied: only administrators can create user accounts' using errcode = '42501';
  end if;

  -- Verify unique email & username in public.users
  select id into existing_id from public.users
  where lower(email) = clean_email or lower(username) = lower(clean_username)
  limit 1;

  if existing_id is not null then
    return jsonb_build_object('success', false, 'error', 'An account with this email or username already exists');
  end if;

  -- Verify unique email in auth.users
  select id into existing_id from auth.users
  where lower(email) = clean_email
  limit 1;

  if existing_id is not null then
    return jsonb_build_object('success', false, 'error', 'An auth account with this email already exists');
  end if;

  -- Insert into auth.users with email confirmed immediately!
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
    now(), -- Confirmed immediately by administrator
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

  -- Insert into public.users
  insert into public.users (
    id,
    email,
    username,
    full_name,
    role,
    approval_status,
    is_active,
    school_id,
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
    true
  ) on conflict (id) do update set
    approval_status = 'approved',
    is_active = true,
    must_change_password = true;

  -- Auto-link section for student
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

-- 4. Update review_user_registration to confirm email in auth.users when approved
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
  caller_role text;
  target_user record;
  is_approve boolean := (p_decision = 'approve');
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  -- Role Hierarchy Validation:
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

  if caller_id = p_user_id then
    raise exception 'Permission denied: Self-approval is prohibited' using errcode = '42501';
  end if;

  if caller.role = 'admin' or caller.is_super_admin is true then
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
    raise exception 'Permission denied: Unauthorized to review registrations' using errcode = '42501';
  end if;

  -- Update public.users
  update public.users
  set
    approval_status = case when is_approve then 'approved' else 'rejected' end,
    is_active = is_approve,
    role = case when is_approve and target_user.requested_role is not null then target_user.requested_role else role end,
    school_id = coalesce(p_school_id, school_id)
  where id = p_user_id;

  -- When approving, also confirm email in auth.users so user is immediately activated
  if is_approve then
    update auth.users
    set
      email_confirmed_at = coalesce(email_confirmed_at, now()),
      updated_at = now()
    where id = p_user_id;
  end if;

  return jsonb_build_object('success', true, 'status', case when is_approve then 'approved' else 'rejected' end);
end;
$$;

grant execute on function public.review_user_registration(uuid, text, uuid) to authenticated;

-- 5. Enhanced delete_user_account function
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
    -- Clean up orphan in auth.users if any
    delete from auth.users where id = target_id;
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

  -- Cascade delete child records
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

  -- Delete auth user account
  delete from auth.users where id = target_id;

  return jsonb_build_object('success', true, 'id', target_id);
end;
$$;

grant execute on function public.delete_user_account(uuid, uuid) to authenticated;

commit;

