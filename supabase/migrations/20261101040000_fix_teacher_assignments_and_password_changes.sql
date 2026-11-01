-- Migration: 20261101040000_fix_teacher_assignments_and_password_changes.sql
-- Description:
-- 1. Fix teacher_courses course_id and section_id nullability constraints
-- 2. Seed all sections A, B, C, D, E for Grades 9, 10, 11, and 12 in Ciro High School
-- 3. Upgrade assign_teacher_to_class RPC to support grade, class, section, and course auto-resolution
-- 4. Create change_own_password RPC for secure password updates
-- 5. Upgrade reset_user_password_admin RPC to ensure full unlock and confirmed email status

begin;

-- ============================================================================
-- 1. FIX TEACHER_COURSES CONSTRAINTS
-- ============================================================================

-- Drop NOT NULL constraint on course_id and section_id so direct or RPC assignments never fail on null course_id
alter table public.teacher_courses alter column course_id drop not null;
alter table public.teacher_courses alter column section_id drop not null;

-- Ensure foreign keys are cascade/set null
alter table public.teacher_courses drop constraint if exists teacher_courses_course_id_fkey;
alter table public.teacher_courses add constraint teacher_courses_course_id_fkey
  foreign key (course_id) references public.courses(id) on delete cascade;

alter table public.teacher_courses drop constraint if exists teacher_courses_section_id_fkey;
alter table public.teacher_courses add constraint teacher_courses_section_id_fkey
  foreign key (section_id) references public.sections(id) on delete cascade;

-- Unique index to prevent duplicate teacher + section + subject pairings
drop index if exists public.idx_teacher_courses_teacher_section_subject;
drop index if exists public.idx_teacher_courses_teacher_sec_subj;
create unique index if not exists idx_teacher_courses_teacher_section_subject
  on public.teacher_courses(teacher_id, section_id, coalesce(subject, ''));

-- ============================================================================
-- 2. SEED SECTIONS A, B, C, D, E FOR GRADES 9, 10, 11, 12 IN CIRO HIGH SCHOOL
-- ============================================================================

-- Ensure school grades exist
insert into public.school_grades (id, school_id, name)
values
  ('c810d0b1-06da-4718-ad5b-112bbb73634f', '00000000-0000-4000-8000-000000000001', 'Grade 9'),
  ('e44369da-dc46-4e3f-ba4f-620abb8f0cdf', '00000000-0000-4000-8000-000000000001', 'Grade 10'),
  ('0585ce0c-9260-4b23-9570-74e2eb8ec7b8', '00000000-0000-4000-8000-000000000001', 'Grade 11'),
  ('ed814422-5c0d-42b8-a546-ff4423a4f4a5', '00000000-0000-4000-8000-000000000001', 'Grade 12')
on conflict (id) do nothing;

-- Insert missing sections for Grade 9
insert into public.sections (school_id, grade_id, grade, name)
values
  ('00000000-0000-4000-8000-000000000001', 'c810d0b1-06da-4718-ad5b-112bbb73634f', 'Grade 9', 'D'),
  ('00000000-0000-4000-8000-000000000001', 'c810d0b1-06da-4718-ad5b-112bbb73634f', 'Grade 9', 'E')
on conflict do nothing;

-- Insert missing sections for Grade 10
insert into public.sections (school_id, grade_id, grade, name)
values
  ('00000000-0000-4000-8000-000000000001', 'e44369da-dc46-4e3f-ba4f-620abb8f0cdf', 'Grade 10', 'D'),
  ('00000000-0000-4000-8000-000000000001', 'e44369da-dc46-4e3f-ba4f-620abb8f0cdf', 'Grade 10', 'E')
on conflict do nothing;

-- Insert missing sections for Grade 11
insert into public.sections (school_id, grade_id, grade, name)
values
  ('00000000-0000-4000-8000-000000000001', '0585ce0c-9260-4b23-9570-74e2eb8ec7b8', 'Grade 11', 'D'),
  ('00000000-0000-4000-8000-000000000001', '0585ce0c-9260-4b23-9570-74e2eb8ec7b8', 'Grade 11', 'E')
