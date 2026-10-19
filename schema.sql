-- Quiz App Supabase schema.
-- Safe to re-run. Existing school-grade tables are retained as school_grades.
-- Run this file before rls_policies.sql.

begin;

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
) values (
  'profile-photos', 'profile-photos', true, 5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.schools (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  address text,
  contact_email text,
  created_at timestamptz not null default now()
);
alter table public.schools
  add column if not exists address text,
  add column if not exists contact_email text,
  add column if not exists created_at timestamptz not null default now();

-- The original starter schema used public.grades for school grade levels.
-- The Flutter app uses public.grades for quiz results, so preserve old data
-- under an unambiguous name before creating the quiz-results table.
do $$
begin
  if to_regclass('public.grades') is not null
     and exists (
       select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'grades'
         and column_name = 'school_id'
     )
     and not exists (
       select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'grades'
         and column_name = 'student_id'
     ) then
    if to_regclass('public.school_grades') is not null then
      raise exception
        'Both legacy public.grades and public.school_grades exist. Back up and merge the school grade-level data before rerunning schema.sql.';
    end if;
    alter table public.grades rename to school_grades;
  end if;
end;
$$;

create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  username text not null,
  role text not null default 'student'
    check (role in ('admin', 'teacher', 'student')),
  school_id uuid references public.schools(id) on delete set null,
  full_name text not null,
  avatar_url text,
  must_change_password boolean not null default false,
  requested_role text
    check (requested_role is null or requested_role in ('admin', 'teacher', 'student')),
  approval_status text not null default 'approved'
    check (approval_status in ('pending', 'approved', 'rejected')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  last_login timestamptz
);

-- Add app fields to a previously-created starter users table without removing
-- existing user or course data.
alter table public.users
  add column if not exists email text,
  add column if not exists school_id uuid,
  add column if not exists avatar_url text,
  add column if not exists must_change_password boolean not null default false,
  add column if not exists requested_role text,
  add column if not exists approval_status text not null default 'approved',
  add column if not exists is_active boolean not null default true,
  add column if not exists last_login timestamptz,
  alter column id drop default;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'users'
      and column_name = 'password_hash'
  ) then
    alter table public.users alter column password_hash drop not null;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.users'::regclass
      and conname = 'users_school_id_fkey'
  ) then
    alter table public.users
      add constraint users_school_id_fkey
      foreign key (school_id) references public.schools(id) on delete set null;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.users'::regclass
      and conname = 'users_requested_role_check'
  ) then
    alter table public.users add constraint users_requested_role_check
      check (requested_role is null or requested_role in ('admin', 'teacher', 'student'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.users'::regclass
      and conname = 'users_approval_status_check'
  ) then
    alter table public.users add constraint users_approval_status_check
      check (approval_status in ('pending', 'approved', 'rejected'));
  end if;
end;
$$;

create unique index if not exists users_username_lower_unique
  on public.users (lower(username))
  where username is not null and username <> '';
create index if not exists users_school_role_idx
  on public.users (school_id, role);

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'users'
      and column_name = 'phone_email'
  ) then
    execute $sql$
      update public.users
      set email = lower(btrim(phone_email))
      where email is null
        and phone_email ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    $sql$;
  end if;
end;
$$;

create table if not exists public.school_grades (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  name text not null,
  unique (school_id, name)
);

create table if not exists public.sections (
  id uuid primary key default gen_random_uuid(),
  school_id uuid references public.schools(id) on delete cascade,
  grade_id uuid references public.school_grades(id) on delete set null,
  name text not null,
  grade text,
  academic_year text,
  created_at timestamptz not null default now()
);

create table if not exists public.courses (
  id uuid primary key default gen_random_uuid(),
  school_id uuid references public.schools(id) on delete cascade,
  section_id uuid references public.sections(id) on delete set null,
  teacher_id uuid references public.users(id) on delete set null,
  name text not null,
  description text,
  subject text,
  created_at timestamptz not null default now()
);

