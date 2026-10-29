-- Migration: 20261028200000_admin_create_user_enhancements.sql
-- Description: Expand admin_create_user to support all user fields including phone, gender, grade, class, and attendance teacher designation.
-- Also provide a JSONB overload to handle flexible client calls without parameter signature mismatch.

drop function if exists public.admin_create_user(text, text, text, text, text, uuid, uuid, text, text, text);
drop function if exists public.admin_create_user(text, text, text, text, text, uuid, uuid, text, text, text, text, text, boolean, text, text);
drop function if exists public.admin_create_user(jsonb);

create or replace function public.admin_create_user(
  p_full_name text,
  p_username text,
  p_email text,
  p_password text,
  p_role text,
  p_school_id uuid default null,
  p_section_id uuid default null,
  p_subject text default null,
  p_phone_number text default null,
  p_gender text default null,
  p_grade text default null,
  p_class text default null,
  p_is_attendance_teacher boolean default false,
  p_attendance_grade text default null,
  p_attendance_class text default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'extensions', 'pg_temp'
as $$
declare
  caller_id uuid := auth.uid();
  caller record;
  new_user_id uuid := gen_random_uuid();
  encrypted_pw text;
  clean_email text := lower(trim(p_email));
  clean_uname text := trim(p_username);
  effective_school uuid;
  assigned_class_val text := p_class;
  assigned_grade_val text := p_grade;
  is_attendance boolean := coalesce(p_is_attendance_teacher, false);
  attendance_class_val text := p_attendance_class;
  attendance_grade_val text := p_attendance_grade;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select id, role, is_super_admin, school_id, is_attendance_teacher, attendance_grade, attendance_class
  into caller
  from public.users
  where id = caller_id;

  if caller.role not in ('admin', 'subadmin', 'teacher') and caller.is_super_admin is not true then
    raise exception 'Permission denied: Unauthorized to create user accounts' using errcode = '42501';
  end if;

  -- Subadmin cannot create super admins
  if caller.role = 'subadmin' and p_role in ('admin', 'super_admin') then
    raise exception 'Permission denied: Sub-admins cannot create administrator accounts' using errcode = '42501';
  end if;

  -- Teacher can only create students of their designated class
  if caller.role = 'teacher' then
    if p_role <> 'student' then
      raise exception 'Teachers can only register student accounts' using errcode = '42501';
    end if;
    if caller.is_attendance_teacher is true and caller.attendance_class is not null then
      assigned_class_val := caller.attendance_class;
      assigned_grade_val := caller.attendance_grade;
    end if;
  end if;

  effective_school := coalesce(p_school_id, caller.school_id);
  encrypted_pw := extensions.crypt(p_password, extensions.gen_salt('bf'));

  -- Insert into auth.users
  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  ) values (
    '00000000-0000-0000-0000-000000000000',
    new_user_id,
    'authenticated',
    'authenticated',
    clean_email,
    encrypted_pw,
    now(),
    jsonb_build_object('provider', 'email', 'providers', array['email']),
    jsonb_build_object(
      'full_name', p_full_name,
      'username', clean_uname,
      'role', p_role,
      'school_id', effective_school,
      'phone_number', p_phone_number,
      'gender', p_gender,
      'assigned_grade', assigned_grade_val,
      'assigned_class', assigned_class_val,
      'is_attendance_teacher', is_attendance,
      'attendance_class', attendance_class_val,
      'attendance_grade', attendance_grade_val
    ),
    now(),
    now()
  );

  -- Insert or update public.users
  insert into public.users (
    id,
    email,
    username,
    full_name,
    role,
    requested_role,
    school_id,
    section_id,
    assigned_subject,
    assigned_class,
    assigned_grade,
    phone_number,
    gender,
    is_attendance_teacher,
    attendance_class,
    attendance_grade,
    approval_status,
    is_active,
    must_change_password,
    created_at
  ) values (
    new_user_id,
    clean_email,
    clean_uname,
    p_full_name,
    p_role,
    p_role,
    effective_school,
    p_section_id,
    p_subject,
    assigned_class_val,
    assigned_grade_val,
    p_phone_number,
    p_gender,
    is_attendance,
    attendance_class_val,
    attendance_grade_val,
    'approved',
    true,
    false,
    now()
  ) on conflict (id) do update set
    email = excluded.email,
    username = excluded.username,
    full_name = excluded.full_name,
    role = excluded.role,
    school_id = excluded.school_id,
    section_id = excluded.section_id,
    assigned_subject = excluded.assigned_subject,
    assigned_class = excluded.assigned_class,
    assigned_grade = excluded.assigned_grade,
    phone_number = excluded.phone_number,
    gender = excluded.gender,
    is_attendance_teacher = excluded.is_attendance_teacher,
    attendance_class = excluded.attendance_class,
    attendance_grade = excluded.attendance_grade,
    approval_status = 'approved',
    is_active = true;

  if p_section_id is not null and p_role = 'student' then
    insert into public.student_sections (student_id, section_id)
    values (new_user_id, p_section_id)
    on conflict do nothing;
  end if;

  return jsonb_build_object(
    'success', true,
    'user_id', new_user_id,
    'username', clean_uname,
    'email', clean_email
  );
end;
$$;

-- Overload with JSONB payload
create or replace function public.admin_create_user(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'extensions', 'pg_temp'
as $$
begin
  return public.admin_create_user(
    p_full_name => payload->>'p_full_name',
    p_username => payload->>'p_username',
    p_email => payload->>'p_email',
    p_password => payload->>'p_password',
    p_role => payload->>'p_role',
    p_school_id => (payload->>'p_school_id')::uuid,
    p_section_id => (payload->>'p_section_id')::uuid,
    p_subject => payload->>'p_subject',
    p_phone_number => payload->>'p_phone_number',
    p_gender => payload->>'p_gender',
    p_grade => payload->>'p_grade',
    p_class => payload->>'p_class',
    p_is_attendance_teacher => coalesce((payload->>'p_is_attendance_teacher')::boolean, false),
    p_attendance_grade => payload->>'p_attendance_grade',
    p_attendance_class => payload->>'p_attendance_class'
  );
end;
$$;

grant execute on function public.admin_create_user(text, text, text, text, text, uuid, uuid, text, text, text, text, text, boolean, text, text) to authenticated;
grant execute on function public.admin_create_user(jsonb) to authenticated;

