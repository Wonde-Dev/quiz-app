-- Migration: 20261030148000_check_identities_schema.sql

create or replace function public.debug_identities_schema()
returns jsonb
language plpgsql
security definer
as $$
declare
  v_cols jsonb;
  v_fk jsonb;
begin
  select jsonb_agg(jsonb_build_object(
    'column_name', column_name,
    'data_type', data_type,
    'is_nullable', is_nullable
  ))
  into v_cols
  from information_schema.columns
  where table_schema = 'auth' and table_name = 'identities';

  select jsonb_agg(jsonb_build_object(
    'conname', conname,
    'condef', pg_get_constraintdef(oid)
  ))
  into v_fk
  from pg_constraint
  where conrelid = 'auth.identities'::regclass;

  return jsonb_build_object('columns', v_cols, 'constraints', v_fk);
end;
$$;

grant execute on function public.debug_identities_schema() to anon, authenticated;
