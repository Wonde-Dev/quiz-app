-- Migration: 20261101010000_perfect_exam_grading_and_results_sync.sql
-- 1. Upgrade submit_student_quiz_attempt RPC:
--    - Enforces authentication
--    - Deletes prior grades for (student_id, quiz_id) to prevent duplicate records
--    - Accurately inserts into public.grades with incorrect_answers, total_points, score, percentage, passed, graded_at
--    - Upserts public.quiz_attempts with score, status='submitted', completed_at=now()
--    - Synchronizes public.answers breakdown (deletes previous attempt answers and re-inserts current answers)
-- 2. Ensure RLS policies and table permissions on grades, quiz_attempts, answers
-- 3. Notify PostgREST schema cache reload

begin;

create or replace function public.submit_student_quiz_attempt(
  p_quiz_id uuid,
  p_student_id uuid,
  p_score integer,
  p_total_points integer,
  p_percentage integer,
  p_passed boolean,
  p_answers jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
declare
  caller_id uuid := auth.uid();
  v_attempt_id uuid;
  ans_rec jsonb;
  v_incorrect integer;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  -- Caller can only submit for themselves unless caller is admin or director
  if caller_id <> p_student_id then
    if not exists (
      select 1 from public.users
      where id = caller_id and role in ('admin', 'director')
    ) then
      raise exception 'Cannot submit quiz attempt for another student' using errcode = '42501';
    end if;
  end if;

  v_incorrect := greatest(0, p_total_points - p_score);

  -- 1. Delete prior grade for this student and quiz to maintain clean single source of truth
  delete from public.grades
  where student_id = p_student_id and quiz_id = p_quiz_id;

  -- 2. Insert new grade record
  insert into public.grades (
    id,
    student_id,
    quiz_id,
    score,
    total_points,
    percentage,
    passed,
    incorrect_answers,
    submitted_at,
    graded_at
  ) values (
    gen_random_uuid(),
    p_student_id,
    p_quiz_id,
    p_score,
    p_total_points,
    p_percentage,
    p_passed,
    v_incorrect,
    now(),
    now()
  );

  -- 3. Upsert quiz attempt
  insert into public.quiz_attempts (
    quiz_id,
    student_id,
    score,
    percentage,
    status,
    submitted_at,
    completed_at
  ) values (
    p_quiz_id,
    p_student_id,
    p_score,
    p_percentage,
    'submitted',
    now(),
    now()
  )
  on conflict (quiz_id, student_id) do update set
    score = excluded.score,
    percentage = excluded.percentage,
    status = 'submitted',
    submitted_at = excluded.submitted_at,
    completed_at = now()
  returning id into v_attempt_id;

  -- 4. Insert question answers breakdown
  if v_attempt_id is not null and p_answers is not null and jsonb_array_length(p_answers) > 0 then
    delete from public.answers where attempt_id = v_attempt_id;
    for ans_rec in select * from jsonb_array_elements(p_answers) loop
      insert into public.answers (
        attempt_id,
        question_id,
        answer_text,
        is_correct
      ) values (
        v_attempt_id,
        (ans_rec->>'question_id')::uuid,
        ans_rec->>'answer_text',
        coalesce((ans_rec->>'is_correct')::boolean, false)
      );
    end loop;
  end if;

  return jsonb_build_object(
    'success', true,
    'attempt_id', v_attempt_id,
    'score', p_score,
    'total_points', p_total_points,
    'percentage', p_percentage,
    'passed', p_passed
  );
end;
$$;

grant execute on function public.submit_student_quiz_attempt(uuid, uuid, integer, integer, integer, boolean, jsonb) to authenticated, anon;

-- Ensure RLS on grades is enabled and allows students to view their own grades
alter table if exists public.grades enable row level security;

drop policy if exists "grades_student_select_own" on public.grades;
create policy "grades_student_select_own"
on public.grades for select to authenticated
using (
  student_id = auth.uid()
  or exists (
    select 1 from public.users
    where id = auth.uid() and role in ('admin', 'director', 'teacher')
  )
);

drop policy if exists "grades_student_insert_own" on public.grades;
create policy "grades_student_insert_own"
on public.grades for insert to authenticated
with check (
  student_id = auth.uid()
  or exists (
    select 1 from public.users
    where id = auth.uid() and role in ('admin', 'director')
  )
);

drop policy if exists "quiz_attempts_select_policy" on public.quiz_attempts;
create policy "quiz_attempts_select_policy"
on public.quiz_attempts for select to authenticated
using (
  student_id = auth.uid()
  or exists (
    select 1 from public.users
    where id = auth.uid() and role in ('admin', 'director', 'teacher')
  )
);

grant all on public.grades to authenticated;
grant all on public.quiz_attempts to authenticated;
grant all on public.answers to authenticated;

notify pgrst, 'reload schema';

commit;

