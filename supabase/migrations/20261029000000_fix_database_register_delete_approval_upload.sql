-- Migration: 20261029000000_fix_database_register_delete_approval_upload.sql
-- Description: Comprehensive database fixes for user registration, account deletion, registration approval, and file/storage uploads.

begin;

-- ============================================================================
-- 1. STORAGE BUCKETS & POLICIES (UPLOAD FIXES)
-- ============================================================================

-- Ensure profile-photos and course-materials buckets allow any valid file mime type
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('profile-photos', 'profile-photos', true, 10485760, null),
  ('course-materials', 'course-materials', true, 104857600, null)
on conflict (id) do update set
  public = true,
  allowed_mime_types = null,
  file_size_limit = excluded.file_size_limit;

-- Clean up restrictive/conflicting storage policies on storage.objects
drop policy if exists "profile_photos_upload_own" on storage.objects;
drop policy if exists "profile_photos_update_own" on storage.objects;
drop policy if exists "profile_photos_delete_own" on storage.objects;
drop policy if exists "profile_photos_public_read" on storage.objects;

drop policy if exists "course_materials_public_read" on storage.objects;
drop policy if exists "course_materials_teacher_upload" on storage.objects;
drop policy if exists "course_materials_teacher_delete" on storage.objects;
drop policy if exists "course_materials_bucket_public" on storage.objects;
drop policy if exists "course_materials_bucket_auth_insert" on storage.objects;

drop policy if exists "storage_app_public_read" on storage.objects;
drop policy if exists "storage_app_auth_insert" on storage.objects;
drop policy if exists "storage_app_auth_update" on storage.objects;
drop policy if exists "storage_app_auth_delete" on storage.objects;

-- Allow public read access to uploaded course materials & profile pictures
create policy "storage_app_public_read" on storage.objects
  for select
  using (bucket_id in ('profile-photos', 'course-materials'));

-- Allow authenticated users (students, teachers, admins) to upload diagrams, worksheets, avatars, and answer attachments
create policy "storage_app_auth_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id in ('profile-photos', 'course-materials'));

create policy "storage_app_auth_update" on storage.objects
  for update to authenticated
  using (bucket_id in ('profile-photos', 'course-materials'))
  with check (bucket_id in ('profile-photos', 'course-materials'));

create policy "storage_app_auth_delete" on storage.objects
  for delete to authenticated
  using (bucket_id in ('profile-photos', 'course-materials'));

-- ============================================================================
-- 2. FOREIGN KEY CONSTRAINTS (PREVENT DELETE BLOCKS)
-- ============================================================================

alter table public.quizzes
  drop constraint if exists quizzes_created_by_fkey,
  add constraint quizzes_created_by_fkey foreign key (created_by) references public.users(id) on delete set null;

alter table public.questions
  drop constraint if exists questions_created_by_fkey,
  add constraint questions_created_by_fkey foreign key (created_by) references public.users(id) on delete set null;

alter table public.users
  drop constraint if exists users_created_by_fkey,
  add constraint users_created_by_fkey foreign key (created_by) references public.users(id) on delete set null;

alter table public.teacher_courses
  drop constraint if exists teacher_courses_assigned_by_fkey,
  add constraint teacher_courses_assigned_by_fkey foreign key (assigned_by) references public.users(id) on delete set null;

alter table public.suspicious_activities
  drop constraint if exists suspicious_activities_student_id_fkey,
  add constraint suspicious_activities_student_id_fkey foreign key (student_id) references public.users(id) on delete cascade;

alter table public.password_reset_requests
  drop constraint if exists password_reset_requests_teacher_id_fkey,
  add constraint password_reset_requests_teacher_id_fkey foreign key (teacher_id) references public.users(id) on delete set null;

alter table public.quiz_attempts
  drop constraint if exists quiz_attempts_student_id_fkey,
  add constraint quiz_attempts_student_id_fkey foreign key (student_id) references public.users(id) on delete cascade;

-- ============================================================================
-- 3. REGISTRATION FIX: handle_quiz_app_user_signup
-- ============================================================================

