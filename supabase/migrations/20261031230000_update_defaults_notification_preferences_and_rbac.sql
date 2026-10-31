-- ============================================================================
-- Migration: 20261031230000_update_defaults_notification_preferences_and_rbac.sql
-- Description:
--   1. Adds notification preference flags (allow_admin_notifications, allow_director_notifications).
--   2. Sets default teacher (wondehymn@gmail.com) and default student (usawonder135@gmail.com).
--   3. Adds check_email_availability RPC for unique email validation across auth and public.
--   4. Adds update_notification_preferences RPC for user self-service notification control.
--   5. Updates get_email_by_username with default email-to-username mappings.
-- ============================================================================

-- 1. Notification preferences on public.users
alter table public.users add column if not exists allow_admin_notifications boolean default true;
alter table public.users add column if not exists allow_director_notifications boolean default true;

-- 2. Cleanly swap and assign default teacher and student emails
do $$
declare
  v_teacher_id uuid;
  v_student_id uuid;
begin
  -- Identify or find teacher row
  select id into v_teacher_id
  from public.users
  where role = 'teacher'
  order by (email in ('usawonder135@gmail.com', 'wondehymn@gmail.com')) desc, created_at asc
  limit 1;

  -- Identify or find student row
  select id into v_student_id
  from public.users
  where role = 'student'
  order by (email in ('wondehymn@gmail.com', 'usawonder135@gmail.com')) desc, created_at asc
  limit 1;

  -- Step 1: Temporarily vacate student email to avoid unique constraint collision during swap
  if v_student_id is not null then
    update public.users
    set email = 'temp_swap_student@ciroschools.local'
    where id = v_student_id;

    update auth.users
    set email = 'temp_swap_student@ciroschools.local'
    where id = v_student_id;
  end if;

  -- Step 2: Update teacher in public.users to wondehymn@gmail.com
  if v_teacher_id is not null then
    update public.users
    set email = 'wondehymn@gmail.com',
        username = 'YonasD@Teacher.edu',
        full_name = 'Yonas Desta',
        approval_status = 'approved',
        is_active = true,
        updated_at = now()
    where id = v_teacher_id;

    -- Sync in auth.users
    update auth.users
    set email = 'wondehymn@gmail.com',
        encrypted_password = extensions.crypt('YonasD@T.edu', extensions.gen_salt('bf', 10)),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        raw_user_meta_data = jsonb_build_object(
          'username', 'YonasD@Teacher.edu',
          'full_name', 'Yonas Desta',
          'role', 'teacher'
        )
    where id = v_teacher_id;
  end if;

  -- Step 3: Update student in public.users to usawonder135@gmail.com
  if v_student_id is not null then
    update public.users
    set email = 'usawonder135@gmail.com',
        username = 'JohnDoe@Student.edu',
        full_name = 'John Doe',
        approval_status = 'approved',
        is_active = true,
        updated_at = now()
    where id = v_student_id;

    -- Sync in auth.users
    update auth.users
    set email = 'usawonder135@gmail.com',
        encrypted_password = extensions.crypt('JohnDoe@S.edu', extensions.gen_salt('bf', 10)),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        raw_user_meta_data = jsonb_build_object(
          'username', 'JohnDoe@Student.edu',
          'full_name', 'John Doe',
          'role', 'student'
        )
    where id = v_student_id;
  end if;
end $$;

-- 3. Function to check email availability (returns true if available, false if taken)
create or replace function public.check_email_availability(p_email text)
returns boolean
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
declare
  clean_email text := lower(btrim(p_email));
  v_count integer := 0;
begin
  if clean_email is null or clean_email = '' or clean_email not like '%@%' then
    return false;
  end if;

  -- Check public.users
  select count(*) into v_count
  from public.users
  where lower(email) = clean_email;

  if v_count > 0 then
    return false;
  end if;

  -- Check auth.users
  select count(*) into v_count
  from auth.users
  where lower(email) = clean_email;

  if v_count > 0 then
    return false;
  end if;

  return true;
end;
$$;

grant execute on function public.check_email_availability(text) to anon, authenticated;

-- 4. User notification preferences update RPC
create or replace function public.update_notification_preferences(
  p_allow_admin boolean,
  p_allow_director boolean
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'unauthorized', 'message', 'Must be authenticated');
  end if;

  update public.users
  set allow_admin_notifications = coalesce(p_allow_admin, true),
      allow_director_notifications = coalesce(p_allow_director, true),
      updated_at = now()
  where id = v_uid;

  return jsonb_build_object(
    'success', true,
    'allow_admin_notifications', p_allow_admin,
    'allow_director_notifications', p_allow_director
  );
end;
$$;

grant execute on function public.update_notification_preferences(boolean, boolean) to authenticated;

-- 5. Update get_email_by_username with the default teacher and student resolution
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

  -- 5. Match on username domain cross-conversions
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

  -- 6. Prefix match without domain
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

  -- 7. Known canonical institution accounts
  if clean_input in ('wondevadmin@admin.edu', 'wondeadmin@admin.edu', 'wondeadmin', 'wonde', 'wondedev') then
    return 'wondedev369@gmail.com';
  elsif clean_input in ('sultanadinan1@director.edu', 'sultanadinan@director.edu', 'sultanadinan', 'sultan', 'director') then
    return 'wondetech404@gmail.com';
  elsif clean_input in ('yonasd@teacher.edu', 'yonas@teacher.edu', 'yonasd', 'yonas', 'wondehymn') then
    return 'wondehymn@gmail.com';
  elsif clean_input in ('johndoe@student.edu', 'johndoe', 'usawonder135') then
    return 'usawonder135@gmail.com';
  end if;

  return clean_input;
end;
$$;

grant execute on function public.get_email_by_username(text) to anon, authenticated;
