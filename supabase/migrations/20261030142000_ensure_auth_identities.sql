-- Migration: 20261030142000_ensure_auth_identities.sql

begin;

-- 1. Ensure all auth.users have matching identities in auth.identities
insert into auth.identities (
  provider_id,
  user_id,
  identity_data,
  provider,
  last_sign_in_at,
  created_at,
  updated_at
)
select
  u.id::text,
  u.id,
  jsonb_build_object('sub', u.id::text, 'email', lower(trim(u.email)), 'email_verified', true),
  'email',
  now(),
  coalesce(u.created_at, now()),
  now()
from auth.users u
where not exists (
  select 1 from auth.identities where user_id = u.id and provider = 'email'
);

-- 2. Synchronize identity_data email for all users
update auth.identities i
set identity_data = jsonb_build_object('sub', u.id::text, 'email', lower(trim(u.email)), 'email_verified', true),
    updated_at = now()
from auth.users u
where i.user_id = u.id and i.provider = 'email';

commit;
