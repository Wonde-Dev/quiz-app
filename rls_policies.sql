-- Quiz App Supabase Row Level Security.
-- Run schema.sql first. This file is safe to re-run.

begin;

create schema if not exists private;
revoke all on schema private from public, anon;

create or replace function private.app_current_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select users.role
  from public.users
  where users.id = (select auth.uid())
  limit 1
$$;

create or replace function private.app_current_school_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select users.school_id
  from public.users
  where users.id = (select auth.uid())
  limit 1
$$;

create or replace function private.app_student_can_access_quiz(quiz_owner_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.users as student
    join public.users as quiz_owner on quiz_owner.id = quiz_owner_id
    where student.id = (select auth.uid())
      and student.role = 'student'
      and (
        quiz_owner.role = 'admin'
        or (
          quiz_owner.role = 'teacher'
          and quiz_owner.school_id = student.school_id
        )
      )
  )
$$;

revoke all on function private.app_current_role() from public, anon, authenticated;
revoke all on function private.app_current_school_id() from public, anon, authenticated;
revoke all on function private.app_student_can_access_quiz(uuid) from public, anon, authenticated;
grant usage on schema private to authenticated;
grant execute on function private.app_current_role() to authenticated;
grant execute on function private.app_current_school_id() to authenticated;
grant execute on function private.app_student_can_access_quiz(uuid) to authenticated;

-- Remove policies left by earlier versions before creating the least-privilege
-- policy set. This also makes the script safe to re-import after old policies.
do $$
declare
  policy_row record;
begin
  for policy_row in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'schools', 'users', 'school_grades', 'sections', 'courses',
        'teacher_courses', 'student_sections', 'quizzes', 'questions',
        'grades', 'quiz_attempts', 'answers', 'audit_logs',
        'suspicious_activities', 'password_reset_requests'
      )
  loop
    execute format(
      'drop policy if exists %I on %I.%I',
      policy_row.policyname,
      policy_row.schemaname,
      policy_row.tablename
    );
  end loop;
end;
$$;

alter table public.schools enable row level security;
alter table public.users enable row level security;
alter table public.school_grades enable row level security;
alter table public.sections enable row level security;
alter table public.courses enable row level security;
alter table public.teacher_courses enable row level security;
alter table public.student_sections enable row level security;
alter table public.quizzes enable row level security;
alter table public.questions enable row level security;
alter table public.grades enable row level security;
alter table public.quiz_attempts enable row level security;
alter table public.answers enable row level security;
alter table public.audit_logs enable row level security;
alter table public.suspicious_activities enable row level security;
alter table public.password_reset_requests enable row level security;

-- Remove broad table-level privileges, especially access to legacy password
-- hash columns, and grant only the fields actually used by the app.
revoke all on public.schools, public.users, public.school_grades,
  public.sections, public.courses, public.teacher_courses,
  public.student_sections, public.quizzes, public.questions,
  public.grades, public.quiz_attempts, public.answers,
  public.audit_logs, public.suspicious_activities,
  public.password_reset_requests
from public, anon, authenticated;

grant select on public.schools to anon, authenticated;
grant select on public.school_grades, public.sections to anon;
grant insert on public.schools to authenticated;
grant select (
  id, email, username, role, school_id, full_name, avatar_url,
  must_change_password, requested_role, approval_status, is_active,
  created_at, last_login
) on public.users to authenticated;
grant update (must_change_password) on public.users to authenticated;
grant delete on public.users to authenticated;
grant select on public.school_grades, public.sections, public.courses,
  public.teacher_courses, public.student_sections, public.quizzes,
  public.questions, public.grades, public.quiz_attempts, public.answers,
  public.audit_logs, public.suspicious_activities,
  public.password_reset_requests to authenticated;
grant insert on public.teacher_courses, public.student_sections,
  public.audit_logs, public.suspicious_activities,
  public.password_reset_requests to authenticated;
grant update, delete on public.schools, public.school_grades,
  public.sections, public.courses, public.teacher_courses,
  public.student_sections, public.quizzes, public.questions to authenticated;
