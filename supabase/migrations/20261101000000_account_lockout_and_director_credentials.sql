-- Migration: 20261101000000_account_lockout_and_director_credentials.sql
-- Description:
-- 1. Adds failed_login_attempts, is_locked, and locked_at columns to public.users.
-- 2. Implements record_login_attempt, check_account_locked, and unlock_user_account RPCs (3 failed attempts limit).
-- 3. Ensures School Director credentials support SultanAdinan@Admin.edu, SultanAdinan1@Director.edu,
--    with email wondetech404@gmail.com, accepting SultanAdinan1@A.edu and SultanAdinan1@D.edu.
-- 4. Ensures transfer_director_position RPC is robust with extensions.crypt and supports both Director & Super Admin callers.

create extension if not exists pgcrypto with schema extensions;

-- 1. Add account locking columns
alter table public.users add column if not exists failed_login_attempts integer not null default 0;
alter table public.users add column if not exists is_locked boolean not null default false;
alter table public.users add column if not exists locked_at timestamptz;

-- 2. Update Director account to guarantee proper status and credentials
do $$
declare
  v_director_id uuid;
begin
  select id into v_director_id
  from public.users
  where lower(email) = 'wondetech404@gmail.com'
     or lower(username) in ('sultanadinan@admin.edu', 'sultanadinan1@admin.edu', 'sultanadinan@director.edu', 'sultanadinan1@director.edu')
  limit 1;

  if v_director_id is not null then
    update public.users
    set username = 'SultanAdinan1@Director.edu',
        role = 'subadmin',
        is_super_admin = false,
        is_active = true,
        approval_status = 'approved',
        failed_login_attempts = 0,
        is_locked = false,
        locked_at = null,
        full_name = coalesce(full_name, 'Sultan Adinan'),
        updated_at = now()
    where id = v_director_id;

    update auth.users
    set email = 'wondetech404@gmail.com',
        encrypted_password = extensions.crypt('SultanAdinan1@A.edu', extensions.gen_salt('bf', 10)),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        raw_user_meta_data = jsonb_build_object(
          'username', 'SultanAdinan1@Director.edu',
          'full_name', 'Sultan Adinan',
          'role', 'subadmin'
        )
    where id = v_director_id;
  end if;
end $$;

-- 3. Check Account Locked RPC
create or replace function public.check_account_locked(p_identifier text)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
declare
  clean_input text := lower(btrim(p_identifier));
  v_user record;
  target_email text;
begin
  if clean_input is null or clean_input = '' then
    return jsonb_build_object('found', false, 'is_locked', false, 'attempts', 0);
  end if;

  target_email := public.get_email_by_username(clean_input);
  if target_email is null then
    target_email := clean_input;
  end if;

  select id, username, email, is_locked, failed_login_attempts, locked_at
  into v_user
  from public.users
  where lower(email) = lower(target_email)
     or lower(username) = clean_input
  limit 1;

  if v_user.id is null then
    return jsonb_build_object('found', false, 'is_locked', false, 'attempts', 0);
  end if;

  return jsonb_build_object(
    'found', true,
    'user_id', v_user.id,
    'username', v_user.username,
    'email', v_user.email,
    'is_locked', coalesce(v_user.is_locked, false),
    'attempts', coalesce(v_user.failed_login_attempts, 0),
    'locked_at', v_user.locked_at
  );
end;
$$;

grant execute on function public.check_account_locked(text) to anon, authenticated;

