-- ==============================================================================
-- QUIZ APP COMPREHENSIVE FIX MIGRATION
-- 1. Updates Admin username to WondeAdmin@Admin.edu
-- 2. Creates/updates get_email_by_username RPC for instant institutional username sign-in
-- 3. Configures Quizzes and Questions visibility so Teachers & Students can see and take exams
-- 4. Ensures requested_grade, requested_class, requested_subject columns exist
-- 5. Updates signup trigger for @Teacher.edu and @Students.edu / @Student.edu formats
-- ==============================================================================

begin;

-- 1. Ensure columns exist on public.users and public.quizzes
alter table public.users
  add column if not exists requested_grade text,
  add column if not exists requested_class text,
  add column if not exists requested_subject text,
  add column if not exists section_id uuid references public.sections(id) on delete set null,
  add column if not exists is_active boolean not null default true,
  add column if not exists must_change_password boolean not null default false,
  add column if not exists approval_status text not null default 'approved';

alter table public.quizzes
  add column if not exists target_grade text,
  add column if not exists target_section text;

-- 2. Update Admin username to WondeAdmin@Admin.edu
update public.users
set username = 'WondeAdmin@Admin.edu',
    role = 'admin',
    requested_role = 'admin',
    approval_status = 'approved',
    is_active = true
where lower(email) = 'wondedev369@gmail.com'
   or lower(username) in ('wondedev@admin.edu', 'wondevadmin@admin.edu', 'wondeadmin@admin.edu');

-- 3. Dedicated security definer RPC function to look up email by username
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
  -- Direct match
  select email into target_email
  from public.users
  where lower(username) = clean_input
    and is_active = true
  limit 1;

  if target_email is not null then
    return target_email;
  end if;

  -- Admin shortcut
  if clean_input in ('wondeadmin@admin.edu', 'wondedev@admin.edu', 'wondeadmin', 'wondedev') then
    select email into target_email
    from public.users
    where role = 'admin' and is_active = true
    limit 1;
    return coalesce(target_email, 'wondedev369@gmail.com');
  end if;

  -- Student / Students plural variation fallback
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

-- 4. Enable permissions and RLS for quizzes and questions
grant select on public.quizzes to authenticated;
grant select on public.questions to authenticated;

alter table public.quizzes enable row level security;
alter table public.questions enable row level security;

-- Quizzes: Students only read quizzes targeted to their grade/class or open school quizzes
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
        -- Enrolled in the quiz section
        exists (
          select 1 from public.student_sections ss
          where ss.student_id = auth.uid()
            and ss.section_id = quizzes.section_id
        )
        -- Matching section grade and name
        or exists (
          select 1 from public.student_sections ss
          join public.sections s_student on s_student.id = ss.section_id
          join public.sections s_quiz on s_quiz.id = quizzes.section_id
          where ss.student_id = auth.uid()
            and s_quiz.grade_id = s_student.grade_id
            and lower(s_quiz.name) = lower(s_student.name)
        )
        -- Matching student requested grade and class
        or exists (
          select 1 from public.users u
          where u.id = auth.uid()
            and (
              (quizzes.target_grade is not null and lower(u.requested_grade) = lower(quizzes.target_grade)
               and (quizzes.target_section is null or lower(u.requested_class) = lower(quizzes.target_section)))
              or (quizzes.section_id is null and quizzes.target_grade is null)
            )
        )
        -- Open quiz without section or grade restriction
        or (quizzes.section_id is null and quizzes.target_grade is null)
      )
    )
  );

-- Quizzes: Teachers manage own
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
  );

-- Quizzes: Admin manages all
drop policy if exists quizzes_admin_manage_all on public.quizzes;
create policy quizzes_admin_manage_all
  on public.quizzes for all to authenticated
  using ((select private.app_current_role()) = 'admin')
  with check ((select private.app_current_role()) = 'admin');

-- Questions: Read policy for all authenticated users
drop policy if exists questions_student_read_for_quiz on public.questions;
drop policy if exists questions_all_read on public.questions;
create policy questions_all_read
  on public.questions for select to authenticated
  using (true);

-- Questions: Teachers & Admins manage questions
drop policy if exists questions_teacher_manage_own on public.questions;
create policy questions_teacher_manage_own
  on public.questions for all to authenticated
  using (
    (select private.app_current_role()) = 'admin'
    or exists (
      select 1 from public.quizzes q
      where q.id = questions.quiz_id
        and q.teacher_id = (select auth.uid())
    )
  )
  with check (
    (select private.app_current_role()) = 'admin'
    or exists (
      select 1 from public.quizzes q
      where q.id = questions.quiz_id
        and q.teacher_id = (select auth.uid())
    )
  );

-- 5. RPC function to safely load quiz attempt data with scrubbed answers for students
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

-- 6. RPC function to permanently delete accounts (admin & teachers)
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

  -- Delete relations
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

-- 7. Update signup trigger with case-insensitive handling for Teacher and Student suffixes
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
  requested_grade_value text := nullif(
    btrim(coalesce(new.raw_user_meta_data ->> 'requested_grade', '')), ''
  );
  requested_class_value text := nullif(
    btrim(coalesce(new.raw_user_meta_data ->> 'requested_class', '')), ''
  );
  requested_subject_value text := nullif(
    btrim(coalesce(new.raw_user_meta_data ->> 'requested_subject', '')), ''
  );
  username_value text := btrim(coalesce(new.raw_user_meta_data ->> 'username', ''));
  full_name_value text := btrim(coalesce(new.raw_user_meta_data ->> 'full_name', ''));
begin
  if requested_role = 'admin' then
    raise exception 'Administrator accounts are invitation-only';
  elsif requested_role not in ('student', 'teacher') then
    raise exception 'Unsupported account role request';
  end if;

  -- Validates TitleCase first and father name with sequential numbers and domain
  if username_value !~ (
    '^[A-Z][a-z]*([A-Z][a-z]*)+[0-9]*@' ||
    case requested_role
      when 'admin' then 'Admin'
      when 'teacher' then 'Teacher'
      else 'Students?'
    end ||
    '\.edu$'
  ) then
    raise exception 'Username must be FirstnameLastname@%.edu',
      case requested_role
        when 'admin' then 'Admin'
        when 'teacher' then 'Teacher'
        else 'Students'
      end;
  end if;

  if length(full_name_value) < 3 or length(full_name_value) > 100
     or array_length(regexp_split_to_array(full_name_value, '[[:space:]]+'), 1) < 2 then
    raise exception 'Enter your first and last name';
  end if;

  if requested_role <> 'admin' then
    school_id_value := nullif(new.raw_user_meta_data ->> 'school_id', '')::uuid;
  end if;

  if requested_role = 'student' then
    section_id_value := nullif(new.raw_user_meta_data ->> 'section_id', '')::uuid;
  end if;

  insert into public.users (
    id, email, username, full_name, role, school_id,
    must_change_password, requested_role, approval_status,
    requested_grade, requested_class, requested_subject, created_at
  ) values (
    new.id, lower(new.email), username_value, full_name_value, 'student',
    school_id_value, false, requested_role,
    case when requested_role = 'student' then 'approved' else 'pending' end,
    requested_grade_value, requested_class_value, requested_subject_value, now()
  )
  on conflict (id) do update
    set email = excluded.email,
        username = excluded.username,
        full_name = excluded.full_name;

  if requested_role = 'student' and section_id_value is not null then
    insert into public.student_sections (student_id, section_id)
    values (new.id, section_id_value)
    on conflict do nothing;
  end if;

  return new;
end;
$$;

commit;