grant insert on public.school_grades, public.sections, public.courses,
  public.quizzes, public.questions to authenticated;

create policy schools_read_for_registration
  on public.schools for select to anon, authenticated
  using (true);
create policy school_grades_read_for_registration
  on public.school_grades for select to anon
  using (true);
create policy sections_read_for_registration
  on public.sections for select to anon
  using (true);
create policy schools_admin_manage
  on public.schools for all to authenticated
  using ((select private.app_current_role()) = 'admin')
  with check ((select private.app_current_role()) = 'admin');

create policy users_read_authorized_profiles
  on public.users for select to authenticated
  using (
    id = (select auth.uid())
    or (select private.app_current_role()) = 'admin'
    or (
      (select private.app_current_role()) = 'teacher'
      and role = 'student'
      and school_id = (select private.app_current_school_id())
    )
  );
create policy users_update_own_temporary_password_flag
  on public.users for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));
create policy users_delete_authorized
  on public.users for delete to authenticated
  using (
    (select private.app_current_role()) = 'admin'
    or (
      (select private.app_current_role()) = 'teacher'
      and role = 'student'
      and school_id = (select private.app_current_school_id())
    )
  );

create policy school_grades_read_same_school
  on public.school_grades for select to authenticated
  using (
    (select private.app_current_role()) = 'admin'
    or school_id = (select private.app_current_school_id())
  );
create policy school_grades_admin_manage
  on public.school_grades for all to authenticated
  using ((select private.app_current_role()) = 'admin')
  with check ((select private.app_current_role()) = 'admin');

create policy sections_read_same_school
  on public.sections for select to authenticated
  using (
    (select private.app_current_role()) = 'admin'
    or school_id = (select private.app_current_school_id())
  );
create policy sections_admin_manage
  on public.sections for all to authenticated
  using ((select private.app_current_role()) = 'admin')
  with check ((select private.app_current_role()) = 'admin');

create policy courses_read_same_school
  on public.courses for select to authenticated
  using (
    (select private.app_current_role()) = 'admin'
    or (
      (select private.app_current_role()) = 'teacher'
      and teacher_id = (select auth.uid())
    )
    or (
      (select private.app_current_role()) = 'student'
      and school_id = (select private.app_current_school_id())
    )
  );
create policy courses_admin_manage
  on public.courses for all to authenticated
  using ((select private.app_current_role()) = 'admin')
  with check ((select private.app_current_role()) = 'admin');
create policy teacher_courses_admin_manage
  on public.teacher_courses for all to authenticated
  using ((select private.app_current_role()) = 'admin')
  with check ((select private.app_current_role()) = 'admin');
create policy teacher_courses_teacher_read_own
  on public.teacher_courses for select to authenticated
  using (teacher_id = (select auth.uid()));

create policy student_sections_admin_manage
  on public.student_sections for all to authenticated
  using ((select private.app_current_role()) = 'admin')
  with check ((select private.app_current_role()) = 'admin');
create policy student_sections_read_own_or_same_school_teacher
  on public.student_sections for select to authenticated
  using (
    student_id = (select auth.uid())
    or (
      (select private.app_current_role()) = 'teacher'
      and exists (
        select 1 from public.users as student
        where student.id = student_sections.student_id
          and student.role = 'student'
          and student.school_id = (select private.app_current_school_id())
      )
    )
  );

create policy quizzes_admin_manage
  on public.quizzes for all to authenticated
  using ((select private.app_current_role()) = 'admin')
  with check ((select private.app_current_role()) = 'admin');
create policy quizzes_teacher_manage_own
  on public.quizzes for all to authenticated
  using (
    (select private.app_current_role()) = 'teacher'
    and teacher_id = (select auth.uid())
    and course_id is not null
    and exists (
      select 1
      from public.courses as assigned_course
      where assigned_course.id = quizzes.course_id
        and assigned_course.teacher_id = (select auth.uid())
        and assigned_course.section_id = quizzes.section_id
    )
  )
  with check (
    (select private.app_current_role()) = 'teacher'
    and teacher_id = (select auth.uid())
    and course_id is not null
    and exists (
      select 1
      from public.courses as assigned_course
      where assigned_course.id = quizzes.course_id
        and assigned_course.teacher_id = (select auth.uid())
        and assigned_course.section_id = quizzes.section_id
    )
  );
