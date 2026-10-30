-- Migration: 20261030150000_cleanup_debug_rpcs.sql
-- Remove temporary debug/inspection functions used during GoTrue auth diagnosis.

drop function if exists public.debug_auth_triggers();
drop function if exists public.debug_auth_users_detailed();
drop function if exists public.debug_user_yonas();
drop function if exists public.debug_trigger_source();
drop function if exists public.debug_users_indexes();
drop function if exists public.debug_identities_schema();