alter table public.sections
  add column if not exists school_id uuid references public.schools(id) on delete cascade,
  add column if not exists grade_id uuid references public.school_grades(id) on delete set null,
  add column if not exists grade text,
  add column if not exists academic_year text,
  add column if not exists created_at timestamptz not null default now();

alter table public.courses
  add column if not exists school_id uuid references public.schools(id) on delete cascade,
  add column if not exists section_id uuid references public.sections(id) on delete set null,
  add column if not exists teacher_id uuid references public.users(id) on delete set null,
  add column if not exists description text,
  add column if not exists subject text,
  add column if not exists created_at timestamptz not null default now();

create table if not exists public.teacher_courses (
  teacher_id uuid not null references public.users(id) on delete cascade,
  course_id uuid not null references public.courses(id) on delete cascade,
  assigned_by uuid references public.users(id) on delete set null,
  assigned_at timestamptz not null default now(),
  primary key (teacher_id, course_id)
);

create table if not exists public.student_sections (
  student_id uuid not null references public.users(id) on delete cascade,
  section_id uuid not null references public.sections(id) on delete cascade,
  primary key (student_id, section_id)
);

create table if not exists public.quizzes (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid references public.users(id) on delete cascade,
  course_id uuid references public.courses(id) on delete set null,
  section_id uuid references public.sections(id) on delete set null,
  title text not null,
  description text,
  time_limit_minutes integer,
  passing_score_percent integer not null default 60
    check (passing_score_percent between 0 and 100),
  total_points integer not null default 0 check (total_points >= 0),
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

alter table public.quizzes
  add column if not exists teacher_id uuid references public.users(id) on delete cascade,
  add column if not exists section_id uuid references public.sections(id) on delete set null,
  add column if not exists description text,
  add column if not exists time_limit_minutes integer,
  add column if not exists passing_score_percent integer not null default 60,
  add column if not exists total_points integer not null default 0,
  add column if not exists is_published boolean not null default false,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'quizzes'
      and column_name = 'created_by'
  ) then
    execute 'update public.quizzes set teacher_id = created_by where teacher_id is null';
    alter table public.quizzes alter column created_by drop not null;
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'quizzes'
      and column_name = 'course_id'
  ) then
    alter table public.quizzes alter column course_id drop not null;
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'quizzes'
      and column_name = 'time_per_question_seconds'
  ) then
    execute $sql$
      update public.quizzes
      set time_limit_minutes = greatest(1, ceil(time_per_question_seconds / 60.0)::integer)
      where time_limit_minutes is null and time_per_question_seconds > 0
    $sql$;
  end if;
end;
$$;

do $$
declare
  options_data_type text;
begin
  select data_type into options_data_type
  from information_schema.columns
  where table_schema = 'public' and table_name = 'questions'
    and column_name = 'options';

  if options_data_type = 'json' then
    alter table public.questions
      alter column options type jsonb using options::jsonb;
  elsif options_data_type = 'text' then
    alter table public.questions
      alter column options type jsonb
      using case
        when options is null or btrim(options) = '' then '[]'::jsonb
        else options::jsonb
      end;
  elsif options_data_type is not null and options_data_type <> 'jsonb' then
    raise exception 'Unsupported public.questions.options type: %', options_data_type;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'questions'
      and column_name = 'options'
  ) then
    execute $sql$
      update public.questions as question
      set options = (
        select coalesce(
          jsonb_agg(
            jsonb_build_object(
              'id', coalesce(option.value ->> 'id', option.value ->> 'index'),
              'text', coalesce(option.value ->> 'text', ''),
              'is_correct',
                coalesce(
                  (option.value ->> 'is_correct')::boolean,
                  lower(coalesce(option.value ->> 'index', '')) =
                    lower(coalesce(question.correct_answer, ''))
                )
            )
          ),
          '[]'::jsonb
        )
        from jsonb_array_elements(
          case
            when jsonb_typeof(question.options) = 'array' then question.options
            else '[]'::jsonb
          end
        ) as option(value)
      )
      where jsonb_typeof(question.options) = 'array'
    $sql$;
  end if;
end;
$$;

create index if not exists quizzes_teacher_created_idx
  on public.quizzes (teacher_id, created_at desc);