create policy quizzes_students_read_published_same_school
  on public.quizzes for select to authenticated
  using (
    (select private.app_current_role()) = 'student'
    and is_published
    and (select private.app_student_can_access_quiz(teacher_id))
  );

-- Correct answers are never available to a student query. Students load
-- questions only through the quiz-attempt Edge Function after it removes keys.
create policy questions_admin_all
  on public.questions for all to authenticated
  using ((select private.app_current_role()) = 'admin')
  with check ((select private.app_current_role()) = 'admin');
create policy questions_teacher_manage_own
  on public.questions for all to authenticated
  using (
    (select private.app_current_role()) = 'teacher'
    and exists (
      select 1 from public.quizzes as quiz
      where quiz.id = questions.quiz_id
        and quiz.teacher_id = (select auth.uid())
    )
  )
  with check (
    (select private.app_current_role()) = 'teacher'
    and exists (
      select 1 from public.quizzes as quiz
      where quiz.id = questions.quiz_id
        and quiz.teacher_id = (select auth.uid())
    )
  );

create policy grades_student_read_own
  on public.grades for select to authenticated
  using (
    (select private.app_current_role()) = 'student'
    and student_id = (select auth.uid())
  );
create policy grades_teacher_read_own_quiz_results
  on public.grades for select to authenticated
  using (
    (select private.app_current_role()) = 'teacher'
    and exists (
      select 1 from public.quizzes as quiz
      where quiz.id = grades.quiz_id
        and quiz.teacher_id = (select auth.uid())
    )
  );
create policy grades_admin_read_all
  on public.grades for select to authenticated
  using ((select private.app_current_role()) = 'admin');

create policy quiz_attempts_student_read_own
  on public.quiz_attempts for select to authenticated
  using (
    (select private.app_current_role()) = 'student'
    and student_id = (select auth.uid())
  );
create policy quiz_attempts_teacher_read_own_quiz
  on public.quiz_attempts for select to authenticated
  using (
    (select private.app_current_role()) = 'teacher'
    and exists (
      select 1 from public.quizzes as quiz
      where quiz.id = quiz_attempts.quiz_id
        and quiz.teacher_id = (select auth.uid())
    )
  );
create policy quiz_attempts_admin_read_all
  on public.quiz_attempts for select to authenticated
  using ((select private.app_current_role()) = 'admin');

create policy answers_student_read_own
  on public.answers for select to authenticated
  using (
    (select private.app_current_role()) = 'student'
    and exists (
      select 1 from public.quiz_attempts as attempt
      where attempt.id = answers.attempt_id
        and attempt.student_id = (select auth.uid())
    )
  );
create policy answers_teacher_read_own_quiz
  on public.answers for select to authenticated
  using (
    (select private.app_current_role()) = 'teacher'
    and exists (
      select 1
      from public.quiz_attempts as attempt
      join public.quizzes as quiz on quiz.id = attempt.quiz_id
      where attempt.id = answers.attempt_id
        and quiz.teacher_id = (select auth.uid())
    )
  );
create policy answers_admin_read_all
  on public.answers for select to authenticated
  using ((select private.app_current_role()) = 'admin');

create policy audit_logs_read_activity
  on public.audit_logs for select to authenticated
  using (
    (select private.app_current_role()) in ('admin', 'teacher')
    or performed_by = (select auth.uid())
    or target_user = (select auth.uid())
  );
create policy audit_logs_insert_as_self
  on public.audit_logs for insert to authenticated
  with check (performed_by = (select auth.uid()));

create policy suspicious_activities_student_insert_own
  on public.suspicious_activities for insert to authenticated
  with check (
    (select private.app_current_role()) = 'student'
    and student_id = (select auth.uid())
  );
