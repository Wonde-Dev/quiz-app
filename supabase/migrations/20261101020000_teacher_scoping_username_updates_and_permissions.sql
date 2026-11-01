-- Migration: 20261101020000_teacher_scoping_username_updates_and_permissions.sql
-- 1. Upgrade update_own_profile RPC to allow updating username (prefix before @role.edu or full institutional username)
-- 2. Upgrade get_email_by_username RPC to support dynamic user-changed usernames and prefix lookups
-- 3. Upgrade reset_user_password_admin RPC:
--    - Super Admin: can reset passwords for ALL users
--    - Director: can reset passwords for TEACHERS ONLY
--    - Attendance Teacher: can reset passwords for STUDENTS ONLY (regular teachers cannot reset passwords)
-- 4. Reload PostgREST schema cache

begin;

-- ==============================================================================
-- 1. UPGRADE update_own_profile RPC TO SUPPORT USERNAME UPDATES
-- ==============================================================================
drop function if exists public.update_own_profile(text, text, text, text);
drop function if exists public.update_own_profile(text, text, text, text, text);

create or replace function public.update_own_profile(
  p_full_name text default null,
  p_avatar_url text default null,
  p_email text default null,
  p_phone_number text default null,
  p_username text default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
declare
  caller_id uuid := auth.uid();
  caller record;
  clean_name text;
  clean_email text;
  clean_phone text;
  clean_avatar text;
  clean_username text;
  role_suffix text;
  final_username text;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into caller from public.users where id = caller_id;
  if caller.id is null then
    raise exception 'User profile not found' using errcode = 'P0002';
  end if;

  clean_name := nullif(trim(p_full_name), '');
  clean_email := nullif(lower(trim(p_email)), '');
  clean_phone := nullif(trim(p_phone_number), '');
  clean_avatar := nullif(trim(p_avatar_url), '');
  clean_username := nullif(trim(p_username), '');

  -- Format username if provided
  if clean_username is not null then
    -- Determine role suffix
    role_suffix := case
      when caller.role = 'admin' or caller.is_super_admin is true then '@Admin.edu'
      when caller.role in ('subadmin', 'director') then '@Director.edu'
      when caller.role = 'teacher' then '@Teacher.edu'
      else '@Student.edu'
    end;

    -- Strip existing suffix if user typed prefix or typed suffix
    if clean_username ilike '%@%.edu' then
      final_username := clean_username;
    else
      -- Append role suffix to the user-entered prefix
      clean_username := regexp_replace(clean_username, '@.*$', '');
      final_username := clean_username || role_suffix;
    end if;

    -- Ensure unique username across other users
    if exists (
      select 1 from public.users
      where lower(username) = lower(final_username)
        and id <> caller_id
    ) then
      raise exception 'Username "%" is already taken. Please choose another prefix.', final_username using errcode = '23505';
    end if;
  else
    final_username := caller.username;
  end if;

  -- Update public.users
  update public.users
  set
    full_name = coalesce(clean_name, full_name),
    avatar_url = coalesce(clean_avatar, avatar_url),
    email = coalesce(clean_email, email),
    phone_number = coalesce(clean_phone, phone_number),
    username = coalesce(final_username, username),
    updated_at = now()
  where id = caller_id;

  -- Sync email into auth.users if provided
  if clean_email is not null then
    update auth.users
    set email = clean_email,
        updated_at = now()
    where id = caller_id;
  end if;

  -- Sync metadata into auth.users
  update auth.users
  set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_strip_nulls(
    jsonb_build_object(
      'full_name', clean_name,
      'phone_number', clean_phone,
      'username', final_username
    )
  ),
  updated_at = now()
  where id = caller_id;

  return jsonb_build_object(
    'success', true,
    'username', final_username,
    'email', coalesce(clean_email, caller.email),
    'full_name', coalesce(clean_name, caller.full_name)
  );
end;
$$;

grant execute on function public.update_own_profile(text, text, text, text, text) to authenticated;

-- ==============================================================================
-- 2. UPGRADE get_email_by_username RPC FOR PREFIX & CUSTOM USERNAMES
-- ==============================================================================
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

  -- 4. Prefix match (part before '@') or username with role suffix appended
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

  -- 5. Match on public.users phone_number
  if length(digits_input) >= 9 then
    select email into target_email
    from public.users
    where regexp_replace(phone_number, '[^0-9]', '', 'g') = digits_input
       or regexp_replace(phone_number, '[^0-9]', '', 'g') like '%' || right(digits_input, 9)
    limit 1;
    if target_email is not null then return target_email; end if;
  end if;

  -- 6. Canonical School Director aliases
  if clean_input in (
    'sultanadinan@admin.edu', 'sultanadinan1@admin.edu',
    'sultanadinan@director.edu', 'sultanadinan1@director.edu',
    'sultanadinan@admin', 'sultanadinan@director', 'sultanadinan1@director',
    'sultanadinan', 'sultanadinan1', 'sultan', 'director', 'sultanadinan1@d.edu', 'sultanadinan1@a.edu'
  ) then
    return 'wondetech404@gmail.com';
  end if;

  -- 7. Canonical Super Admin aliases
  if clean_input in (
    'wondevadmin@admin.edu', 'wondeadmin@admin.edu', 'wondeadmin',
    'wonde', 'wondedev', 'wondevadmin', 'admin', 'wondevadmin@a.edu'
  ) then
    return 'wondedev369@gmail.com';
  end if;

  -- 8. Canonical Default Teacher aliases
  if clean_input in (
    'yonasd@teacher.edu', 'yonas@teacher.edu', 'yonasd', 'yonas',
    'wondehymn', 'yonasd@t.edu'
  ) then
    return 'wondehymn@gmail.com';
  end if;

  -- 9. Canonical Default Student aliases
  if clean_input in (
    'johndoe@student.edu', 'johndoe@students.edu', 'johndoe',
    'usawonder135', 'johndoe@s.edu'
  ) then
    return 'usawonder135@gmail.com';
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

-- ==============================================================================
-- 3. UPGRADE reset_user_password_admin RPC (ROLE-BASED PASSWORD RESET)
-- ==============================================================================
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

  select id, role, is_super_admin, is_attendance_teacher, attendance_grade, attendance_class
  into caller
  from public.users
  where id = caller_id;

  select id, role, is_super_admin, username, email, assigned_grade, assigned_class
  into target_user
  from public.users
  where id = p_user_id;

  if target_user.id is null then
    raise exception 'Target user not found' using errcode = 'P0002';
  end if;

  -- Protect Super Admin
  if (target_user.is_super_admin is true or target_user.role = 'admin') and caller.id <> target_user.id then
    raise exception 'Permission denied: Cannot reset password for Main Administrator account.' using errcode = '42501';
  end if;

  -- Strict Role Hierarchy Enforcement:
  -- A. Super Admin: full authority across all accounts
  if caller.role = 'admin' or caller.is_super_admin is true then
    null;

  -- B. Director: authority over Faculty Teachers ONLY
  elsif caller.role in ('subadmin', 'director') then
    if target_user.role <> 'teacher' then
      raise exception 'Permission denied: School Directors have authority to reset passwords for Faculty Teachers only.' using errcode = '42501';
    end if;

  -- C. Attendance Teacher: authority over Students ONLY (Non-attendance teachers are forbidden)
  elsif caller.role = 'teacher' then
    if caller.is_attendance_teacher is not true then
      raise exception 'Permission denied: Only designated Class Attendance Teachers have authority to reset student passwords.' using errcode = '42501';
    end if;
    if target_user.role <> 'student' then
      raise exception 'Permission denied: Attendance Teachers can only reset passwords for student accounts.' using errcode = '42501';
    end if;

  else
    raise exception 'Permission denied: Unauthorized to reset passwords.' using errcode = '42501';
  end if;

  -- Update auth.users encrypted password
  update auth.users
  set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf', 10)),
      updated_at = now()
  where id = p_user_id;

  -- Update public.users flags
  update public.users
  set must_change_password = true,
      failed_login_attempts = 0,
      is_locked = false,
      locked_at = null,
      updated_at = now()
  where id = p_user_id;

  return jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'username', target_user.username,
    'temporary_password', p_password
  );
end;
$$;

grant execute on function public.reset_user_password_admin(uuid, text) to authenticated;

notify pgrst, 'reload schema';

commit;
