-- Migration: 20261030141000_inspect_and_fix_auth_users.sql

create or replace function public.debug_auth_users_detailed()
returns jsonb
language plpgsql
security definer
as $$
declare
  v_res jsonb;
begin
  select jsonb_agg(row_to_json(u))
  into v_res
  from (
    select id, email, instance_id, aud, role, is_super_admin, email_confirmed_at, raw_app_meta_data, raw_user_meta_data
    from auth.users
  ) u;
  return v_res;
end;
$$;

grant execute on function public.debug_auth_users_detailed() to anon, authenticated;

