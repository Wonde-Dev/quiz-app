-- Migration: 20261030100000_strict_rbac_and_ownership_transfer.sql
-- Description:
-- 1. Strictly align current accounts: 1 Super Admin (WondevAdmin), 1 Director (SultanAdinan).
-- 2. Enforce ONLY ONE active Super Admin via unique index idx_single_active_super_admin.
-- 3. Enforce ONLY ONE active Director via unique index idx_ciro_single_active_director.
-- 4. Create public.transfer_super_admin_ownership RPC.
-- 5. Create public.transfer_director_position RPC.
-- 6. Create public.toggle_user_status RPC (suspend/activate accounts with RBAC).
-- 7. Create public.teacher_academic_activities table and get_teacher_academic_activities RPC.
-- 8. Seed existing academic activities from quizzes and learning resources.

begin;

-- ============================================================================
-- 1. ALIGN CURRENT PRIVILEGED ACCOUNTS
-- ============================================================================

-- Ensure WondevAdmin is the single active Super Admin
update public.users
set role = 'admin',
    is_super_admin = true,
    is_active = true,
    approval_status = 'approved'
where lower(email) = 'wondedev369@gmail.com';

-- Appoint SultanAdinan as the single active School Director
update public.users
set role = 'subadmin',
    is_super_admin = false,
    is_active = true,
    approval_status = 'approved'
where lower(email) = 'wondetech404@gmail.com';

-- Update auth.users metadata accordingly
update auth.users
set raw_user_meta_data = raw_user_meta_data || '{"role": "admin", "is_super_admin": true}'::jsonb
where lower(email) = 'wondedev369@gmail.com';

update auth.users
set raw_user_meta_data = raw_user_meta_data || '{"role": "subadmin", "is_super_admin": false}'::jsonb
where lower(email) = 'wondetech404@gmail.com';

-- ============================================================================
-- 2. STRICT DATABASE CONSTRAINTS: ONLY ONE ACTIVE SUPER ADMIN & ONE DIRECTOR
-- ============================================================================

drop index if exists public.idx_single_active_super_admin;
create unique index idx_single_active_super_admin
on public.users ((true))
where role = 'admin' and is_active = true;

drop index if exists public.idx_ciro_single_active_director;
create unique index idx_ciro_single_active_director
on public.users (coalesce(school_id, '00000000-0000-4000-8000-000000000001'))
where role in ('subadmin', 'director') and is_active = true;

-- ============================================================================
-- 3. TEACHER ACADEMIC ACTIVITIES TABLE & TRACKING
-- ============================================================================

create table if not exists public.teacher_academic_activities (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade default '00000000-0000-4000-8000-000000000001',
  teacher_id text not null,
  teacher_name text not null,
  activity_type text not null, -- 'quiz_created', 'examination_published', 'resource_uploaded', 'marks_evaluated'
  description text not null,
  subject text,
  target_grade text,
  target_section text,
  status text not null default 'Active',
  created_at timestamptz not null default now()
);

alter table public.teacher_academic_activities enable row level security;
grant all on public.teacher_academic_activities to authenticated;
grant select on public.teacher_academic_activities to anon;

drop policy if exists "teacher_academic_activities_select" on public.teacher_academic_activities;
create policy "teacher_academic_activities_select" on public.teacher_academic_activities
  for select using (true);

drop policy if exists "teacher_academic_activities_manage" on public.teacher_academic_activities;
create policy "teacher_academic_activities_manage" on public.teacher_academic_activities
  for all using (
    private.app_current_role() in ('admin', 'subadmin', 'teacher')
  );

-- Seed existing quizzes into academic activities
insert into public.teacher_academic_activities (
  school_id, teacher_id, teacher_name, activity_type, description, subject, target_grade, target_section, status, created_at
)
select
  coalesce(q.school_id, '00000000-0000-4000-8000-000000000001'),
  q.teacher_id::text,
  coalesce(u.full_name, u.username, 'Faculty Teacher'),
  case when q.is_published then 'examination_published' else 'quiz_created' end,
  'Prepared ' || coalesce(q.title, 'Examination'),
  coalesce(u.assigned_subject, 'General'),
  q.target_grade,
  q.target_section,
  case when q.is_published then 'Published' else 'Draft' end,
  coalesce(q.created_at, now())
from public.quizzes q
left join public.users u on u.id::text = q.teacher_id::text
where q.teacher_id is not null
  and not exists (
    select 1 from public.teacher_academic_activities a where a.description = ('Prepared ' || coalesce(q.title, 'Examination'))
  );