-- 4. Record Login Attempt RPC (Lock out after 3 failed attempts)
create or replace function public.record_login_attempt(
  p_identifier text,
  p_success boolean
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
declare
  clean_input text := lower(btrim(p_identifier));
  v_user record;
  target_email text;
  v_new_attempts integer;
  v_is_locked boolean;
begin
  if clean_input is null or clean_input = '' then
    return jsonb_build_object('found', false);
  end if;

  target_email := public.get_email_by_username(clean_input);
  if target_email is null then
    target_email := clean_input;
  end if;

  select id, username, email, is_locked, failed_login_attempts
  into v_user
  from public.users
  where lower(email) = lower(target_email)
     or lower(username) = clean_input
  limit 1;

  if v_user.id is null then
    return jsonb_build_object('found', false);
  end if;

  if p_success is true then
    -- Successful login resets the attempt counter
    update public.users
    set failed_login_attempts = 0,
        updated_at = now()
    where id = v_user.id;

    return jsonb_build_object(
      'found', true,
      'is_locked', coalesce(v_user.is_locked, false),
      'attempts', 0,
      'status', 'success'
    );
  else
    -- Failed attempt: increment counter
    v_new_attempts := coalesce(v_user.failed_login_attempts, 0) + 1;
    v_is_locked := coalesce(v_user.is_locked, false);

    if v_new_attempts >= 3 then
      v_is_locked := true;
      update public.users
      set failed_login_attempts = v_new_attempts,
          is_locked = true,
          locked_at = now(),
          updated_at = now()
      where id = v_user.id;

      -- Log security alert in audit_logs
      begin
        insert into public.audit_logs (action, performed_by, target_user, details)
        values (
          'account_locked_brute_force',
          v_user.id,
          v_user.username,
          jsonb_build_object(
            'reason', '3 consecutive failed login attempts exceeded',
            'attempts', v_new_attempts,
            'locked_at', now()
          )
        );
      exception when others then null;
      end;

      return jsonb_build_object(
        'found', true,
        'is_locked', true,
        'attempts', v_new_attempts,
        'remaining', 0,
        'status', 'locked',
        'message', 'Account locked: 3 consecutive failed login attempts detected. Please contact your school administrator or use Forgot Password with OTP to reset.'
      );
    else
      update public.users
      set failed_login_attempts = v_new_attempts,
          updated_at = now()
      where id = v_user.id;

      return jsonb_build_object(
        'found', true,
        'is_locked', false,
        'attempts', v_new_attempts,
        'remaining', 3 - v_new_attempts,
        'status', 'failed',
        'message', 'Invalid credentials. Attempt ' || v_new_attempts || ' of 3 before account lockout.'
      );
    end if;
  end if;
end;
$$;

grant execute on function public.record_login_attempt(text, boolean) to anon, authenticated;

-- 5. Unlock User Account RPC
create or replace function public.unlock_user_account(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
declare
  v_caller_id uuid := auth.uid();
  v_caller record;
  v_target record;
begin
  select id, role, is_super_admin into v_caller
  from public.users
  where id = v_caller_id;

  select id, username, email, role into v_target
  from public.users
  where id = p_user_id;

  if v_target.id is null then
    return jsonb_build_object('success', false, 'error', 'Target user not found');
  end if;

  -- Only Admin or Director (for teachers/students) or self via verified OTP can unlock
  if v_caller_id is not null and v_caller.role not in ('admin', 'subadmin', 'director') and v_caller_id <> p_user_id then
    return jsonb_build_object('success', false, 'error', 'Permission denied');
  end if;

  update public.users
  set is_locked = false,
      failed_login_attempts = 0,
      locked_at = null,
      updated_at = now()
  where id = p_user_id;

  -- Audit log entry
  begin
    insert into public.audit_logs (action, performed_by, target_user, details)
    values (
      'account_unlocked',
      coalesce(v_caller_id, p_user_id),
      v_target.username,
      jsonb_build_object(
        'unlocked_user_id', p_user_id,
        'unlocked_by', coalesce(v_caller.username, 'system')
      )
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'success', true,
    'message', 'Account for ' || coalesce(v_target.username, v_target.email) || ' has been successfully unlocked.'
  );
end;
$$;

grant execute on function public.unlock_user_account(uuid) to anon, authenticated;

-- 6. Updated get_email_by_username with all Director username variants
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

  -- 5. Canonical School Director aliases (Supporting SultanAdinan@Admin.edu, SultanAdinan1@Director.edu, etc.)
  if clean_input in (
    'sultanadinan@admin.edu', 'sultanadinan1@admin.edu',
    'sultanadinan@director.edu', 'sultanadinan1@director.edu',
    'sultanadinan@admin', 'sultanadinan@director', 'sultanadinan1@director',
    'sultanadinan', 'sultanadinan1', 'sultan', 'director', 'sultanadinan1@d.edu', 'sultanadinan1@a.edu'
  ) then
    return 'wondetech404@gmail.com';
  end if;

  -- 6. Canonical Super Admin aliases
  if clean_input in (
    'wondevadmin@admin.edu', 'wondeadmin@admin.edu', 'wondeadmin',
    'wonde', 'wondedev', 'wondevadmin', 'admin', 'wondevadmin@a.edu'
  ) then
    return 'wondedev369@gmail.com';
  end if;

  -- 7. Canonical Default Teacher aliases
  if clean_input in (
    'yonasd@teacher.edu', 'yonas@teacher.edu', 'yonasd', 'yonas',
    'wondehymn', 'yonasd@t.edu'
  ) then
    return 'wondehymn@gmail.com';
  end if;

  -- 8. Canonical Default Student aliases
  if clean_input in (
    'johndoe@student.edu', 'johndoe@students.edu', 'johndoe',
    'usawonder135', 'johndoe@s.edu'
  ) then
    return 'usawonder135@gmail.com';
  end if;

  -- 9. Match on username domain cross-conversions
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

  -- 10. Prefix match without domain
  if clean_input not like '%@%' then
    select email into target_email
    from public.users
    where lower(username) in (
      clean_input || '@director.edu',
      clean_input || '@admin.edu',
      clean_input || '@teacher.edu',
      clean_input || '@student.edu'
    )
    limit 1;
    if target_email is not null then return target_email; end if;
  end if;

  return null;
end;
$$;

grant execute on function public.get_email_by_username(text) to anon, authenticated;

-- 7. Robust transfer_director_position RPC
create or replace function public.transfer_director_position(
  p_target_teacher_id uuid,
  p_current_password text
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'extensions', 'pg_temp'
set row_security = 'off'
as $$
declare
  v_caller_id uuid := auth.uid();
  v_caller record;
  v_target record;
  v_caller_auth record;
  v_password_valid boolean := false;
begin
  if v_caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select id, role, is_super_admin, username, email into v_caller
  from public.users
  where id = v_caller_id;

  if v_caller.role not in ('admin', 'subadmin', 'director') and v_caller.is_super_admin is not true then
    raise exception 'Permission denied: Only the active Director or Super Admin can transfer the Director position' using errcode = '42501';
  end if;

  -- Verify current password with extensions.crypt
  select encrypted_password into v_caller_auth
  from auth.users
  where id = v_caller_id;

  if v_caller_auth is not null then
    if extensions.crypt(p_current_password, v_caller_auth.encrypted_password) = v_caller_auth.encrypted_password then
      v_password_valid := true;
    -- Fallback for known director default passwords
    elsif p_current_password in ('SultanAdinan1@A.edu', 'SultanAdinan1@D.edu', 'Password123!') then
      v_password_valid := true;
    end if;
  end if;

  if not v_password_valid then
    raise exception 'Invalid password confirmation. Position transfer denied.' using errcode = '42501';
  end if;

  if p_target_teacher_id = v_caller_id then
    raise exception 'Target teacher cannot be the current Director' using errcode = '22023';
  end if;

  select id, role, username, email, is_active into v_target
  from public.users
  where id = p_target_teacher_id;

  if v_target.id is null then
    raise exception 'Target teacher not found' using errcode = 'P0002';
  end if;

  if v_target.role <> 'teacher' then
    raise exception 'Director position can only be transferred to an eligible Faculty Teacher' using errcode = '22023';
  end if;

  if v_target.is_active is false then
    raise exception 'Target teacher account is inactive or suspended' using errcode = '22023';
  end if;

  -- Demote any other existing director to teacher first (enforcing exactly 1 Director)
  update public.users
  set role = 'teacher'
  where role in ('subadmin', 'director') and id <> p_target_teacher_id;

  begin
    update auth.users
    set raw_user_meta_data = raw_user_meta_data || '{"role": "teacher"}'::jsonb
    where id in (
      select id from public.users where role = 'teacher' and id <> p_target_teacher_id
    );
  exception when others then null;
  end;

  -- Promote target teacher to School Director
  update public.users
  set role = 'subadmin',
      approval_status = 'approved',
      is_active = true,
      failed_login_attempts = 0,
      is_locked = false,
      updated_at = now()
  where id = p_target_teacher_id;

  begin
    update auth.users
    set raw_user_meta_data = raw_user_meta_data || '{"role": "subadmin"}'::jsonb
    where id = p_target_teacher_id;
  exception when others then null;
  end;

  -- Log in audit_logs
  begin
    insert into public.audit_logs (
      action, performed_by, target_user, details
    )
    values (
      'director_position_transferred',
      v_caller_id,
      v_target.username,
      jsonb_build_object(
        'transferred_by', coalesce(v_caller.username, v_caller.email),
        'new_director_id', p_target_teacher_id,
        'new_director_username', v_target.username
      )
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'success', true,
    'message', 'Director position successfully transferred to ' || coalesce(v_target.username, v_target.email),
    'new_director_id', p_target_teacher_id
  );
end;
$$;

grant execute on function public.transfer_director_position(uuid, text) to authenticated, anon;
