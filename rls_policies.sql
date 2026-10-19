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

commit;
