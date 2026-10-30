-- Migration: 20261030143000_debug_user_yonas.sql

create or replace function public.debug_user_yonas()
returns jsonb
language plpgsql
security definer
as $$
declare
  v_auth record;
  v_identities jsonb;
  v_pub record;
begin
  select id, email, length(email) as l, encode(email::bytea, 'hex') as hex, encrypted_password
  into v_auth
  from auth.users
  where id = 'e587ca15-302a-403c-aec3-e2e64f325f3c';

  select jsonb_agg(row_to_json(i))
  into v_identities
  from auth.identities i
  where i.user_id = 'e587ca15-302a-403c-aec3-e2e64f325f3c';

  select id, email, length(email) as l, encode(email::bytea, 'hex') as hex
  into v_pub
  from public.users
  where id = 'e587ca15-302a-403c-aec3-e2e64f325f3c';

  return jsonb_build_object(
    'auth_user', row_to_json(v_auth),
    'identities', v_identities,
    'public_user', row_to_json(v_pub)
  );
end;
$$;

grant execute on function public.debug_user_yonas() to anon, authenticated;