create policy suspicious_activities_teacher_read_same_school
  on public.suspicious_activities for select to authenticated
  using (
    (select private.app_current_role()) = 'teacher'
    and exists (
      select 1 from public.users as student
      where student.id = suspicious_activities.student_id
        and student.school_id = (select private.app_current_school_id())
    )
  );
create policy suspicious_activities_admin_read
  on public.suspicious_activities for select to authenticated
  using ((select private.app_current_role()) = 'admin');

create policy password_reset_requests_student_create_own
  on public.password_reset_requests for insert to authenticated
  with check (
    (select private.app_current_role()) = 'student'
    and student_id = (select auth.uid())
  );
create policy password_reset_requests_admin_read
  on public.password_reset_requests for select to authenticated
  using ((select private.app_current_role()) = 'admin');
create policy password_reset_requests_teacher_read_same_school
  on public.password_reset_requests for select to authenticated
  using (
    (select private.app_current_role()) = 'teacher'
    and exists (
      select 1 from public.users as student
      where student.id = password_reset_requests.student_id
        and student.school_id = (select private.app_current_school_id())
    )
  );

drop policy if exists profile_photos_public_read on storage.objects;
create policy profile_photos_public_read
  on storage.objects for select to public
  using (bucket_id = 'profile-photos');

drop policy if exists profile_photos_upload_own on storage.objects;
create policy profile_photos_upload_own
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists profile_photos_update_own on storage.objects;
create policy profile_photos_update_own
  on storage.objects for update to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists profile_photos_delete_own on storage.objects;
create policy profile_photos_delete_own
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- ==============================================================================
-- QUIZ APP COMPREHENSIVE ADDITIONS
-- ==============================================================================

alter table public.users
  add column if not exists requested_grade text,
  add column if not exists requested_class text,
  add column if not exists requested_subject text,
  add column if not exists is_active boolean not null default true,
  add column if not exists must_change_password boolean not null default false,
  add column if not exists approval_status text not null default 'approved';

-- Set WondeAdmin@Admin.edu for admin
update public.users
set username = 'WondeAdmin@Admin.edu',
    role = 'admin',
    requested_role = 'admin',
    approval_status = 'approved',
    is_active = true
where lower(email) = 'wondedev369@gmail.com'
   or lower(username) in ('wondedev@admin.edu', 'wondevadmin@admin.edu', 'wondeadmin@admin.edu');

-- Username to Email Resolver for Login
create or replace function public.get_email_by_username(p_username text)
returns text
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $$
declare
  target_email text;
  clean_input text := lower(btrim(p_username));
  alt_input text;
begin
  select email into target_email
  from public.users
  where lower(username) = clean_input
    and is_active = true
  limit 1;

  if target_email is not null then
    return target_email;
  end if;

  if clean_input in ('wondeadmin@admin.edu', 'wondedev@admin.edu', 'wondeadmin', 'wondedev') then
    select email into target_email
    from public.users
    where role = 'admin' and is_active = true
    limit 1;
    return coalesce(target_email, 'wondedev369@gmail.com');
  end if;

  if clean_input like '%@students.edu' then
    alt_input := replace(clean_input, '@students.edu', '@student.edu');
    select email into target_email
    from public.users
    where lower(username) = alt_input and is_active = true
    limit 1;
    if target_email is not null then return target_email; end if;
  elsif clean_input like '%@student.edu' then
    alt_input := replace(clean_input, '@student.edu', '@students.edu');
    select email into target_email
    from public.users
    where lower(username) = alt_input and is_active = true
    limit 1;
    if target_email is not null then return target_email; end if;
  end if;

  return null;
end;
$$;

grant execute on function public.get_email_by_username(text) to anon, authenticated;

-- Quizzes & Questions visibility
grant select on public.quizzes to authenticated;
grant select on public.questions to authenticated;

alter table public.quizzes
  add column if not exists target_grade text,
  add column if not exists target_section text;

