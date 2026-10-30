-- Migration: 20261030145000_check_trigger_def.sql

create or replace function public.debug_trigger_source()
returns text
language plpgsql
security definer
as $$
declare
  v_src text;
begin
  select prosrc into v_src from pg_proc where proname = 'handle_quiz_app_user_signup' limit 1;
  return v_src;
end;
$$;

grant execute on function public.debug_trigger_source() to anon, authenticated;

