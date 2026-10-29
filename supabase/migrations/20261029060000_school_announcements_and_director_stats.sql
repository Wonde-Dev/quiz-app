-- Migration: 20261029060000_school_announcements_and_director_stats.sql
-- Description:
-- 1. Create school_announcements table for Director and Admin to broadcast school notices.
-- 2. Enhance get_school_user_stats to separate total_users (all users including super admin)
--    and school_users (strictly school users: director + teachers + students, excluding super admin).
-- 3. Provide pending_teachers count specifically for school directors.

begin;

-- ============================================================================
-- 1. SCHOOL ANNOUNCEMENTS TABLE
-- ============================================================================

create table if not exists public.school_announcements (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade default '00000000-0000-4000-8000-000000000001',
  author_id uuid not null references public.users(id) on delete cascade,
  author_name text not null,
  author_role text not null default 'Director',
  title text not null,
  content text not null,
  target_audience text not null default 'all', -- 'all', 'teachers', 'students', 'Grade 9', 'Grade 10', 'Grade 11', 'Grade 12'
  is_pinned boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.school_announcements enable row level security;
grant all on public.school_announcements to authenticated;
grant select on public.school_announcements to anon;

drop policy if exists "school_announcements_select" on public.school_announcements;
create policy "school_announcements_select" on public.school_announcements
  for select using (true);

drop policy if exists "school_announcements_manage" on public.school_announcements;
create policy "school_announcements_manage" on public.school_announcements
  for all using (
    private.app_current_role() in ('admin', 'subadmin')
    or author_id = auth.uid()
  );

-- ============================================================================
-- 2. ENHANCED GET_SCHOOL_USER_STATS RPC
-- ============================================================================

create or replace function public.get_school_user_stats(p_school_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = 'off'
as $$
declare
  v_school_id uuid := coalesce(p_school_id, '00000000-0000-4000-8000-000000000001');
  v_total_users int := 0;
  v_school_users int := 0;
  v_subadmins int := 0;
  v_teachers int := 0;
  v_students int := 0;
  v_pending int := 0;
  v_pending_teachers int := 0;
  v_materials_locked boolean := false;
  v_grades jsonb;
  v_sections jsonb;
begin
  -- Materials locked status
  select coalesce(materials_locked, false) into v_materials_locked
  from public.schools
  where id = v_school_id;

  -- Total active users (including super admin)
  select count(*) into v_total_users
  from public.users
  where is_active != false
    and (school_id = v_school_id or school_id is null);

  -- Role totals
  select count(*) into v_subadmins
  from public.users
  where role = 'subadmin' and is_active != false
    and (school_id = v_school_id or school_id is null);

  select count(*) into v_teachers
  from public.users
  where role = 'teacher' and is_active != false
    and (school_id = v_school_id or school_id is null);

  select count(*) into v_students
  from public.users
  where role = 'student' and is_active != false
    and (school_id = v_school_id or school_id is null);

  -- School users (Director, Teachers, Students - strictly EXCLUDES Super Admin)
  v_school_users := v_subadmins + v_teachers + v_students;

  -- Pending total
  select count(*) into v_pending
  from public.users
  where approval_status = 'pending'
    and (school_id = v_school_id or school_id is null);

  -- Pending teachers specifically (for subadmins/directors)
  select count(*) into v_pending_teachers
  from public.users
  where approval_status = 'pending'
    and (role = 'teacher' or requested_role = 'teacher')
    and (school_id = v_school_id or school_id is null);

  -- Grade breakdowns (Grade 9, 10, 11, 12) - for Subadmins and Teachers
  with grade_list as (
    select unnest(array['Grade 9', 'Grade 10', 'Grade 11', 'Grade 12']) as grade_name
  )
  select jsonb_agg(
    jsonb_build_object(
      'grade', g.grade_name,
      'students', (
        select count(*)
        from public.users u
        where u.role = 'student'
          and u.is_active != false
          and (
            u.assigned_grade = g.grade_name
            or u.requested_grade = g.grade_name
            or u.assigned_class ilike g.grade_name || '%'
            or u.assigned_class ilike replace(g.grade_name, 'Grade ', '') || '%'
          )
      ),
      'teachers', (
        select count(distinct u.id)
        from public.users u
        left join public.teacher_courses tc on tc.teacher_id = u.id
        left join public.sections s on s.id = tc.section_id
        where u.role = 'teacher'
          and u.is_active != false
          and (
            u.assigned_grade = g.grade_name
            or s.grade = g.grade_name
            or u.assigned_class ilike g.grade_name || '%'
            or u.assigned_class ilike replace(g.grade_name, 'Grade ', '') || '%'
          )
      )
    )
  ) into v_grades
  from grade_list g;

  -- Section breakdowns (by Section within Grade) - for Teachers
  select jsonb_agg(
    jsonb_build_object(
      'grade', coalesce(s.grade, 'Grade 9'),
      'section', s.name,
      'students', (
        select count(*)
        from public.users u
        where u.role = 'student'
          and u.is_active != false
          and (
            u.section_id = s.id
            or lower(trim(u.assigned_class)) = lower(trim(s.name))
            or lower(trim(u.assigned_class)) = lower(trim(s.grade || ' ' || s.name))
            or lower(trim(u.assigned_class)) = lower(trim(replace(s.grade, 'Grade ', '') || s.name))
          )
      )
    )
  ) into v_sections
  from public.sections s
  where s.school_id = v_school_id;

  return jsonb_build_object(
    'total_users', v_total_users,
    'school_users', v_school_users,
    'subadmins', v_subadmins,
    'teachers', v_teachers,
    'students', v_students,
    'pending', v_pending,
    'pending_teachers', v_pending_teachers,
    'materials_locked', v_materials_locked,
    'grades', coalesce(v_grades, '[]'::jsonb),
    'sections', coalesce(v_sections, '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_school_user_stats(uuid) to authenticated, anon;

commit;