create index if not exists quizzes_published_idx
  on public.quizzes (is_published, created_at desc);

create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid references public.quizzes(id) on delete cascade,
  text text not null,
  type text not null default 'multiple_choice'
    check (type in ('multiple_choice', 'true_false', 'short_answer')),
  options jsonb not null default '[]'::jsonb,
  correct_answer text,
  points integer not null default 1 check (points > 0),
  "order" integer not null default 0,
  explanation text,
  created_at timestamptz not null default now()
);

alter table public.questions
  add column if not exists quiz_id uuid references public.quizzes(id) on delete cascade,
  add column if not exists text text,
  add column if not exists type text not null default 'multiple_choice',
  add column if not exists options jsonb not null default '[]'::jsonb,
  add column if not exists correct_answer text,
  add column if not exists points integer not null default 1,
  add column if not exists "order" integer not null default 0,
  add column if not exists explanation text,
  add column if not exists created_at timestamptz not null default now();

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'questions'
      and column_name = 'question_text'
  ) then
    execute 'update public.questions set text = question_text where text is null';
    alter table public.questions alter column question_text drop not null;
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'questions'
      and column_name = 'question_type'
  ) then
    execute $sql$
      update public.questions
      set type = case
        when question_type in ('mcq', 'multiple_choice') then 'multiple_choice'
        when question_type = 'true_false' then 'true_false'
        else 'short_answer'
      end
      where type = 'multiple_choice'
    $sql$;
    alter table public.questions alter column question_type drop not null;
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'questions'
      and column_name = 'course_id'
  ) then
    alter table public.questions alter column course_id drop not null;
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'questions'
      and column_name = 'created_by'
  ) then
    alter table public.questions alter column created_by drop not null;
  end if;
end;
$$;

-- Preserve existing question-bank assignments from the old join table. A
-- question linked to more than one quiz is copied for each additional quiz.
do $$
declare
  link_row record;
  question_row public.questions%rowtype;
begin
  if to_regclass('public.quiz_questions') is null then
    return;
  end if;
  for link_row in
    execute 'select quiz_id, question_id, position from public.quiz_questions order by quiz_id, position'
  loop
    select * into question_row
    from public.questions
    where id = link_row.question_id;
    if not found or question_row.quiz_id = link_row.quiz_id then
      continue;
    end if;
    if question_row.quiz_id is null then
      update public.questions
      set quiz_id = link_row.quiz_id, "order" = link_row.position
      where id = link_row.question_id;
    else
      insert into public.questions (
        quiz_id, text, type, options, correct_answer, points, "order", explanation
      ) values (
        link_row.quiz_id, question_row.text, question_row.type,
        question_row.options, question_row.correct_answer, question_row.points,
        link_row.position, question_row.explanation
      );
    end if;
  end loop;
end;
$$;

create index if not exists questions_quiz_order_idx
  on public.questions (quiz_id, "order");

create table if not exists public.grades (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.users(id) on delete cascade,
  quiz_id uuid not null references public.quizzes(id) on delete cascade,
  course_id uuid references public.courses(id) on delete set null,
  score integer not null default 0,
  total_points integer not null default 0,
  incorrect_answers integer check (incorrect_answers >= 0),
  percentage integer not null default 0,
  passed boolean not null default false,
  submitted_at timestamptz not null default now(),
  graded_at timestamptz,
  unique (student_id, quiz_id)
);

alter table public.grades
  add column if not exists student_id uuid references public.users(id) on delete cascade,
  add column if not exists quiz_id uuid references public.quizzes(id) on delete cascade,
  add column if not exists course_id uuid references public.courses(id) on delete set null,
  add column if not exists score integer not null default 0,
  add column if not exists total_points integer not null default 0,
  add column if not exists incorrect_answers integer
    check (incorrect_answers >= 0),
  add column if not exists percentage integer not null default 0,
  add column if not exists passed boolean not null default false,
  add column if not exists submitted_at timestamptz not null default now(),
  add column if not exists graded_at timestamptz;

