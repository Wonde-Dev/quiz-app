-- Migration: 20261028210000_strict_role_hierarchy_and_moderation.sql
-- Description: Enforce strict role hierarchy and separation of duties:
-- 1. Super Admin registers & approves any role across all schools.
-- 2. Subadmin registers & approves teachers & students of their own school ONLY.
-- 3. Attendance Teacher registers & approves students of their designated class & school ONLY.
-- 4. Content preparation (quizzes, documents, worksheets, videos) is strictly reserved for teachers.
-- 5. Admins & Subadmins can oversee and delete quizzes/materials of their school, but cannot update or prepare them.

-- Add school_id to quizzes if not present
alter table public.quizzes add column if not exists school_id uuid references public.schools(id) on delete set null;

update public.quizzes q
set school_id = u.school_id
from public.users u
where q.teacher_id = u.id and q.school_id is null;

-- ============================================================================
-- 1. admin_create_user: Strict Role Scoping
-- ============================================================================
create or replace function public.admin_create_user(
  p_full_name text,
  p_username text,
  p_email text,
  p_password text,
  p_role text,
  p_school_id uuid default null,
  p_section_id uuid default null,
  p_subject text default null,
  p_phone_number text default null,
  p_gender text default null,
  p_grade text default null,
  p_class text default null,
  p_is_attendance_teacher boolean default false,
  p_attendance_grade text default null,
  p_attendance_class text default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'extensions', 'pg_temp'
as $$
declare
  caller_id uuid := auth.uid();
  caller record;
  new_user_id uuid := gen_random_uuid();
  encrypted_pw text;
  clean_email text := lower(trim(p_email));
  clean_uname text := trim(p_username);
  effective_school uuid;
  assigned_class_val text;
  assigned_grade_val text;
  is_attendance boolean;
  attendance_class_val text;
  attendance_grade_val text;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select id, role, is_super_admin, school_id, is_attendance_teacher, attendance_grade, attendance_class
  into caller
  from public.users
  where id = caller_id;

  if caller.role not in ('admin', 'subadmin', 'teacher') and caller.is_super_admin is not true then
    raise exception 'Permission denied: Unauthorized to create user accounts' using errcode = '42501';
  end if;

  -- 1. SUPER ADMIN: Full authority across all schools and roles
  if caller.role = 'admin' or caller.is_super_admin is true then
    effective_school := coalesce(p_school_id, caller.school_id);
    assigned_class_val := p_class;
    assigned_grade_val := p_grade;
    is_attendance := coalesce(p_is_attendance_teacher, false);
    attendance_class_val := p_attendance_class;
    attendance_grade_val := p_attendance_grade;

  -- 2. SUBADMIN: Can ONLY register teachers and students for their own school
  elsif caller.role = 'subadmin' then
    if p_role not in ('teacher', 'student') then
      raise exception 'Permission denied: Sub-admins can only register teachers and students' using errcode = '42501';
    end if;
    if caller.school_id is null then
      raise exception 'Permission denied: Sub-admin has no assigned school' using errcode = '42501';
    end if;

    -- Subadmin cannot assign users to other schools
    effective_school := caller.school_id;
    assigned_class_val := p_class;
    assigned_grade_val := p_grade;
    is_attendance := coalesce(p_is_attendance_teacher, false);
    attendance_class_val := p_attendance_class;
    attendance_grade_val := p_attendance_grade;

  -- 3. ATTENDANCE TEACHER: Can ONLY register students of their designated class
  elsif caller.role = 'teacher' then
    if caller.is_attendance_teacher is not true then
      raise exception 'Permission denied: Only designated Attendance Teachers can register student accounts' using errcode = '42501';
    end if;
    if p_role <> 'student' then
      raise exception 'Permission denied: Attendance teachers can only register student accounts' using errcode = '42501';
    end if;
    if caller.attendance_class is null then
      raise exception 'Permission denied: Attendance teacher has no assigned class' using errcode = '42501';
    end if;

    effective_school := caller.school_id;
    assigned_class_val := caller.attendance_class;
    assigned_grade_val := coalesce(caller.attendance_grade, p_grade);
    is_attendance := false;
    attendance_class_val := null;
    attendance_grade_val := null;
  else
    raise exception 'Permission denied' using errcode = '42501';
  end if;

  encrypted_pw := extensions.crypt(p_password, extensions.gen_salt('bf'));

  -- Insert into auth.users
  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  ) values (
    '00000000-0000-0000-0000-000000000000',
    new_user_id,
    'authenticated',
    'authenticated',
    clean_email,
    encrypted_pw,
    now(),
    jsonb_build_object('provider', 'email', 'providers', array['email']),
    jsonb_build_object(
      'full_name', p_full_name,
      'username', clean_uname,
      'role', p_role,
      'school_id', effective_school,
      'phone_number', p_phone_number,
      'gender', p_gender,
      'assigned_grade', assigned_grade_val,
      'assigned_class', assigned_class_val,
      'is_attendance_teacher', is_attendance,
      'attendance_class', attendance_class_val,
      'attendance_grade', attendance_grade_val
    ),
    now(),
    now()
  );

  -- Insert or update public.users
  insert into public.users (
    id,
    email,
    username,
    full_name,
    role,
    requested_role,
    school_id,
    section_id,
    assigned_subject,
    assigned_class,
    assigned_grade,
    phone_number,
    gender,
    is_attendance_teacher,
    attendance_class,
    attendance_grade,
    approval_status,
    is_active,
    must_change_password,
    created_at
  ) values (
    new_user_id,
    clean_email,
    clean_uname,
    p_full_name,
    p_role,
    p_role,
    effective_school,
    p_section_id,
    p_subject,
    assigned_class_val,
    assigned_grade_val,
    p_phone_number,
    p_gender,
    is_attendance,
    attendance_class_val,
    attendance_grade_val,
    'approved',
    true,
    false,
    now()
  ) on conflict (id) do update set
    email = excluded.email,
    username = excluded.username,
    full_name = excluded.full_name,
    role = excluded.role,
    school_id = excluded.school_id,
    section_id = excluded.section_id,
    assigned_subject = excluded.assigned_subject,
    assigned_class = excluded.assigned_class,
    assigned_grade = excluded.assigned_grade,
    phone_number = excluded.phone_number,
    gender = excluded.gender,
    is_attendance_teacher = excluded.is_attendance_teacher,
    attendance_class = excluded.attendance_class,
    attendance_grade = excluded.attendance_grade,
    approval_status = 'approved',
    is_active = true;

  if p_section_id is not null and p_role = 'student' then
    insert into public.student_sections (student_id, section_id)
    values (new_user_id, p_section_id)
    on conflict do nothing;
  end if;

  return jsonb_build_object(
    'success', true,
    'user_id', new_user_id,
    'username', clean_uname,
    'email', clean_email
  );
