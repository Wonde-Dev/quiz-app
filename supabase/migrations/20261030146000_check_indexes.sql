-- Migration: 20261030146000_check_indexes.sql

create or replace function public.debug_users_indexes()
returns jsonb
language plpgsql
security definer
as $$
declare
  v_res jsonb;
begin
  select jsonb_agg(jsonb_build_object(
    'tablename', tablename,
    'indexname', indexname,
    'indexdef', indexdef
  ))
  into v_res
  from pg_indexes
  where tablename in ('users') and schemaname in ('public', 'auth');

  return v_res;
end;
$$;

grant execute on function public.debug_users_indexes() to anon, authenticated;

