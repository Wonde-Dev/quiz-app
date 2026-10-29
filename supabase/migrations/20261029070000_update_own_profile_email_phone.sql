-- ==============================================================================
-- UPDATE OWN PROFILE RPC WITH EMAIL AND PHONE NUMBER SUPPORT
-- Allows authenticated users to update their full name, avatar, email, and phone number.
-- Synchronizes public.users and auth.users email and raw_user_meta_data safely.
-- ==============================================================================

-- Drop the old 2-argument signature to prevent ambiguous function call conflicts
drop function if exists public.update_own_profile(text, text);

create or replace function public.update_own_profile(
  p_full_name text default null,
  p_avatar_url text default null,
  p_email text default null,
  p_phone_number text default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
declare
  caller_id uuid := auth.uid();
  clean_name text;
  clean_email text;
  clean_phone text;
  clean_avatar text;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  clean_name := nullif(trim(p_full_name), '');
  clean_email := nullif(lower(trim(p_email)), '');
  clean_phone := nullif(trim(p_phone_number), '');
  clean_avatar := nullif(trim(p_avatar_url), '');

  -- Update public.users
  update public.users
  set
    full_name = coalesce(clean_name, full_name),
    avatar_url = coalesce(clean_avatar, avatar_url),
    email = coalesce(clean_email, email),
    phone_number = coalesce(clean_phone, phone_number)
  where id = caller_id;

  -- Sync email into auth.users if provided
  if clean_email is not null then
    update auth.users
    set email = clean_email
    where id = caller_id;
  end if;

  -- Sync full_name & phone into auth.users metadata if provided
  update auth.users
  set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_strip_nulls(
    jsonb_build_object(
      'full_name', clean_name,
      'phone_number', clean_phone
    )
  )
  where id = caller_id;

  return jsonb_build_object(
    'success', true,
    'full_name', clean_name,
    'email', clean_email,
    'phone_number', clean_phone
  );
end;
$$;

grant execute on function public.update_own_profile(text, text, text, text) to authenticated;
