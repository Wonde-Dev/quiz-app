-- Migration: 20261031120000_fix_teacher_courses_id_and_approval_flow.sql
-- Description:
-- 1. Adds id primary key column to public.teacher_courses to fix PostgREST column does not exist error.
-- 2. Upgrades review_user_registration RPC to support Director and Attendance Teacher approval flows.
-- 3. Ensures auth.users and public.users are synchronized upon approval with confirmed email.

-- ============================================================================
-- 1. FIX TEACHER_COURSES TABLE SCHEMA
-- ============================================================================

-- Ensure id column exists with default UUID
alter table public.teacher_courses add column if not exists id uuid default gen_random_uuid();
update public.teacher_courses set id = gen_random_uuid() where id is null;
alter table public.teacher_courses alter column id set not null;

-- Make id the primary key if not already
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.teacher_courses'::regclass
      and contype = 'p'
      and conname = 'teacher_courses_id_pkey'
  ) then
    alter table public.teacher_courses drop constraint if exists teacher_courses_pkey cascade;
    alter table public.teacher_courses add constraint teacher_courses_id_pkey primary key (id);
  end if;
exception when others then
  null;
end $$;

-- Ensure other columns exist on teacher_courses
alter table public.teacher_courses add column if not exists section_id uuid references public.sections(id) on delete set null;
alter table public.teacher_courses add column if not exists subject text;
alter table public.teacher_courses add column if not exists course_id uuid references public.courses(id) on delete cascade;
alter table public.teacher_courses add column if not exists assigned_by uuid references public.users(id) on delete set null;
alter table public.teacher_courses add column if not exists assigned_at timestamptz default now();

-- Ensure unique index for conflict handling
create unique index if not exists idx_teacher_courses_teacher_section_subject
  on public.teacher_courses(teacher_id, section_id, coalesce(subject, ''));

grant all on public.teacher_courses to authenticated;
grant select on public.teacher_courses to anon;

-- ============================================================================
-- 2. MASTER REVIEW_USER_REGISTRATION RPC (Support Director & Attendance Teacher)
-- ============================================================================

