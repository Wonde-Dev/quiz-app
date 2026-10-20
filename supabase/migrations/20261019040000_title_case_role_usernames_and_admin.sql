begin;

alter table public.users
  add column if not exists requested_grade text,
  add column if not exists requested_class text,
  add column if not exists requested_subject text;

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
  if username_value !~ (
    '^[A-Z][a-z]*([A-Z][a-z]*)+@' ||
    case requested_role
      when 'admin' then 'Admin'
      when 'teacher' then 'Teacher'
      else 'Student'
    end ||
    '\.edu$'
  ) then
    raise exception 'Username must be FirstnameLastname@%.edu',
      case requested_role
        when 'admin' then 'Admin'
        when 'teacher' then 'Teacher'
        else 'Student'
      end;
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

  if requested_role = 'teacher' then
    if requested_grade_value is null or requested_class_value is null then
      raise exception 'Choose a teaching grade and class';
    end if;
    if not exists (
      select 1
      from public.sections as s
      join public.school_grades as g on g.id = s.grade_id
      where s.school_id = school_id_value
        and s.name = requested_class_value
        and g.name = requested_grade_value
    ) then
      raise exception 'Choose a valid teaching grade and class';
    end if;
    if requested_subject_value is null then
      raise exception 'Enter the subject you teach';
    end if;
  end if;
  if requested_grade_value is not null and length(requested_grade_value) > 40 then
    raise exception 'Requested grade is too long';
  end if;
  if requested_class_value is not null and length(requested_class_value) > 40 then
    raise exception 'Requested class is too long';
  end if;
  if requested_subject_value is not null and length(requested_subject_value) > 80 then
    raise exception 'Requested subject is too long';
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
  on conflict (id) do nothing;

  if requested_role = 'student' then
    insert into public.student_sections (student_id, section_id)
    values (new.id, section_id_value)
    on conflict do nothing;
  end if;

  return new;
end;
$$;

do $$
declare
  auth_account auth.users%rowtype;
  admin_username constant text := 'WondeDev@Admin.edu';
begin
  select *
  into auth_account
  from auth.users
  where lower(email) = 'wondedev369@gmail.com'
  limit 1;

  if not found then
    raise notice
      'Admin account was not changed: no Supabase Auth user exists for wondedev369@gmail.com.';
    return;
  end if;

  if exists (
    select 1 from public.users
    where lower(username) = lower(admin_username)
      and id <> auth_account.id
  ) then
    raise exception
      'Cannot promote wondedev369@gmail.com: % is already used by another account.',
      admin_username;
  end if;

  insert into public.users (
    id, email, username, role, full_name, school_id,
    must_change_password, requested_role, approval_status, is_active,
    requested_grade, requested_class, requested_subject, created_at
  ) values (
    auth_account.id,
    lower(auth_account.email),
    admin_username,
    'admin',
    coalesce(
      nullif(auth_account.raw_user_meta_data ->> 'full_name', ''),
      'Wonde Dev'
    ),
    null,
    false,
    'admin',
    'approved',
    true,
    null,
    null,
    null,
    now()
  )
  on conflict (id) do update
    set email = excluded.email,
        username = excluded.username,
        role = 'admin',
        requested_role = 'admin',
        approval_status = 'approved',
        is_active = true;
end;
$$;

commit;
