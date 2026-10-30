-- Migration: 20261030140000_debug_and_fix_auth_triggers.sql

create or replace function public.debug_auth_triggers()
returns jsonb
language plpgsql
security definer
as $$
declare
  v_auth_users jsonb;
begin
  select jsonb_agg(row_to_json(u))
  into v_auth_users
  from (
    select id, email, instance_id, aud, role, is_super_admin, email_confirmed_at, raw_app_meta_data, raw_user_meta_data
    from auth.users
  ) u;

  return v_auth_users;
end;
$$;

grant execute on function public.debug_auth_triggers() to anon, authenticated;
