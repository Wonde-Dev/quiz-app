-- Apply after the core quiz-app tables and schools table have been created.
begin;

alter table public.users
  add column if not exists email text,
  add column if not exists school_id uuid references public.schools(id) on delete set null,
  add column if not exists must_change_password boolean not null default false,
  add column if not exists is_active boolean not null default true,
  add column if not exists requested_role text,
  add column if not exists approval_status text not null default 'approved',
  add column if not exists last_login timestamptz;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'users'
      and column_name = 'password_hash'
  ) then
    alter table public.users alter column password_hash drop not null;
  end if;
end;
$$;

alter table public.users
  drop constraint if exists users_requested_role_check,
  add constraint users_requested_role_check
    check (requested_role is null or requested_role in ('student', 'teacher', 'admin')),
  drop constraint if exists users_approval_status_check,
  add constraint users_approval_status_check
    check (approval_status in ('pending', 'approved', 'rejected'));

create unique index if not exists users_username_lower_unique
  on public.users (lower(username))
  where username is not null and username <> '';

create or replace function public.handle_quiz_app_user_signup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_role text := coalesce(new.raw_user_meta_data ->> 'requested_role', 'student');
  school_id_value uuid;
  username_value text := btrim(coalesce(new.raw_user_meta_data ->> 'username', ''));
  full_name_value text := btrim(coalesce(new.raw_user_meta_data ->> 'full_name', ''));
begin
  if requested_role not in ('student', 'teacher', 'admin') then
    raise exception 'Unsupported account role request';
  end if;
  if username_value !~ '^[A-Z][a-zA-Z0-9]{0,49}@(Admin|teacher|Student)\.edu$' then
    raise exception 'Use a capitalized first name followed by the username suffix for the requested role';
  end if;
  if (requested_role = 'student' and username_value !~ '@Student\.edu$')
     or (requested_role = 'teacher' and username_value !~ '@teacher\.edu$')
     or (requested_role = 'admin' and username_value !~ '@Admin\.edu$') then
    raise exception 'Username suffix does not match the requested role';
  end if;
  if length(full_name_value) < 2 or length(full_name_value) > 100 then
    raise exception 'Enter a valid full name';
  end if;

  if requested_role <> 'admin' then
    school_id_value := nullif(new.raw_user_meta_data ->> 'school_id', '')::uuid;
    if school_id_value is null or not exists (
      select 1 from public.schools where id = school_id_value
    ) then
      raise exception 'Choose a valid school';
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

  return new;
end;
$$;

revoke all on function public.handle_quiz_app_user_signup() from public, anon, authenticated;
drop trigger if exists z_quiz_app_secure_profile on auth.users;
create trigger z_quiz_app_secure_profile
  after insert on auth.users
  for each row execute function public.handle_quiz_app_user_signup();

-- Provision only the matching pre-existing Supabase Auth user. No password is
-- written or changed, and neither a mismatched UID nor email can be promoted.
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
