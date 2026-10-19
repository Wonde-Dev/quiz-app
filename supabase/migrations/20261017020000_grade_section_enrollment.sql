begin;

insert into public.school_grades (school_id, name)
select school.id, 'Grade ' || grade.level
from public.schools as school
cross join generate_series(9, 12) as grade(level)
on conflict (school_id, name) do nothing;

insert into public.sections (school_id, grade_id, name, grade)
select school_grade.school_id, school_grade.id, section.name, school_grade.name
from public.school_grades as school_grade
cross join (values ('A'), ('B'), ('C')) as section(name)
where school_grade.name in ('Grade 9', 'Grade 10', 'Grade 11', 'Grade 12')
on conflict do nothing;

create unique index if not exists sections_school_grade_name_unique
  on public.sections (school_id, grade_id, lower(name))
  where grade_id is not null;

create or replace function public.handle_quiz_app_user_signup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_role text := coalesce(new.raw_user_meta_data ->> 'requested_role', 'student');
  school_id_value uuid;
  section_id_value uuid;
  username_value text := btrim(coalesce(new.raw_user_meta_data ->> 'username', ''));
  full_name_value text := btrim(coalesce(new.raw_user_meta_data ->> 'full_name', ''));
begin
  if requested_role not in ('student', 'teacher', 'admin') then
    raise exception 'Unsupported account role request';
  end if;
  if username_value !~ '^[A-Z][a-zA-Z0-9]{0,49}@(Admin|teacher|Student)\.edu$' then
    raise exception 'Use a capitalized first name followed by the username suffix for the requested role';
  end if;
  if (requested_role = 'student' and username_value !~ '@Student\.edu$')
     or (requested_role = 'teacher' and username_value !~ '@teacher\.edu$')
     or (requested_role = 'admin' and username_value !~ '@Admin\.edu$') then
    raise exception 'Username suffix does not match the requested role';
  end if;
  if length(full_name_value) < 2 or length(full_name_value) > 100 then
    raise exception 'Enter a valid full name';
  end if;

  if requested_role <> 'admin' then
    school_id_value := nullif(new.raw_user_meta_data ->> 'school_id', '')::uuid;
    if school_id_value is null or not exists (
      select 1 from public.schools where id = school_id_value
    ) then
      raise exception 'Choose a valid school';
    end if;
  end if;

  if requested_role = 'student' then
    section_id_value := nullif(new.raw_user_meta_data ->> 'section_id', '')::uuid;
    if section_id_value is null or not exists (
      select 1 from public.sections
      where id = section_id_value and school_id = school_id_value
    ) then
      raise exception 'Choose a valid grade and section';
    end if;
  end if;

  insert into public.users (
    id, email, username, full_name, role, school_id,
    must_change_password, requested_role, approval_status, created_at
  ) values (
    new.id, lower(new.email), username_value, full_name_value, 'student',
    school_id_value, false, requested_role,
    case when requested_role = 'student' then 'approved' else 'pending' end,
    now()
  )
  on conflict (id) do nothing;

  if requested_role = 'student' then
    insert into public.student_sections (student_id, section_id)
    values (new.id, section_id_value)
    on conflict do nothing;
  end if;
  return new;
end;
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

create or replace function private.app_student_can_access_quiz_section(
  quiz_owner_id uuid,
  quiz_section_id uuid
)
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
        (
          quiz_section_id is null
          and (
            quiz_owner.role = 'admin'
            or (
              quiz_owner.role = 'teacher'
              and quiz_owner.school_id = student.school_id
            )
          )
        )
        or exists (
          select 1
          from public.student_sections as enrollment
          where enrollment.student_id = student.id
            and enrollment.section_id = quiz_section_id
        )
      )
  )
$$;

revoke all on function private.app_student_can_access_quiz_section(uuid, uuid)
  from public, anon, authenticated;
grant execute on function private.app_student_can_access_quiz_section(uuid, uuid)
  to authenticated;

drop policy if exists quizzes_students_read_published_same_school
  on public.quizzes;
create policy quizzes_students_read_published_same_school
  on public.quizzes for select to authenticated
  using (
    (select private.app_current_role()) = 'student'
    and is_published
    and (
      select private.app_student_can_access_quiz_section(teacher_id, section_id)
    )
  );

drop policy if exists quizzes_teacher_manage_own on public.quizzes;
create policy quizzes_teacher_manage_own
  on public.quizzes for all to authenticated
  using (
    (select private.app_current_role()) = 'teacher'
    and teacher_id = (select auth.uid())
  )
  with check (
    (select private.app_current_role()) = 'teacher'
    and teacher_id = (select auth.uid())
    and (
      section_id is null
      or exists (
        select 1 from public.sections as target_section
        where target_section.id = quizzes.section_id
          and target_section.school_id = (select private.app_current_school_id())
      )
    )
  );

commit;
