-- Migration: 20261030144000_debug_identities_compare.sql

create or replace function public.debug_user_yonas()
returns jsonb
language plpgsql
security definer
as $$
declare
  v_all_identities jsonb;
begin
  select jsonb_agg(row_to_json(i))
  into v_all_identities
  from auth.identities i;

  return v_all_identities;
end;
$$;

grant execute on function public.debug_user_yonas() to anon, authenticated;
