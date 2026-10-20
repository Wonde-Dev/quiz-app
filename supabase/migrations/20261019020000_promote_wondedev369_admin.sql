begin;

do $$
declare
  auth_account auth.users%rowtype;
begin
  select *
  into auth_account
  from auth.users
  where lower(email) = 'wondedev369@gmail.com'
  limit 1;

  if not found then
    raise notice
      'Admin profile unchanged: no Supabase Auth account exists for wondedev369@gmail.com.';
    return;
  end if;

  if exists (
    select 1
    from public.users
    where lower(username) = lower('WondevAdmin@admin.edu')
      and id <> auth_account.id
  ) then
    raise exception
      'Cannot promote admin: username WondevAdmin@admin.edu is already assigned to another account.';
  end if;

  insert into public.users (
    id,
    email,
    username,
    role,
    full_name,
    school_id,
    must_change_password,
    requested_role,
    approval_status,
    is_active,
    created_at
  ) values (
    auth_account.id,
    lower(auth_account.email),
    'WondevAdmin@admin.edu',
    'admin',
    coalesce(
      nullif(auth_account.raw_user_meta_data ->> 'full_name', ''),
      'Wondev Admin'
    ),
    null,
    false,
    'admin',
    'approved',
    true,
    now()
  )
  on conflict (id) do update
    set email = excluded.email,
        username = excluded.username,
        role = 'admin',
        requested_role = 'admin',
        approval_status = 'approved',
        is_active = true;
end;
$$;

commit;