create unique index if not exists grades_one_attempt_per_quiz
  on public.grades (student_id, quiz_id)
  where student_id is not null and quiz_id is not null;
create index if not exists grades_student_submitted_idx
  on public.grades (student_id, submitted_at desc);
create index if not exists grades_quiz_submitted_idx
  on public.grades (quiz_id, submitted_at desc);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  action text not null,
  performed_by uuid references public.users(id) on delete set null,
  target_user uuid references public.users(id) on delete set null,
  details jsonb,
  ip_address text,
  user_agent text,
  created_at timestamptz not null default now()
);

alter table public.audit_logs
  add column if not exists ip_address text,
  add column if not exists user_agent text;

create table if not exists public.quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.quizzes(id) on delete cascade,
  student_id uuid not null references public.users(id) on delete cascade,
  started_at timestamptz not null default now(),
  submitted_at timestamptz,
  score numeric,
  auto_submitted boolean not null default false,
  unique (quiz_id, student_id)
);

create table if not exists public.answers (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.quiz_attempts(id) on delete cascade,
  question_id uuid not null references public.questions(id),
  answer_text text,
  is_correct boolean,
  answered_at timestamptz not null default now()
);

create table if not exists public.suspicious_activities (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid references public.quiz_attempts(id) on delete cascade,
  student_id uuid not null references public.users(id) on delete cascade,
  activity text not null,
  details jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.password_reset_requests (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.users(id) on delete cascade,
  teacher_id uuid not null references public.users(id),
  requested_at timestamptz not null default now(),
  resolved_at timestamptz
);

insert into public.schools (id, name)
values ('00000000-0000-4000-8000-000000000001', 'Main School')
on conflict (id) do nothing;

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
  expected_suffix text;
  username_value text := btrim(coalesce(new.raw_user_meta_data ->> 'username', ''));
  full_name_value text := btrim(coalesce(new.raw_user_meta_data ->> 'full_name', ''));
begin
  if requested_role not in ('student', 'teacher', 'admin') then
    raise exception 'Unsupported account role request';
  end if;
  expected_suffix := case requested_role
    when 'admin' then 'A'
    when 'teacher' then 'T'
    else 'S'
  end;
  if username_value !~ (
    '^[A-Z][a-z]{1,49}@' || expected_suffix || '\.edu$'
  ) then
    raise exception 'Username must be Firstlastname@%.edu', expected_suffix;
  end if;
  if length(full_name_value) < 3 or length(full_name_value) > 100
     or array_length(regexp_split_to_array(full_name_value, '[[:space:]]+'), 1) < 2 then
    raise exception 'Enter your first and last name';
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

revoke all on function public.handle_quiz_app_user_signup() from public, anon, authenticated;

drop trigger if exists z_quiz_app_secure_profile on auth.users;
create trigger z_quiz_app_secure_profile
  after insert on auth.users
  for each row execute function public.handle_quiz_app_user_signup();

-- Promote only this exact Supabase Auth user. This never changes their
-- password or promotes an account with a different email.
do $$
declare
  affected_count integer;
begin
  insert into public.users (
    id, email, username, role, full_name, school_id,
    must_change_password, requested_role, approval_status, is_active, created_at
  )
  select
    auth_user.id,
    lower(auth_user.email),
    'Wondev@Admin.edu',
    'admin',
    coalesce(
      nullif(auth_user.raw_user_meta_data ->> 'full_name', ''),
      'Wondev Admin'
    ),
    null,
    false,
    'admin',
    'approved',
    true,
    now()
  from auth.users as auth_user
  where auth_user.id = 'bf883616-97a1-4797-8455-1d8df34917fa'::uuid
    and lower(auth_user.email) = 'wondedev369@gmail.com'
  on conflict (id) do update
    set email = excluded.email,
        username = excluded.username,
        role = 'admin',
        requested_role = 'admin',
        approval_status = 'approved',
        is_active = true;
  get diagnostics affected_count = row_count;
  if affected_count = 0 then
    raise notice 'Admin not promoted: no Supabase Auth user matched the exact UID and email.';
  end if;
end;
$$;

commit;