-- Seed existing course resources into academic activities
insert into public.teacher_academic_activities (
  school_id, teacher_id, teacher_name, activity_type, description, subject, target_grade, target_section, status, created_at
)
select
  coalesce(r.school_id, '00000000-0000-4000-8000-000000000001'),
  r.teacher_id::text,
  coalesce(u.full_name, u.username, 'Faculty Teacher'),
  'resource_uploaded',
  'Uploaded study material: ' || coalesce(r.title, 'Document'),
  coalesce(u.assigned_subject, 'General'),
  r.target_grade,
  r.target_section,
  'Active',
  coalesce(r.created_at, now())
from public.course_resources r
left join public.users u on u.id::text = r.teacher_id::text
where r.teacher_id is not null
  and not exists (
    select 1 from public.teacher_academic_activities a where a.description = ('Uploaded study material: ' || coalesce(r.title, 'Document'))
  );

-- Trigger to automatically capture new quizzes
create or replace function public.capture_quiz_academic_activity()
returns trigger
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
declare
  t_name text;
  t_subj text;
begin
  select coalesce(full_name, username, 'Faculty Teacher'), coalesce(assigned_subject, 'General')
  into t_name, t_subj
  from public.users
  where id::text = new.teacher_id::text;

  insert into public.teacher_academic_activities (
    school_id, teacher_id, teacher_name, activity_type, description, subject, target_grade, target_section, status, created_at
  )
  values (
    coalesce(new.school_id, '00000000-0000-4000-8000-000000000001'),
    new.teacher_id::text,
    coalesce(t_name, 'Faculty Teacher'),
    case when new.is_published then 'examination_published' else 'quiz_created' end,
    'Prepared examination: ' || coalesce(new.title, 'Quiz'),
    coalesce(t_subj, 'General'),
    new.target_grade,
    new.target_section,
    case when new.is_published then 'Published' else 'Draft' end,
    now()
  );
  return new;
end;
$$;

drop trigger if exists trg_capture_quiz_activity on public.quizzes;
create trigger trg_capture_quiz_activity
after insert on public.quizzes
for each row execute function public.capture_quiz_academic_activity();

-- Trigger to automatically capture new learning resources
create or replace function public.capture_resource_academic_activity()
returns trigger
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
declare
  t_name text;
  t_subj text;
begin
  select coalesce(full_name, username, 'Faculty Teacher'), coalesce(assigned_subject, 'General')
  into t_name, t_subj
  from public.users
  where id::text = new.teacher_id::text;

  insert into public.teacher_academic_activities (
    school_id, teacher_id, teacher_name, activity_type, description, subject, target_grade, target_section, status, created_at
  )
  values (
    coalesce(new.school_id, '00000000-0000-4000-8000-000000000001'),
    new.teacher_id::text,
    coalesce(t_name, 'Faculty Teacher'),
    'resource_uploaded',
    'Uploaded study resource: ' || coalesce(new.title, 'Document'),
    coalesce(t_subj, 'General'),
    new.target_grade,
    new.target_section,
    'Active',
    now()
  );
  return new;
end;
$$;

drop trigger if exists trg_capture_resource_activity on public.course_resources;
create trigger trg_capture_resource_activity
after insert on public.course_resources
for each row execute function public.capture_resource_academic_activity();

-- ============================================================================
-- 4. GET TEACHER ACADEMIC ACTIVITIES RPC (for Super Admin & Director)
-- ============================================================================

create or replace function public.get_teacher_academic_activities(
  p_school_id uuid default null,
  p_limit int default 50
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = 'off'
as $$
declare
  v_school_id uuid := coalesce(p_school_id, '00000000-0000-4000-8000-000000000001');
  v_activities jsonb;
begin
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', a.id,
      'teacher_id', a.teacher_id,
      'teacher_name', a.teacher_name,
      'activity_type', a.activity_type,
      'description', a.description,
      'subject', a.subject,
      'target_grade', a.target_grade,
      'target_section', a.target_section,
      'status', a.status,
      'created_at', a.created_at
    ) order by a.created_at desc
  ), '[]'::jsonb)
  into v_activities
  from (
    select * from public.teacher_academic_activities
    where school_id = v_school_id
    order by created_at desc
    limit coalesce(p_limit, 50)
  ) a;

  return v_activities;
end;
$$;