create or replace function public.review_user_registration(
  p_user_id uuid default null,
  p_decision text default null,
  p_school_id uuid default null,
  user_id uuid default null,
  decision text default null,
  school_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = 'off'
as $$
declare
  caller_id uuid := auth.uid();
  caller record;
  target_user record;
  target_uid uuid := coalesce(p_user_id, user_id);
  target_dec text := coalesce(p_decision, decision);
  target_sid uuid := coalesce(p_school_id, school_id);
  is_approve boolean := (lower(trim(coalesce(target_dec, ''))) in ('approve', 'approved'));
  target_role text;
  clean_target_class text;
  clean_caller_class text;
  v_effective_school uuid;
  v_effective_class text;
  v_effective_section_id uuid;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if target_uid is null then
    raise exception 'User ID is required' using errcode = '23502';
  end if;

  if caller_id = target_uid then
    raise exception 'Permission denied: Self-approval is strictly prohibited' using errcode = '42501';
  end if;

  select id, role, is_super_admin, is_attendance_teacher, attendance_grade, attendance_class, school_id
  into caller
  from public.users
  where id = caller_id;

  select id, role, requested_role, school_id, section_id, requested_grade, requested_class,
         assigned_grade, assigned_class, requested_subject, assigned_subject, full_name, email, username
  into target_user
  from public.users
  where id = target_uid;

  if target_user.id is null then
    return jsonb_build_object('success', false, 'error', 'User registration not found');
  end if;

  target_role := lower(trim(coalesce(nullif(target_user.requested_role, ''), target_user.role, 'student')));

  -- HIERARCHY VALIDATION:
  -- 1. Super Admin: full approval authority
  if caller.role = 'admin' or caller.is_super_admin is true then
    null;

  -- 2. School Director: can approve TEACHERS ONLY
  elsif caller.role in ('subadmin', 'director') then
    if target_role <> 'teacher' then
      raise exception 'Permission denied: School Directors have authority to review and approve Faculty Teachers only. Student registrations are approved by homeroom Attendance Teachers.' using errcode = '42501';
    end if;

  -- 3. Attendance Teacher: can approve STUDENTS of their designated class
  elsif caller.role = 'teacher' and caller.is_attendance_teacher is true then
    if target_role <> 'student' then
      raise exception 'Permission denied: Attendance teachers can only review student registrations' using errcode = '42501';
    end if;

    clean_target_class := regexp_replace(lower(trim(coalesce(nullif(target_user.requested_class, ''), nullif(target_user.assigned_class, ''), ''))), '^(class|grade|section)\s*', '');
    clean_caller_class := regexp_replace(lower(trim(coalesce(caller.attendance_class, ''))), '^(class|grade|section)\s*', '');

    if clean_caller_class <> '' and clean_target_class <> clean_caller_class and clean_target_class <> '' then
      raise exception 'Permission denied: You can only approve students for your assigned class (%)', caller.attendance_class using errcode = '42501';
    end if;
  else
    raise exception 'Permission denied: Unauthorized to review user registrations' using errcode = '42501';
  end if;

  v_effective_school := coalesce(target_sid, target_user.school_id, caller.school_id, '00000000-0000-4000-8000-000000000001');
  v_effective_class := coalesce(target_user.assigned_class, target_user.requested_class);
  v_effective_section_id := target_user.section_id;

  -- Auto-resolve section_id from sections table if missing
  if v_effective_section_id is null and v_effective_school is not null and coalesce(v_effective_class, '') <> '' then
    select id into v_effective_section_id
    from public.sections
    where school_id = v_effective_school
      and (
        lower(trim(name)) = lower(trim(v_effective_class))
        or lower(trim(name)) = lower(trim(regexp_replace(v_effective_class, '^(class|section)\s*', '', 'i')))
        or lower(trim(grade || ' ' || name)) = lower(trim(v_effective_class))
      )
    order by name asc
    limit 1;
  end if;

  if is_approve then
    -- 1. Update public.users
    update public.users
    set
      approval_status = 'approved',
      is_active = true,
      role = target_role,
      school_id = v_effective_school,
      section_id = coalesce(v_effective_section_id, section_id),
      assigned_grade = coalesce(assigned_grade, requested_grade),
      assigned_class = coalesce(assigned_class, requested_class),
      assigned_subject = coalesce(assigned_subject, requested_subject),
      updated_at = now()
    where id = target_uid;

    -- 2. Synchronize auth.users
    update auth.users
    set email_confirmed_at = coalesce(email_confirmed_at, now()),
        raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object(
          'approval_status', 'approved',
          'role', target_role,
          'email_verified', true,
          'school_id', v_effective_school,
          'section_id', v_effective_section_id
        ),
        updated_at = now()
    where id = target_uid;

    -- 3. Auto-link teacher course if subject provided
    if target_role = 'teacher' and v_effective_section_id is not null and target_user.assigned_subject is not null then
      insert into public.teacher_courses (id, teacher_id, section_id, subject, assigned_by)
      values (gen_random_uuid(), target_uid, v_effective_section_id, target_user.assigned_subject, caller_id)
      on conflict (teacher_id, section_id, coalesce(subject, '')) do nothing;
    end if;

    -- 4. Auto-enroll student into section
    if target_role = 'student' and v_effective_section_id is not null then
      insert into public.student_sections (student_id, section_id)
      values (target_uid, v_effective_section_id)
      on conflict do nothing;
    end if;

    -- 5. Audit log
    insert into public.audit_logs (action, performed_by, target_user, details)
    values (
      'account_approved',
      caller_id,
      coalesce(target_user.username, target_uid::text),
      jsonb_build_object(
        'approved_user_id', target_uid,
        'role', target_role,
        'decision', 'approved',
        'performed_by_role', caller.role
      )
    );

    return jsonb_build_object(
      'success', true,
      'status', 'approved',
      'user_id', target_uid,
      'role', target_role,
      'message', 'Registration approved successfully. Account activated.'
    );
  else
    -- Reject
    update public.users
    set
      approval_status = 'rejected',
      is_active = false,
      updated_at = now()
    where id = target_uid;

    update auth.users
    set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object(
          'approval_status', 'rejected'
        ),
        updated_at = now()
    where id = target_uid;

    insert into public.audit_logs (action, performed_by, target_user, details)
    values (
      'account_rejected',
      caller_id,
      coalesce(target_user.username, target_uid::text),
      jsonb_build_object(
        'rejected_user_id', target_uid,
        'role', target_role,
        'decision', 'rejected',
        'performed_by_role', caller.role
      )
    );

    return jsonb_build_object(
      'success', true,
      'status', 'rejected',
      'user_id', target_uid,
      'message', 'Registration declined.'
    );
  end if;
end;
$$;

grant execute on function public.review_user_registration(uuid, text, uuid, uuid, text, uuid) to authenticated;

-- Overload with jsonb payload for versatility
create or replace function public.review_user_registration(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = 'off'
as $$
begin
  return public.review_user_registration(
    (payload->>'user_id')::uuid,
    payload->>'decision',
    case when payload->>'school_id' is not null and payload->>'school_id' <> '' then (payload->>'school_id')::uuid else null end
  );
end;
$$;

grant execute on function public.review_user_registration(jsonb) to authenticated;

