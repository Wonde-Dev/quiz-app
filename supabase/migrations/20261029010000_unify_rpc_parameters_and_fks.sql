-- Migration: 20261029010000_unify_rpc_parameters_and_fks.sql
-- Description: Unify RPC signatures for delete_user_account and review_user_registration and update foreign keys.

begin;

-- ============================================================================
-- 1. FOREIGN KEY CONSTRAINTS (PREVENT DELETE BLOCKS)
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
-- 2. DELETE ACCOUNT FIX: Clean cascade & flexible parameters delete_user_account
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
-- 3. APPROVAL FIX: review_user_registration with flexible parameters
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

commit;