grant execute on function public.get_teacher_academic_activities(uuid, int) to authenticated, anon;

-- ============================================================================
-- 5. TRANSFER SUPER ADMIN OWNERSHIP RPC
-- ============================================================================

drop function if exists public.transfer_super_admin_ownership(uuid, text);

create or replace function public.transfer_super_admin_ownership(
  p_target_user_id uuid,
  p_current_password text
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'extensions', 'pg_temp'
set row_security = 'off'
as $$
declare
  v_caller_id uuid := auth.uid();
  v_caller record;
  v_target record;
  v_caller_auth record;
begin
  if v_caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select id, role, is_super_admin, username, email into v_caller
  from public.users
  where id = v_caller_id;

  if v_caller.role <> 'admin' and v_caller.is_super_admin is not true then
    raise exception 'Permission denied: Only the active Super Admin can transfer ownership' using errcode = '42501';
  end if;

  -- Verify current password
  select encrypted_password into v_caller_auth
  from auth.users
  where id = v_caller_id;

  if v_caller_auth is null or crypt(p_current_password, v_caller_auth.encrypted_password) <> v_caller_auth.encrypted_password then
    raise exception 'Invalid password confirmation. Ownership transfer denied.' using errcode = '42501';
  end if;

  if p_target_user_id = v_caller_id then
    raise exception 'Target user cannot be the current Super Admin' using errcode = '22023';
  end if;

  select id, role, username, email, is_active into v_target
  from public.users
  where id = p_target_user_id;

  if v_target.id is null then
    raise exception 'Target user not found' using errcode = 'P0002';
  end if;

  if v_target.is_active is false then
    raise exception 'Target user account is inactive or suspended' using errcode = '22023';
  end if;

  -- Atomically transfer:
  -- 1. Demote old Super Admin to teacher role
  update public.users
  set is_super_admin = false,
      role = 'teacher'
  where id = v_caller_id;

  -- 2. Promote target user to Super Admin
  update public.users
  set is_super_admin = true,
      role = 'admin',
      approval_status = 'approved',
      is_active = true
  where id = p_target_user_id;

  -- Sync auth.users metadata
  begin
    update auth.users
    set raw_user_meta_data = raw_user_meta_data || '{"role": "teacher", "is_super_admin": false}'::jsonb
    where id = v_caller_id;

    update auth.users
    set raw_user_meta_data = raw_user_meta_data || '{"role": "admin", "is_super_admin": true}'::jsonb
    where id = p_target_user_id;
  exception when others then null;
  end;

  -- Log in audit_logs
  insert into public.audit_logs (
    action, performed_by, target_user, details
  )
  values (
    'super_admin_ownership_transferred',
    v_caller_id,
    v_target.username,
    jsonb_build_object(
      'previous_super_admin_id', v_caller_id,
      'previous_super_admin_username', v_caller.username,
      'new_super_admin_id', p_target_user_id,
      'new_super_admin_username', v_target.username
    )
  );

  return jsonb_build_object(
    'success', true,
    'message', 'Super Admin ownership successfully transferred to ' || coalesce(v_target.username, v_target.email),
    'new_super_admin_id', p_target_user_id
  );
end;
$$;

grant execute on function public.transfer_super_admin_ownership(uuid, text) to authenticated, anon;

-- ============================================================================
-- 6. TRANSFER DIRECTOR POSITION RPC
-- ============================================================================

drop function if exists public.transfer_director_position(uuid, text);

create or replace function public.transfer_director_position(
  p_target_teacher_id uuid,
  p_current_password text
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'extensions', 'pg_temp'
set row_security = 'off'
as $$
declare
  v_caller_id uuid := auth.uid();
  v_caller record;
  v_target record;
  v_caller_auth record;
begin
  if v_caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select id, role, is_super_admin, username, email into v_caller
  from public.users
  where id = v_caller_id;

  if v_caller.role not in ('admin', 'subadmin', 'director') and v_caller.is_super_admin is not true then
    raise exception 'Permission denied: Only the active Director or Super Admin can transfer Director position' using errcode = '42501';
  end if;

  -- Verify current password
  select encrypted_password into v_caller_auth
  from auth.users
  where id = v_caller_id;

  if v_caller_auth is null or crypt(p_current_password, v_caller_auth.encrypted_password) <> v_caller_auth.encrypted_password then
    raise exception 'Invalid password confirmation. Position transfer denied.' using errcode = '42501';
  end if;

  if p_target_teacher_id = v_caller_id then
    raise exception 'Target teacher cannot be the current Director' using errcode = '22023';
  end if;

  select id, role, username, email, is_active into v_target
  from public.users
  where id = p_target_teacher_id;

  if v_target.id is null then
    raise exception 'Target teacher not found' using errcode = 'P0002';
  end if;

  if v_target.role <> 'teacher' then
    raise exception 'Director position can only be transferred to an eligible Faculty Teacher' using errcode = '22023';
  end if;

  if v_target.is_active is false then
    raise exception 'Target teacher account is inactive or suspended' using errcode = '22023';
  end if;

  -- Atomically transfer:
  -- If caller is the Director, demote old Director to teacher
  if v_caller.role in ('subadmin', 'director') then
    update public.users
    set role = 'teacher'
    where id = v_caller_id;

    begin
      update auth.users
      set raw_user_meta_data = raw_user_meta_data || '{"role": "teacher"}'::jsonb
      where id = v_caller_id;
    exception when others then null;
    end;
  else
    -- Super Admin is transferring: demote any other existing director to teacher first
    update public.users
    set role = 'teacher'
    where role in ('subadmin', 'director') and id <> p_target_teacher_id;
  end if;

  -- Promote target teacher to Director
  update public.users
  set role = 'subadmin',
      approval_status = 'approved',
      is_active = true
  where id = p_target_teacher_id;

  begin
    update auth.users
    set raw_user_meta_data = raw_user_meta_data || '{"role": "subadmin"}'::jsonb
    where id = p_target_teacher_id;
  exception when others then null;
  end;

  -- Log in audit_logs
  insert into public.audit_logs (
    action, performed_by, target_user, details
  )
  values (
    'director_position_transferred',
    v_caller_id,
    v_target.username,
    jsonb_build_object(
      'transferred_by', v_caller.username,
      'new_director_id', p_target_teacher_id,
      'new_director_username', v_target.username
    )
  );

  return jsonb_build_object(
    'success', true,
    'message', 'Director position successfully transferred to ' || coalesce(v_target.username, v_target.email),
    'new_director_id', p_target_teacher_id
  );
end;
$$;

grant execute on function public.transfer_director_position(uuid, text) to authenticated, anon;

-- ============================================================================
-- 7. TOGGLE USER STATUS RPC (Suspend / Activate Account)
-- ============================================================================

drop function if exists public.toggle_user_status(uuid, boolean);

create or replace function public.toggle_user_status(
  p_user_id uuid,
  p_is_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
set row_security = 'off'
as $$
declare
  v_caller_id uuid := auth.uid();
  v_caller record;
  v_target record;
begin
  if v_caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select id, role, is_super_admin, username into v_caller
  from public.users
  where id = v_caller_id;

  select id, role, is_super_admin, username, email into v_target
  from public.users
  where id = p_user_id;

  if v_target.id is null then
    raise exception 'Target user not found' using errcode = 'P0002';
  end if;

  -- Protected Super Admin
  if v_target.is_super_admin is true or v_target.role = 'admin' then
    raise exception 'Permission denied: The Super Administrator account is protected and cannot be suspended' using errcode = '42501';
  end if;

  -- Hierarchy check:
  -- Super Admin can suspend/activate anyone
  if v_caller.role = 'admin' or v_caller.is_super_admin is true then
    null;
  -- Director can suspend/activate TEACHERS ONLY
  elsif v_caller.role in ('subadmin', 'director') then
    if v_target.role <> 'teacher' then
      raise exception 'Permission denied: School Directors can only suspend or activate Faculty Teacher accounts' using errcode = '42501';
    end if;
  else
    raise exception 'Permission denied: You do not have authority to suspend or activate accounts' using errcode = '42501';
  end if;

  update public.users
  set is_active = p_is_active
  where id = p_user_id;

  insert into public.audit_logs (
    action, performed_by, target_user, details
  )
  values (
    case when p_is_active then 'user_activated' else 'user_suspended' end,
    v_caller_id,
    v_target.username,
    jsonb_build_object(
      'target_id', p_user_id,
      'new_active_status', p_is_active,
      'role', v_target.role,
      'performed_by_role', v_caller.role
    )
  );

  return jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'is_active', p_is_active,
    'message', case when p_is_active then 'Account successfully activated' else 'Account suspended successfully' end
  );
end;
$$;

grant execute on function public.toggle_user_status(uuid, boolean) to authenticated, anon;

commit;
