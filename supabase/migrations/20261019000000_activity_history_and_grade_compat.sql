begin;

alter table public.grades
  add column if not exists incorrect_answers integer
  check (incorrect_answers >= 0);

create schema if not exists private;

create or replace function private.capture_app_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_data jsonb;
  old_data jsonb;
  action_name text;
  target_id uuid;
  actor_id uuid := (select auth.uid());
  event_details jsonb;
begin
  if tg_op = 'DELETE' then
    row_data := to_jsonb(old);
  else
    row_data := to_jsonb(new);
  end if;
  if tg_op <> 'INSERT' then
    old_data := to_jsonb(old);
  end if;
  if tg_op = 'UPDATE' and old_data = row_data then
    return new;
  end if;

  if tg_table_name = 'users' then
    target_id := nullif(row_data ->> 'id', '')::uuid;
    if tg_op = 'DELETE' then
      action_name := 'account_deleted';
      target_id := null;
    elsif tg_op = 'INSERT' then
      action_name := 'account_created';
    elsif old_data -> 'avatar_url' is distinct from row_data -> 'avatar_url' then
      action_name := 'profile_photo_updated';
    elsif old_data -> 'full_name' is distinct from row_data -> 'full_name' then
      action_name := 'profile_updated';
    elsif old_data -> 'must_change_password' is distinct from row_data -> 'must_change_password' then
      if coalesce((row_data ->> 'must_change_password')::boolean, false)
         or actor_id is null then
        return new;
      end if;
      action_name := 'password_changed';
    elsif old_data -> 'approval_status' is distinct from row_data -> 'approval_status'
       or old_data -> 'role' is distinct from row_data -> 'role' then
      action_name := case
        when row_data ->> 'approval_status' = 'approved' then 'account_approved'
        when row_data ->> 'approval_status' = 'rejected' then 'account_rejected'
        else 'account_updated'
      end;
    else
      action_name := 'account_updated';
    end if;
    event_details := jsonb_build_object(
      'target_user_id', row_data ->> 'id',
      'target_name', coalesce(row_data ->> 'full_name', row_data ->> 'username'),
      'target_role', row_data ->> 'role'
    );
  elsif tg_table_name = 'quizzes' then
    target_id := nullif(row_data ->> 'teacher_id', '')::uuid;
    if tg_op = 'INSERT' then
      action_name := 'quiz_created';
    elsif tg_op = 'DELETE' then
      action_name := 'quiz_deleted';
      target_id := null;
    elsif old_data -> 'is_published' is distinct from row_data -> 'is_published' then
      action_name := case
        when coalesce((row_data ->> 'is_published')::boolean, false)
          then 'quiz_published'
        else 'quiz_unpublished'
      end;
    else
      action_name := 'quiz_updated';
    end if;
    event_details := jsonb_build_object(
      'quiz_id', row_data ->> 'id',
      'quiz_title', row_data ->> 'title'
    );
  elsif tg_table_name = 'grades' and tg_op = 'INSERT' then
    action_name := 'quiz_submitted';
    target_id := nullif(row_data ->> 'student_id', '')::uuid;
    event_details := jsonb_build_object(
      'quiz_id', row_data ->> 'quiz_id',
      'score', row_data ->> 'score',
      'total_points', row_data ->> 'total_points',
      'percentage', row_data ->> 'percentage'
    );
  else
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  if actor_id is null and tg_table_name = 'grades' then
    actor_id := target_id;
  elsif actor_id is null
      and tg_table_name = 'users'
      and action_name in ('profile_updated', 'profile_photo_updated', 'password_changed') then
    actor_id := nullif(event_details ->> 'target_user_id', '')::uuid;
  end if;

  if actor_id is not null then
    event_details := event_details || jsonb_build_object(
      'actor_name',
      (select users.full_name from public.users where users.id = actor_id)
    );
  end if;

  insert into public.audit_logs (action, performed_by, target_user, details)
  values (action_name, actor_id, target_id, event_details);
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function private.capture_app_activity()
  from public, anon, authenticated;

drop trigger if exists users_capture_app_activity on public.users;
create trigger users_capture_app_activity
  after insert or update or delete on public.users
  for each row execute function private.capture_app_activity();

drop trigger if exists quizzes_capture_app_activity on public.quizzes;
create trigger quizzes_capture_app_activity
  after insert or update or delete on public.quizzes
  for each row execute function private.capture_app_activity();

drop trigger if exists grades_capture_app_activity on public.grades;
create trigger grades_capture_app_activity
  after insert on public.grades
  for each row execute function private.capture_app_activity();

drop policy if exists audit_logs_admin_read on public.audit_logs;
drop policy if exists audit_logs_read_activity on public.audit_logs;
create policy audit_logs_read_activity
  on public.audit_logs for select to authenticated
  using (
    (select private.app_current_role()) in ('admin', 'teacher')
    or performed_by = (select auth.uid())
    or target_user = (select auth.uid())
  );

commit;