create or replace function public.handle_quiz_app_user_signup()
returns trigger
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
declare
  is_admin_created boolean := coalesce(
    (new.raw_app_meta_data ->> 'created_by_admin')::boolean,
    (new.raw_user_meta_data ->> 'is_admin_creation')::boolean,
    false
  );
  requested_role_val text := lower(trim(coalesce(
    new.raw_user_meta_data ->> 'requested_role',
    new.raw_user_meta_data ->> 'role',
    'student'
  )));
  assigned_role text;
  username_val text := trim(coalesce(new.raw_user_meta_data ->> 'username', ''));
  full_name_val text := trim(coalesce(new.raw_user_meta_data ->> 'full_name', ''));
  school_id_val uuid;
  section_id_val uuid;
  phone_val text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'phone_number', new.raw_user_meta_data ->> 'phone', '')), '');
  gender_val text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'gender', '')), '');
  grade_val text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'requested_grade', new.raw_user_meta_data ->> 'assigned_grade', '')), '');
  class_val text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'requested_class', new.raw_user_meta_data ->> 'assigned_class', '')), '');
  subject_val text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'requested_subject', new.raw_user_meta_data ->> 'assigned_subject', '')), '');
  is_attendance boolean := coalesce((new.raw_user_meta_data ->> 'is_attendance_teacher')::boolean, false);
  attendance_class_val text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'attendance_class', '')), '');
  attendance_grade_val text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'attendance_grade', '')), '');
begin
  -- Validate role keyword
  if requested_role_val not in ('student', 'teacher', 'subadmin', 'admin', 'super_admin') then
    requested_role_val := 'student';
  end if;

  -- Block self-registration for admin or super_admin
  if not is_admin_created and new.email_confirmed_at is null and requested_role_val in ('admin', 'super_admin') then
    raise exception 'Administrator accounts are invitation-only' using errcode = '42501';
  end if;

  -- Fallbacks for name and username
  if length(full_name_val) < 1 then
    full_name_val := coalesce(nullif(username_val, ''), split_part(coalesce(new.email, 'User'), '@', 1), 'User');
  end if;
  if length(username_val) < 1 then
    username_val := coalesce(new.email, new.id::text);
  end if;

  begin
    school_id_val := nullif(new.raw_user_meta_data ->> 'school_id', '')::uuid;
  exception when others then
    school_id_val := null;
  end;

  begin
    section_id_val := nullif(new.raw_user_meta_data ->> 'section_id', '')::uuid;
  exception when others then
    section_id_val := null;
  end;

  -- Instant activation for admin-created or pre-confirmed accounts
  if is_admin_created or new.email_confirmed_at is not null then
    assigned_role := requested_role_val;
    insert into public.users (
      id, email, username, full_name, role, requested_role,
      school_id, section_id, phone_number, gender,
      assigned_grade, assigned_class, assigned_subject,
      requested_grade, requested_class, requested_subject,
      is_attendance_teacher, attendance_grade, attendance_class,
      approval_status, is_active, must_change_password, created_at
    ) values (
      new.id, lower(new.email), username_val, full_name_val, assigned_role, assigned_role,
      school_id_val, section_id_val, phone_val, gender_val,
      grade_val, class_val, subject_val,
      grade_val, class_val, subject_val,
      is_attendance, attendance_grade_val, attendance_class_val,
      'approved', true, false, now()
    ) on conflict (id) do update set
      email = excluded.email,
      username = excluded.username,
      full_name = excluded.full_name,
      role = excluded.role,
      requested_role = excluded.requested_role,
      school_id = coalesce(excluded.school_id, public.users.school_id),
      section_id = coalesce(excluded.section_id, public.users.section_id),
      phone_number = coalesce(excluded.phone_number, public.users.phone_number),
      gender = coalesce(excluded.gender, public.users.gender),
      assigned_grade = coalesce(excluded.assigned_grade, public.users.assigned_grade),
      assigned_class = coalesce(excluded.assigned_class, public.users.assigned_class),
      assigned_subject = coalesce(excluded.assigned_subject, public.users.assigned_subject),
      approval_status = 'approved',
      is_active = true;
  else
    -- Standard self-registration: starts pending approval
    insert into public.users (
      id, email, username, full_name, role, requested_role,
      school_id, section_id, phone_number, gender,
      requested_grade, requested_class, requested_subject,
      approval_status, is_active, must_change_password, created_at
    ) values (
      new.id, lower(new.email), username_val, full_name_val, 'student', requested_role_val,
      school_id_val, section_id_val, phone_val, gender_val,
      grade_val, class_val, subject_val,
      'pending', false, false, now()
    ) on conflict (id) do update set
      email = excluded.email,
      username = excluded.username,
      full_name = excluded.full_name,
      requested_role = excluded.requested_role,
      school_id = coalesce(excluded.school_id, public.users.school_id),
      section_id = coalesce(excluded.section_id, public.users.section_id),
      phone_number = coalesce(excluded.phone_number, public.users.phone_number),
      gender = coalesce(excluded.gender, public.users.gender),
      requested_grade = coalesce(excluded.requested_grade, public.users.requested_grade),
      requested_class = coalesce(excluded.requested_class, public.users.requested_class),
      requested_subject = coalesce(excluded.requested_subject, public.users.requested_subject);
  end if;

  return new;