drop policy if exists quizzes_students_read_published on public.quizzes;
drop policy if exists quizzes_students_read_published_same_school on public.quizzes;
drop policy if exists quizzes_students_read_targeted on public.quizzes;
create policy quizzes_students_read_targeted
  on public.quizzes for select to authenticated
  using (
    (select private.app_current_role()) in ('admin', 'teacher')
    or (
      is_published = true
      and (
        exists (
          select 1 from public.student_sections ss
          where ss.student_id = auth.uid()
            and ss.section_id = quizzes.section_id
        )
        or exists (
          select 1 from public.student_sections ss
          join public.sections s_student on s_student.id = ss.section_id
          join public.sections s_quiz on s_quiz.id = quizzes.section_id
          where ss.student_id = auth.uid()
            and s_quiz.grade_id = s_student.grade_id
            and lower(s_quiz.name) = lower(s_student.name)
        )
        or exists (
          select 1 from public.users u
          where u.id = auth.uid()
            and (
              (quizzes.target_grade is not null and lower(u.requested_grade) = lower(quizzes.target_grade)
               and (quizzes.target_section is null or lower(u.requested_class) = lower(quizzes.target_section)))
              or (quizzes.section_id is null and quizzes.target_grade is null)
            )
        )
        or (quizzes.section_id is null and quizzes.target_grade is null)
      )
    )
  );

drop policy if exists questions_student_read_for_quiz on public.questions;
drop policy if exists questions_all_read on public.questions;
create policy questions_all_read
  on public.questions for select to authenticated
  using (true);

-- User Deletion RPC for Admin and Teachers
create or replace function public.delete_user_account(user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
declare
  caller_id uuid := auth.uid();
  caller_role text;
  caller_school uuid;
  target_user record;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into caller_role from private.app_current_role();
  if caller_role is null or caller_role not in ('admin', 'teacher') then
    raise exception 'Permission denied: only administrators and teachers can delete accounts' using errcode = '42501';
  end if;

  select * into caller_school from private.app_current_school_id();

  select id, role, school_id, full_name, username into target_user
  from public.users
  where id = user_id;

  if target_user.id is null then
    return jsonb_build_object('success', true, 'message', 'Account already deleted');
  end if;

  if caller_id = user_id then
    raise exception 'You cannot delete your own account' using errcode = '23514';
  end if;

  if caller_role = 'teacher' then
    if target_user.role <> 'student' then
      raise exception 'Teachers can only delete student accounts' using errcode = '42501';
    end if;
    if caller_school is not null and target_user.school_id is not null and target_user.school_id <> caller_school then
      raise exception 'Teachers can only delete students from their own school' using errcode = '42501';
    end if;
  end if;

  delete from public.student_sections where student_id = user_id;
  delete from public.teacher_courses where teacher_id = user_id;
  delete from public.courses where teacher_id = user_id;
  delete from public.grades where student_id = user_id;
  delete from public.users where id = user_id;
  delete from auth.users where id = user_id;

  return jsonb_build_object('success', true, 'id', user_id);
end;
$$;

grant execute on function public.delete_user_account(uuid) to authenticated;

-- Quiz Attempt RPC
create or replace function public.get_quiz_attempt_data(p_quiz_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $$
declare
  quiz_record record;
  questions_json jsonb;
begin
  select * into quiz_record
  from public.quizzes
  where id = p_quiz_id;

  if quiz_record.id is null then
    raise exception 'Quiz not found';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', q.id,
      'quiz_id', q.quiz_id,
      'text', q.text,
      'type', q.type,
      'options', q.options,
      'points', q.points,
      'order', q."order",
      'correct_answer', null,
      'explanation', null
    ) order by q."order" asc
  ), '[]'::jsonb) into questions_json
  from public.questions q
  where q.quiz_id = p_quiz_id;

  return jsonb_build_object(
    'quiz', to_jsonb(quiz_record),
    'questions', questions_json
  );
end;
$$;

grant execute on function public.get_quiz_attempt_data(uuid) to authenticated;

commit;
