-- Migration: 20261030147000_fix_instance_id.sql

begin;

-- Set all auth.users instance_id to Supabase standard all-zeros UUID
update auth.users
set instance_id = '00000000-0000-0000-0000-000000000000'
where instance_id <> '00000000-0000-0000-0000-000000000000'
   or instance_id is null;

commit;