on conflict do nothing;

-- Insert missing sections for Grade 12
insert into public.sections (school_id, grade_id, grade, name)
values
  ('00000000-0000-4000-8000-000000000001', 'ed814422-5c0d-42b8-a546-ff4423a4f4a5', 'Grade 12', 'D'),
  ('00000000-0000-4000-8000-000000000001', 'ed814422-5c0d-42b8-a546-ff4423a4f4a5', 'Grade 12', 'E')
on conflict do nothing;

-- ============================================================================
-- 3. UPGRADE ASSIGN_TEACHER_TO_CLASS RPC
-- ============================================================================

drop function if exists public.assign_teacher_to_class(uuid, uuid, text);
drop function if exists public.assign_teacher_to_class(uuid, uuid, text, text, text);

create or replace function public.assign_teacher_to_class(
  p_teacher_id uuid,
  p_section_id uuid default null,
  p_subject text default null,
  p_grade text default null,
  p_class text default null
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
  target_teacher record;
  v_section_id uuid := p_section_id;
  v_course_id uuid;
  v_subject text := coalesce(nullif(trim(p_subject), ''), 'General');
  v_grade text := trim(coalesce(p_grade, 'Grade 9'));
  v_class text := trim(coalesce(p_class, '9A'));
  v_letter text;
  v_grade_id uuid;
  v_ciro_school uuid := '00000000-0000-4000-8000-000000000001';
  v_course_name text;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select id, role, is_super_admin, school_id into caller from public.users where id = caller_id;
  if caller.id is null then
    raise exception 'Caller profile not found' using errcode = '42501';
  end if;

  if caller.role not in ('admin', 'subadmin', 'director') and caller.is_super_admin is not true then
    raise exception 'Permission denied: Only administrators or school directors can assign teachers to classes.' using errcode = '42501';
  end if;

  select id, role, full_name, username, school_id, assigned_grade, assigned_class, assigned_subject
  into target_teacher
  from public.users
  where id = p_teacher_id;

  if target_teacher.id is null then
    raise exception 'Target teacher account not found' using errcode = 'P0002';
  end if;

  if target_teacher.role <> 'teacher' then
    raise exception 'Permission denied: Target user is not a faculty teacher' using errcode = '42501';
  end if;

  -- 1. Resolve or create section if not provided
  if v_section_id is null then
    -- Clean letter (e.g. '9A' -> 'A', '10B' -> 'B')
    v_letter := regexp_replace(v_class, '^[0-9]+', '');
    if v_letter is null or v_letter = '' then
      v_letter := v_class;
    end if;

    -- Lookup existing section
    select id into v_section_id
    from public.sections
    where (lower(grade) = lower(v_grade) or grade = regexp_replace(v_grade, '[^0-9]', ''))
      and (lower(name) = lower(v_class) or lower(name) = lower(v_letter))
      and school_id = v_ciro_school
    limit 1;

    -- If still null, create section
    if v_section_id is null then
      select id into v_grade_id from public.school_grades where lower(name) = lower(v_grade) and school_id = v_ciro_school limit 1;
      if v_grade_id is null then
        v_grade_id := gen_random_uuid();
        insert into public.school_grades (id, school_id, name)
        values (v_grade_id, v_ciro_school, v_grade)
        on conflict do nothing;
      end if;

      v_section_id := gen_random_uuid();
      insert into public.sections (id, school_id, grade_id, grade, name)
      values (v_section_id, v_ciro_school, v_grade_id, v_grade, v_letter)
      on conflict do nothing;
    end if;
  end if;

  -- 2. Resolve or create course in public.courses
  v_course_name := v_subject || ' · ' || v_grade || ' Class ' || v_class;

  select id into v_course_id
  from public.courses
  where teacher_id = p_teacher_id
    and section_id = v_section_id
    and lower(subject) = lower(v_subject)
  limit 1;

  if v_course_id is null then
    v_course_id := gen_random_uuid();
    insert into public.courses (id, school_id, teacher_id, section_id, name, subject, created_at)
    values (v_course_id, v_ciro_school, p_teacher_id, v_section_id, v_course_name, v_subject, now())
    on conflict do nothing;
  end if;

  -- 3. Insert or update teacher_courses
  insert into public.teacher_courses (id, teacher_id, section_id, course_id, subject, assigned_by, assigned_at)
  values (gen_random_uuid(), p_teacher_id, v_section_id, v_course_id, v_subject, caller_id, now())
  on conflict (teacher_id, section_id, coalesce(subject, ''))
  do update set
    course_id = coalesce(excluded.course_id, teacher_courses.course_id),
    assigned_by = excluded.assigned_by,
    assigned_at = now();

  -- 4. Update teacher's primary assignments in public.users if currently unset
  update public.users
  set
    assigned_grade = coalesce(assigned_grade, v_grade),
    assigned_class = coalesce(assigned_class, v_class),
    assigned_subject = coalesce(assigned_subject, v_subject),
    updated_at = now()
  where id = p_teacher_id;

  -- 5. Audit log
  begin
    insert into public.audit_logs (
      action,
      entity_type,
      entity_id,
      performed_by,
      target_user,
      school_id,
      details,
      created_at
    ) values (
      'assign_teacher_to_class',
      'teacher_assignment',
      p_teacher_id,
      caller_id,
      target_teacher.username,
      v_ciro_school,
      jsonb_build_object(
        'teacher_name', target_teacher.full_name,
        'subject', v_subject,
        'grade', v_grade,
        'class', v_class,
        'section_id', v_section_id,
        'course_id', v_course_id
      ),
      now()
    );
  exception when others then
    null;
  end;

  return jsonb_build_object(
    'success', true,
    'section_id', v_section_id,
    'course_id', v_course_id,
    'subject', v_subject,
    'message', 'Teacher successfully allocated to ' || v_grade || ' Class ' || v_class || ' (' || v_subject || ').'
  );
end;
$$;

grant execute on function public.assign_teacher_to_class(uuid, uuid, text, text, text) to authenticated;

-- ============================================================================
-- 4. CREATE CHANGE_OWN_PASSWORD RPC
-- ============================================================================

create or replace function public.change_own_password(
  p_new_password text,
  p_current_password text default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'extensions', 'pg_temp'
set row_security = 'off'
as $$
declare
  v_uid uuid := auth.uid();
  v_auth_user record;
begin
  if v_uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if p_new_password is null or length(trim(p_new_password)) < 6 then
    raise exception 'New password must be at least 6 characters.' using errcode = '22023';
  end if;

  select id, email, encrypted_password into v_auth_user
  from auth.users
  where id = v_uid;

  if v_auth_user.id is null then
    raise exception 'User record not found.' using errcode = 'P0002';
  end if;

  -- If current password provided, verify it against existing encrypted password
  if p_current_password is not null and p_current_password <> '' then
    if v_auth_user.encrypted_password is not null and
       v_auth_user.encrypted_password <> extensions.crypt(p_current_password, v_auth_user.encrypted_password) then
      raise exception 'The current password you entered is incorrect.' using errcode = '28P01';
    end if;
  end if;

  -- Update auth.users encrypted password
  update auth.users
  set encrypted_password = extensions.crypt(p_new_password, extensions.gen_salt('bf', 10)),
      updated_at = now()
  where id = v_uid;

  -- Clear must_change_password and unlock user
  update public.users
  set must_change_password = false,
      failed_login_attempts = 0,
      is_locked = false,
      locked_at = null,
      updated_at = now()
  where id = v_uid;

  -- Audit log
  begin
    insert into public.audit_logs (
      action,
      entity_type,
      entity_id,
      performed_by,
      target_user,
      details,
      created_at
    ) values (
      'password_changed',
      'user',
      v_uid,
      v_uid,
      v_auth_user.email,
      jsonb_build_object('method', 'change_own_password_rpc'),
      now()
    );
  exception when others then
    null;
  end;

  return jsonb_build_object(
    'success', true,
    'message', 'Your password has been updated successfully.'
  );
end;
$$;

grant execute on function public.change_own_password(text, text) to authenticated;

-- ============================================================================
-- 5. UPGRADE RESET_USER_PASSWORD_ADMIN RPC (Full unlock & confirmed email status)
-- ============================================================================

create or replace function public.reset_user_password_admin(
  p_user_id uuid,
  p_password text
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'extensions', 'pg_temp'
set row_security = 'off'
as $$
declare
  caller_id uuid := auth.uid();
  caller record;
  target_user record;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select id, role, is_super_admin, is_attendance_teacher, attendance_grade, attendance_class
  into caller
  from public.users
  where id = caller_id;

  select id, role, is_super_admin, username, email, assigned_grade, assigned_class
  into target_user
  from public.users
  where id = p_user_id;

  if target_user.id is null then
    raise exception 'Target user not found' using errcode = 'P0002';
  end if;

  -- Protect Super Admin
  if (target_user.is_super_admin is true or target_user.role = 'admin') and caller.id <> target_user.id then
    raise exception 'Permission denied: Cannot reset password for Main Administrator account.' using errcode = '42501';
  end if;

  -- Strict Role Hierarchy Enforcement:
  -- A. Super Admin: full authority across all accounts
  if caller.role = 'admin' or caller.is_super_admin is true then
    null;

  -- B. Director: authority over Faculty Teachers ONLY
  elsif caller.role in ('subadmin', 'director') then
    if target_user.role <> 'teacher' then
      raise exception 'Permission denied: School Directors have authority to reset passwords for Faculty Teachers only.' using errcode = '42501';
    end if;

  -- C. Attendance Teacher: authority over Students ONLY (Non-attendance teachers are forbidden)
  elsif caller.role = 'teacher' then
    if caller.is_attendance_teacher is not true then
      raise exception 'Permission denied: Only designated Class Attendance Teachers have authority to reset student passwords.' using errcode = '42501';
    end if;
    if target_user.role <> 'student' then
      raise exception 'Permission denied: Attendance Teachers can only reset passwords for student accounts.' using errcode = '42501';
    end if;

  else
    raise exception 'Permission denied: Unauthorized to reset passwords.' using errcode = '42501';
  end if;

  -- Update auth.users encrypted password and confirm email to prevent login blocks
  update auth.users
  set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf', 10)),
      email_confirmed_at = coalesce(email_confirmed_at, now()),
      banned_until = null,
      raw_user_meta_data = jsonb_set(
        coalesce(raw_user_meta_data, '{}'::jsonb),
        '{must_change_password}',
        'true'
      ),
      updated_at = now()
  where id = p_user_id;

  -- Update public.users flags
  update public.users
  set must_change_password = true,
      failed_login_attempts = 0,
      is_locked = false,
      locked_at = null,
      updated_at = now()
  where id = p_user_id;

  -- Audit log
  begin
    insert into public.audit_logs (
      action,
      entity_type,
      entity_id,
      performed_by,
      target_user,
      details,
      created_at
    ) values (
      'reset_user_password_admin',
      'user',
      p_user_id,
      caller_id,
      target_user.username,
      jsonb_build_object(
        'target_role', target_user.role,
        'reset_by', caller.role
      ),
      now()
    );
  exception when others then
    null;
  end;

  return jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'username', target_user.username,
    'temporary_password', p_password
  );
end;
$$;

grant execute on function public.reset_user_password_admin(uuid, text) to authenticated;

notify pgrst, 'reload schema';

commit;
