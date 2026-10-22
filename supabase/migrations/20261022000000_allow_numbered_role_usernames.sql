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

  -- Enforces CapitalizedNamePart(CapitalizedFatherName)+[Digits]@(Teacher|Student|Students).edu
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
      from public.school_grades
      where school_id = school_id_value
        and name = requested_grade_value
    ) then
      raise exception 'Choose a grade offered by your school';
    end if;
    if not exists (
      select 1
      from public.sections
      where school_id = school_id_value
        and name = requested_class_value
    ) then
      raise exception 'Choose an existing section for your school';
    end if;
  end if;

  insert into public.users (
    id, email, username, full_name, role, school_id,
    must_change_password, requested_role, approval_status,
    requested_grade, requested_class, requested_subject, created_at
  ) values (
    new.id, lower(new.email), username_value, full_name_value, 'student',
    school_id_value, false, requested_role,
    case when requested_role = 'student' then 'approved' else 'pending' end,
    requested_grade_value, requested_class_value, requested_subject_value,
    now()
  );

  return new;
end;
$$;

commit;

