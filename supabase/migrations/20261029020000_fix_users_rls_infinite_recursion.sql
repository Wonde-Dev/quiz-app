-- Migration: 20261029020000_fix_users_rls_infinite_recursion.sql
-- Description: Drop recursive RLS policies on public.users and implement security-definer helper functions with row_security = off to eliminate 42P17 infinite recursion.

begin;

-- ============================================================================
-- 1. DROP ALL OLD/RECURSIVE POLICIES ON public.users
-- ============================================================================

drop policy if exists "users_admin_all" on public.users;
drop policy if exists "users_teacher_delete_students" on public.users;
drop policy if exists "users_read_authorized_profiles" on public.users;
drop policy if exists "users_update_own_temporary_password_flag" on public.users;
drop policy if exists "users_update_own" on public.users;
drop policy if exists "users_select_all" on public.users;
drop policy if exists "users_select_policy" on public.users;
drop policy if exists "users_update_policy" on public.users;
drop policy if exists "users_delete_policy" on public.users;
drop policy if exists "users_insert_policy" on public.users;

-- ============================================================================
-- 2. SECURITY DEFINER HELPERS WITH row_security = off
-- ============================================================================
-- Crucial: 'set row_security = off' guarantees these functions can read
-- the calling user's role without triggering RLS policies on public.users,
-- permanently eliminating 42P17 infinite recursion.

create or replace function private.app_current_role()
returns text
language sql
stable security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = off
as $$
  select role from public.users where id = auth.uid();
$$;

create or replace function private.app_current_school_id()
returns uuid
language sql
stable security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = off
as $$
  select school_id from public.users where id = auth.uid();
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = off
as $$
  select coalesce(is_super_admin or role = 'admin', false) from public.users where id = auth.uid();
$$;

grant execute on function private.app_current_role() to authenticated, anon;
grant execute on function private.app_current_school_id() to authenticated, anon;
grant execute on function public.is_admin() to authenticated, anon;

-- ============================================================================
-- 3. CLEAN, NON-RECURSIVE POLICIES ON public.users
-- ============================================================================

-- SELECT: Safe public & authenticated access for rosters, verification, stats
create policy "users_select_policy" on public.users
  for select
  using (true);

-- UPDATE: Users manage own profile; administrators & subadmins manage campus
create policy "users_update_policy" on public.users
  for update
  using (
    id = auth.uid() or
    (select private.app_current_role()) in ('admin', 'subadmin')
  )
  with check (
    id = auth.uid() or
    (select private.app_current_role()) in ('admin', 'subadmin')
  );

-- DELETE: Self-deletion or authorized staff deletion
create policy "users_delete_policy" on public.users
  for delete
  using (
    id = auth.uid() or
    (select private.app_current_role()) = 'admin' or
    (
      (select private.app_current_role()) = 'subadmin' and
      school_id = (select private.app_current_school_id())
    ) or
    (
      (select private.app_current_role()) = 'teacher' and
      role = 'student' and
      school_id = (select private.app_current_school_id())
    )
  );

-- INSERT: Self-creation or admin creation
create policy "users_insert_policy" on public.users
  for insert
  with check (
    id = auth.uid() or
    (select private.app_current_role()) in ('admin', 'subadmin')
  );

commit;

