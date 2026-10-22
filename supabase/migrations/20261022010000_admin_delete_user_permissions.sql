begin;

-- 1. Grant delete permissions on public.users to authenticated users (controlled by RLS)
grant delete on public.users to authenticated;

-- 2. Create RLS delete policy allowing administrators to delete accounts
--    and teachers to delete student accounts belonging to their school
drop policy if exists users_delete_authorized on public.users;
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

-- 3. Dedicated security definer RPC function to permanently delete a user from
--    both public.users and auth.users (including cascades on enrollment and courses)
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
    -- Already deleted or not found
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

  -- Remove relationships and course assignments
  delete from public.student_sections where student_id = user_id;
  delete from public.teacher_courses where teacher_id = user_id;
  delete from public.courses where teacher_id = user_id;
  delete from public.grades where student_id = user_id;

  -- Delete public profile
  delete from public.users where id = user_id;

  -- Delete auth credentials so user cannot sign in anymore
  delete from auth.users where id = user_id;

  return jsonb_build_object('success', true, 'id', user_id);
end;
$$;

grant execute on function public.delete_user_account(uuid) to authenticated;

-- 4. Ensure teacher request columns exist on public.users (prevents Postgres error 42703)
alter table public.users
  add column if not exists requested_grade text,
  add column if not exists requested_class text,
  add column if not exists requested_subject text;

-- 5. RPC function to resolve email given institutional username for login
create or replace function public.get_email_by_username(p_username text)
returns text
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $$
declare
  target_email text;
begin
  select email into target_email
  from public.users
  where lower(username) = lower(btrim(p_username))
    and is_active = true
  limit 1;

  return target_email;
end;
$$;

grant execute on function public.get_email_by_username(text) to anon, authenticated;

-- 6. Grant select on questions to authenticated and allow students to load quiz questions
grant select on public.questions to authenticated;

drop policy if exists questions_student_read_for_quiz on public.questions;
create policy questions_student_read_for_quiz
  on public.questions for select to authenticated
  using (
    (select private.app_current_role()) in ('student', 'teacher', 'admin')
  );

-- 7. RPC function to safely load quiz attempt data with scrubbed answers for students
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

