begin;

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

commit;