end;
$$;

drop trigger if exists z_quiz_app_secure_profile on auth.users;
create trigger z_quiz_app_secure_profile
  after insert on auth.users
  for each row execute function public.handle_quiz_app_user_signup();

-- ============================================================================
-- 4. ADMIN REGISTRATION FIX: drop competing overloads & unify admin_create_user
-- ============================================================================

drop function if exists public.admin_create_user(text, text, text, text, text, uuid, uuid, text, text, text, boolean, text, text);

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
  clean_uname text := trim(p_username);
  clean_email text := lower(trim(p_email));
  existing_id uuid;
  assigned_role text := lower(trim(p_role));
  effective_school uuid := p_school_id;
  assigned_class_val text := p_class;
  assigned_grade_val text := p_grade;
  attendance_class_val text := p_attendance_class;
  attendance_grade_val text := p_attendance_grade;
  is_attendance boolean := coalesce(p_is_attendance_teacher, false);
  encrypted_pw text;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select id, role, is_super_admin, is_attendance_teacher, attendance_grade, attendance_class, school_id
  into caller
  from public.users
  where id = caller_id;

  if caller.id is null then
    raise exception 'Caller profile not found' using errcode = '42501';
  end if;

  -- Role boundaries:
  if caller.role = 'admin' or caller.is_super_admin is true then
    if assigned_role in ('admin', 'super_admin') then
      assigned_role := 'subadmin';
    end if;
  elsif caller.role = 'subadmin' then
    if assigned_role not in ('teacher', 'student') then
      raise exception 'Permission denied: Sub-admins can only register teachers and students' using errcode = '42501';
    end if;
    if caller.school_id is null then
      raise exception 'Permission denied: Sub-admin has no assigned school' using errcode = '42501';
    end if;
    effective_school := caller.school_id;
  elsif caller.role = 'teacher' then
    if caller.is_attendance_teacher is not true then
      raise exception 'Permission denied: Only designated Attendance Teachers can register student accounts' using errcode = '42501';
    end if;
    if assigned_role <> 'student' then
      raise exception 'Permission denied: Attendance teachers can only register student accounts' using errcode = '42501';
    end if;
    if caller.attendance_class is null then
      raise exception 'Permission denied: Attendance teacher has no assigned class' using errcode = '42501';
    end if;

    effective_school := caller.school_id;
    assigned_class_val := caller.attendance_class;
    assigned_grade_val := coalesce(caller.attendance_grade, p_grade);
    is_attendance := false;
    attendance_class_val := null;
    attendance_grade_val := null;
  else
    raise exception 'Permission denied: You do not have authority to register accounts' using errcode = '42501';
  end if;

  -- Check existing username or email
  select id into existing_id from public.users
  where lower(email) = clean_email or lower(username) = lower(clean_uname)
  limit 1;

  if existing_id is not null then
    return jsonb_build_object('success', false, 'error', 'An account with this email or username already exists');
  end if;

  select id into existing_id from auth.users
  where lower(email) = clean_email
  limit 1;

  if existing_id is not null then
    delete from auth.users where id = existing_id;
  end if;

  encrypted_pw := extensions.crypt(p_password, extensions.gen_salt('bf'));

  -- Insert into auth.users with created_by_admin flag
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
    jsonb_build_object('provider', 'email', 'providers', array['email'], 'created_by_admin', true),
    jsonb_build_object(
      'full_name', p_full_name,
      'username', clean_uname,
      'role', assigned_role,
      'requested_role', assigned_role,
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

  -- Insert into public.users
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
    requested_class,
    requested_grade,
    requested_subject,
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
    assigned_role,
    assigned_role,
    effective_school,
    p_section_id,
    p_subject,
    assigned_class_val,
    assigned_grade_val,
    assigned_class_val,
    assigned_grade_val,
    p_subject,
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
    requested_role = excluded.requested_role,
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

  if p_section_id is not null and assigned_role = 'student' then
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

-- ============================================================================
-- 5. DELETE ACCOUNT FIX: Clean cascade & flexible parameters delete_user_account
-- ============================================================================

drop function if exists public.delete_user_account(uuid, uuid);
drop function if exists public.delete_user_account(uuid);
drop function if exists public.delete_user_account(jsonb);

create or replace function public.delete_user_account(
  p_user_id uuid default null,
  user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
declare
  caller_id uuid := auth.uid();
  caller record;
  target_user record;
  t_quiz record;
  target_id uuid := coalesce(p_user_id, user_id);
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if target_id is null then
    raise exception 'Target user ID is required' using errcode = '23502';
  end if;

  select id, role, is_super_admin, is_attendance_teacher, attendance_grade, attendance_class, school_id
  into caller
  from public.users
  where id = caller_id;

  select id, email, username, role, is_super_admin, requested_class, assigned_class, school_id
  into target_user
  from public.users
  where id = target_id;

  if target_user.id is null then
    delete from auth.users where id = target_id;
    return jsonb_build_object('success', true, 'message', 'Account already deleted');
  end if;

  -- Protected Main Admin account protection
  if target_user.is_super_admin is true or
     lower(coalesce(target_user.email, '')) in ('wondedev369@gmail.com', 'wondeadmin@admin.edu') or
     lower(coalesce(target_user.username, '')) in ('wondedev369@gmail.com', 'wondeadmin@admin.edu') or
     (target_user.role = 'admin' and caller.role = 'subadmin') then
    raise exception 'Permission denied: The Main Administrator account is protected and cannot be deleted' using errcode = '42501';
  end if;

  -- Self-deletion prevention for admins
  if caller_id = target_id and caller.role in ('admin', 'subadmin') then
    raise exception 'Permission denied: Administrators cannot delete their own account' using errcode = '42501';
  end if;

  -- Authorization hierarchy
  if caller.role = 'admin' or caller.is_super_admin is true then
    null;
  elsif caller.role = 'subadmin' then
    if target_user.role in ('admin', 'subadmin', 'super_admin') then
      raise exception 'Permission denied: Sub-admins cannot delete other administrators' using errcode = '42501';
    end if;
    if caller.school_id is not null and target_user.school_id is not null and target_user.school_id <> caller.school_id then
      raise exception 'Permission denied: Sub-admins can only delete accounts from their own school' using errcode = '42501';
    end if;
  elsif caller.role = 'teacher' then
    if target_user.role <> 'student' then
      raise exception 'Permission denied: Teachers can only delete student accounts' using errcode = '42501';
    end if;
    if caller.is_attendance_teacher = true and caller.attendance_class is not null then
      if lower(trim(coalesce(target_user.requested_class, target_user.assigned_class, ''))) <> lower(trim(caller.attendance_class)) then
        raise exception 'Permission denied: Attendance teachers can only delete students of their assigned class (%)', caller.attendance_class using errcode = '42501';
      end if;
    end if;
  else
    raise exception 'Permission denied: Unauthorized to delete user accounts' using errcode = '42501';
  end if;

  -- Cascade delete child records to avoid foreign key violations
  delete from public.answers where student_id = target_id;
  delete from public.quiz_attempts where student_id = target_id;
  delete from public.grades where student_id = target_id;
  delete from public.student_sections where student_id = target_id;
  delete from public.suspicious_activities where student_id = target_id;
  delete from public.password_reset_requests where student_id = target_id or teacher_id = target_id;
  delete from public.teacher_courses where teacher_id = target_id or assigned_by = target_id;
  delete from public.course_resources where teacher_id = target_id::text;

  -- If target authored quizzes, cascade questions and quiz records
  for t_quiz in select id from public.quizzes where teacher_id = target_id or created_by = target_id loop
    delete from public.answers where question_id in (select id from public.questions where quiz_id = t_quiz.id);
    delete from public.grades where quiz_id = t_quiz.id;
    delete from public.quiz_attempts where quiz_id = t_quiz.id;
    delete from public.quiz_questions where quiz_id = t_quiz.id;
    delete from public.questions where quiz_id = t_quiz.id;
    delete from public.quizzes where id = t_quiz.id;
  end loop;

  -- Nullify any remaining references in questions / quizzes / courses / audit_logs / users
  update public.questions set created_by = null where created_by = target_id;
  update public.quizzes set created_by = null where created_by = target_id;
  update public.courses set teacher_id = null where teacher_id = target_id;
  update public.users set created_by = null where created_by = target_id;
  update public.audit_logs set performed_by = null where performed_by = target_id;
  update public.audit_logs set target_user = null where target_user = target_id;

  -- Delete public.users and auth.users
  delete from public.users where id = target_id;
  delete from auth.users where id = target_id;

  return jsonb_build_object('success', true, 'id', target_id);
end;
$$;

create or replace function public.delete_user_account(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
begin
  return public.delete_user_account(
    p_user_id => coalesce(
      nullif(payload->>'p_user_id', ''),
      nullif(payload->>'user_id', ''),
      nullif(payload->>'id', '')
    )::uuid
  );
end;
$$;

grant execute on function public.delete_user_account(uuid, uuid) to authenticated;
grant execute on function public.delete_user_account(jsonb) to authenticated;

-- ============================================================================
-- 6. APPROVAL FIX: review_user_registration with flexible parameters
-- ============================================================================

drop function if exists public.review_user_registration(jsonb);
drop function if exists public.review_user_registration(uuid, text, uuid);
drop function if exists public.review_user_registration(uuid, text, uuid, uuid, text, uuid);

create or replace function public.review_user_registration(
  p_user_id uuid default null,
  p_decision text default null,
  p_school_id uuid default null,
  user_id uuid default null,
  decision text default null,
  school_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
declare
  caller_id uuid := auth.uid();
  caller record;
  target_user record;
  target_uid uuid := coalesce(p_user_id, user_id);
  target_dec text := coalesce(p_decision, decision);
  target_sid uuid := coalesce(p_school_id, school_id);
  is_approve boolean := (lower(trim(coalesce(target_dec, ''))) in ('approve', 'approved'));
  target_role text;
  clean_target_class text;
  clean_caller_class text;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if target_uid is null then
    raise exception 'User ID is required' using errcode = '23502';
  end if;

  if caller_id = target_uid then
    raise exception 'Permission denied: Self-approval is strictly prohibited' using errcode = '42501';
  end if;

  select id, role, is_super_admin, is_attendance_teacher, attendance_grade, attendance_class, school_id
  into caller
  from public.users
  where id = caller_id;

  select id, role, requested_role, school_id, section_id, requested_grade, requested_class,
         assigned_grade, assigned_class, requested_subject, assigned_subject, full_name, email
  into target_user
  from public.users
  where id = target_uid;

  if target_user.id is null then
    return jsonb_build_object('success', false, 'error', 'User registration not found');
  end if;

  target_role := lower(trim(coalesce(nullif(target_user.requested_role, ''), target_user.role, 'student')));

  -- HIERARCHY VALIDATION:
  if caller.role = 'admin' or caller.is_super_admin is true then
    null;
  elsif caller.role = 'subadmin' then
    if target_role in ('admin', 'subadmin', 'super_admin') then
      raise exception 'Permission denied: Only the Super Administrator can review sub-administrator accounts' using errcode = '42501';
    end if;
    if caller.school_id is null then
      raise exception 'Permission denied: Sub-admin has no school assignment' using errcode = '42501';
    end if;
    if target_user.school_id is not null and target_user.school_id <> caller.school_id then
      raise exception 'Permission denied: Sub-admins can only review users from their own school' using errcode = '42501';
    end if;
    if target_sid is not null and target_sid <> caller.school_id then
      raise exception 'Permission denied: Sub-admins cannot assign users to other schools' using errcode = '42501';
    end if;
  elsif caller.role = 'teacher' and caller.is_attendance_teacher is true then
    if target_role <> 'student' then
      raise exception 'Permission denied: Attendance teachers can only review student registrations' using errcode = '42501';
    end if;
    if caller.school_id is not null and target_user.school_id is not null and target_user.school_id <> caller.school_id then
      raise exception 'Permission denied: You can only review students from your own school' using errcode = '42501';
    end if;

    clean_target_class := regexp_replace(lower(trim(coalesce(nullif(target_user.requested_class, ''), nullif(target_user.assigned_class, ''), ''))), '^class\s*', '');
    clean_caller_class := regexp_replace(lower(trim(coalesce(caller.attendance_class, ''))), '^class\s*', '');

    if clean_caller_class <> '' and clean_target_class <> clean_caller_class then
      raise exception 'Permission denied: You can only approve students for your assigned class (%)', caller.attendance_class using errcode = '42501';
    end if;
  else
    raise exception 'Permission denied: Unauthorized to review user registrations' using errcode = '42501';
  end if;

  -- Apply approval or rejection to public.users
  update public.users
  set
    approval_status = case when is_approve then 'approved' else 'rejected' end,
    is_active = is_approve,
    role = case
      when is_approve then target_role
      else role
    end,
    school_id = coalesce(target_sid, target_user.school_id, caller.school_id),
    assigned_grade = coalesce(target_user.assigned_grade, target_user.requested_grade),
    assigned_class = coalesce(target_user.assigned_class, target_user.requested_class),
    assigned_subject = coalesce(target_user.assigned_subject, target_user.requested_subject)
  where id = target_uid;

  if is_approve then
    -- Confirm email in auth.users and update metadata so app session detects approval immediately
    update auth.users
    set
      email_confirmed_at = coalesce(email_confirmed_at, now()),
      raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object(
        'approval_status', 'approved',
        'is_active', true,
        'role', target_role
      ),
      updated_at = now()
    where id = target_uid;

    if target_user.section_id is not null then
      insert into public.student_sections (student_id, section_id)
      values (target_uid, target_user.section_id)
      on conflict do nothing;
    end if;
  end if;

  return jsonb_build_object(
    'success', true,
    'status', case when is_approve then 'approved' else 'rejected' end,
    'id', target_uid,
    'role', case when is_approve then target_role else target_user.role end
  );
end;
$$;

create or replace function public.review_user_registration(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
begin
  return public.review_user_registration(
    p_user_id => coalesce(
      nullif(payload->>'p_user_id', ''),
      nullif(payload->>'user_id', ''),
      nullif(payload->>'id', '')
    )::uuid,
    p_decision => coalesce(
      payload->>'p_decision',
      payload->>'decision'
    ),
    p_school_id => nullif(
      coalesce(payload->>'p_school_id', payload->>'school_id', ''),
      ''
    )::uuid
  );
end;
$$;

grant execute on function public.review_user_registration(uuid, text, uuid, uuid, text, uuid) to authenticated;
grant execute on function public.review_user_registration(jsonb) to authenticated;

-- ============================================================================
-- 7. COURSE RESOURCES RLS POLICIES FOR FACULTY AND ADMINISTRATION
-- ============================================================================

alter table public.course_resources enable row level security;

drop policy if exists "course_resources_select" on public.course_resources;
drop policy if exists "course_resources_select_all" on public.course_resources;
drop policy if exists "course_resources_select_policy" on public.course_resources;
drop policy if exists "course_resources_teacher_insert" on public.course_resources;
drop policy if exists "course_resources_teacher_insert_policy" on public.course_resources;
drop policy if exists "course_resources_teacher_update" on public.course_resources;
drop policy if exists "course_resources_teacher_update_policy" on public.course_resources;
drop policy if exists "course_resources_teacher_delete" on public.course_resources;
drop policy if exists "course_resources_delete" on public.course_resources;
drop policy if exists "course_resources_delete_policy" on public.course_resources;

create policy "course_resources_select_policy" on public.course_resources
  for select
  using (true);

create policy "course_resources_teacher_insert_policy" on public.course_resources
  for insert
  with check (
    ((select role from public.users where id = auth.uid()) = 'teacher') and
    (teacher_id = auth.uid()::text)
  );

create policy "course_resources_teacher_update_policy" on public.course_resources
  for update
  using (
    ((select role from public.users where id = auth.uid()) = 'teacher') and
    (teacher_id = auth.uid()::text)
  )
  with check (
    ((select role from public.users where id = auth.uid()) = 'teacher') and
    (teacher_id = auth.uid()::text)
  );

create policy "course_resources_delete_policy" on public.course_resources
  for delete
  using (
    (teacher_id = auth.uid()::text) or
    ((select is_super_admin or role = 'admin' from public.users where id = auth.uid())) or
    (
      ((select role from public.users where id = auth.uid()) = 'subadmin') and
      (school_id = (select school_id from public.users where id = auth.uid()))
    )
  );

commit;
