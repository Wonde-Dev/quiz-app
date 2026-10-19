begin;

alter table public.grades
  add column if not exists incorrect_answers integer
  check (incorrect_answers >= 0);

drop policy if exists courses_read_same_school on public.courses;
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

drop policy if exists courses_teacher_manage_own on public.courses;
drop policy if exists courses_teacher_read_assigned on public.courses;

drop policy if exists quizzes_teacher_manage_own on public.quizzes;
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

commit;