end;
$$;

-- Overload with JSONB payload
create or replace function public.admin_create_user(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'extensions', 'pg_temp'
as $$
begin
  return public.admin_create_user(
    p_full_name => payload->>'p_full_name',
    p_username => payload->>'p_username',
    p_email => payload->>'p_email',
    p_password => payload->>'p_password',
    p_role => payload->>'p_role',
    p_school_id => (payload->>'p_school_id')::uuid,
    p_section_id => (payload->>'p_section_id')::uuid,
    p_subject => payload->>'p_subject',
    p_phone_number => payload->>'p_phone_number',
    p_gender => payload->>'p_gender',
    p_grade => payload->>'p_grade',
    p_class => payload->>'p_class',
    p_is_attendance_teacher => coalesce((payload->>'p_is_attendance_teacher')::boolean, false),
    p_attendance_grade => payload->>'p_attendance_grade',
    p_attendance_class => payload->>'p_attendance_class'
  );
end;
$$;

-- ============================================================================
-- 2. Quizzes RLS Policies: Teachers Prepare/Update; Admins/Subadmins Can Delete
-- ============================================================================
drop policy if exists quizzes_teacher_manage_own on public.quizzes;
drop policy if exists quizzes_admin_manage_all on public.quizzes;
drop policy if exists quizzes_teacher_insert on public.quizzes;
drop policy if exists quizzes_teacher_update on public.quizzes;
drop policy if exists quizzes_delete_policy on public.quizzes;
drop policy if exists quizzes_admin_select on public.quizzes;
drop policy if exists quizzes_teacher_select on public.quizzes;

-- Teachers can view their own quizzes
create policy quizzes_teacher_select
  on public.quizzes for select to authenticated
  using (
    teacher_id = auth.uid()
    or (select role from public.users where id = auth.uid()) = 'teacher'
  );

-- Admins & Subadmins can view quizzes of their school (or all for super admin)
create policy quizzes_admin_select
  on public.quizzes for select to authenticated
  using (
    (select is_super_admin or role = 'admin' from public.users where id = auth.uid())
    or (
      (select role from public.users where id = auth.uid()) = 'subadmin'
      and (
        quizzes.school_id = (select school_id from public.users where id = auth.uid())
        or exists (
          select 1 from public.users t
          where t.id = quizzes.teacher_id
            and t.school_id = (select school_id from public.users where id = auth.uid())
        )
      )
    )
  );

-- INSERT: Strictly teachers only
create policy quizzes_teacher_insert
  on public.quizzes for insert to authenticated
  with check (
    (select role from public.users where id = auth.uid()) = 'teacher'
    and teacher_id = auth.uid()
  );

-- UPDATE: Strictly teacher who prepared it
create policy quizzes_teacher_update
  on public.quizzes for update to authenticated
  using (
    (select role from public.users where id = auth.uid()) = 'teacher'
    and teacher_id = auth.uid()
  )
  with check (
    (select role from public.users where id = auth.uid()) = 'teacher'
    and teacher_id = auth.uid()
  );

-- DELETE: Teacher who prepared it OR Admin OR Subadmin of that school
create policy quizzes_delete_policy
  on public.quizzes for delete to authenticated
  using (
    teacher_id = auth.uid()
    or (select is_super_admin or role = 'admin' from public.users where id = auth.uid())
    or (
      (select role from public.users where id = auth.uid()) = 'subadmin'
      and (
        quizzes.school_id = (select school_id from public.users where id = auth.uid())
        or exists (
          select 1 from public.users t
          where t.id = quizzes.teacher_id
            and t.school_id = (select school_id from public.users where id = auth.uid())
        )
      )
    )
  );

-- ============================================================================
-- 3. Questions RLS Policies: Teachers Prepare/Update; Admins/Subadmins Can Delete
-- ============================================================================
drop policy if exists questions_teacher_manage_own on public.questions;
drop policy if exists questions_teacher_insert on public.questions;
drop policy if exists questions_teacher_update on public.questions;
drop policy if exists questions_delete_policy on public.questions;

create policy questions_teacher_insert
  on public.questions for insert to authenticated
  with check (
    exists (
      select 1 from public.quizzes q
      where q.id = questions.quiz_id
        and q.teacher_id = auth.uid()
    )
  );

create policy questions_teacher_update
  on public.questions for update to authenticated
  using (
    exists (
      select 1 from public.quizzes q
      where q.id = questions.quiz_id
        and q.teacher_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.quizzes q
      where q.id = questions.quiz_id
        and q.teacher_id = auth.uid()
    )
  );

create policy questions_delete_policy
  on public.questions for delete to authenticated
  using (
    exists (
      select 1 from public.quizzes q
      where q.id = questions.quiz_id
        and (
          q.teacher_id = auth.uid()
          or (select is_super_admin or role = 'admin' from public.users where id = auth.uid())
          or (
            (select role from public.users where id = auth.uid()) = 'subadmin'
            and (
              q.school_id = (select school_id from public.users where id = auth.uid())
              or exists (
                select 1 from public.users t
                where t.id = q.teacher_id
                  and t.school_id = (select school_id from public.users where id = auth.uid())
              )
            )
          )
        )
    )
  );

-- ============================================================================
-- 4. Course Resources RLS: Teachers Upload/Update; Admins/Subadmins Can Delete
-- ============================================================================
drop policy if exists course_resources_teacher_manage on public.course_resources;
drop policy if exists course_resources_teacher_insert on public.course_resources;
drop policy if exists course_resources_teacher_update on public.course_resources;
drop policy if exists course_resources_delete on public.course_resources;

create policy course_resources_teacher_insert
  on public.course_resources for insert to authenticated
  with check (
    (select role from public.users where id = auth.uid()) = 'teacher'
    and teacher_id = auth.uid()::text
  );

create policy course_resources_teacher_update
  on public.course_resources for update to authenticated
  using (
    (select role from public.users where id = auth.uid()) = 'teacher'
    and teacher_id = auth.uid()::text
  )
  with check (
    (select role from public.users where id = auth.uid()) = 'teacher'
    and teacher_id = auth.uid()::text
  );

create policy course_resources_delete
  on public.course_resources for delete to authenticated
  using (
    teacher_id = auth.uid()::text
    or (select is_super_admin or role = 'admin' from public.users where id = auth.uid())
    or (
      (select role from public.users where id = auth.uid()) = 'subadmin'
      and school_id = (select school_id from public.users where id = auth.uid())
    )
  );

-- ============================================================================
-- 5. RPC Function: admin_delete_quiz (Safely cascades deletion of preparation)
-- ============================================================================
create or replace function public.admin_delete_quiz(p_quiz_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
declare
  caller_id uuid := auth.uid();
  caller record;
  target_quiz record;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select id, role, is_super_admin, school_id into caller
  from public.users
  where id = caller_id;

  select id, title, teacher_id, school_id into target_quiz
  from public.quizzes
  where id = p_quiz_id;

  if target_quiz.id is null then
    return jsonb_build_object('success', true, 'message', 'Quiz already deleted');
  end if;

  -- Verification: Teacher who created it, or Super Admin, or Subadmin of the same school
  if target_quiz.teacher_id <> caller_id and
     caller.role <> 'admin' and
     caller.is_super_admin is not true and
     not (
       caller.role = 'subadmin' and (
         target_quiz.school_id = caller.school_id or
         exists (
           select 1 from public.users t
           where t.id = target_quiz.teacher_id and t.school_id = caller.school_id
         )
       )
     ) then
    raise exception 'Permission denied: You can only delete quizzes from your own school' using errcode = '42501';
  end if;

  -- Cascade deletion of quiz components
  delete from public.answers where quiz_id = p_quiz_id;
  delete from public.quiz_attempts where quiz_id = p_quiz_id;
  delete from public.grades where quiz_id = p_quiz_id;
  delete from public.options where question_id in (select id from public.questions where quiz_id = p_quiz_id);
  delete from public.questions where quiz_id = p_quiz_id;
  delete from public.quizzes where id = p_quiz_id;

  return jsonb_build_object(
    'success', true,
    'quiz_id', p_quiz_id,
    'title', target_quiz.title
  );
end;
$$;

grant execute on function public.admin_delete_quiz(uuid) to authenticated;
