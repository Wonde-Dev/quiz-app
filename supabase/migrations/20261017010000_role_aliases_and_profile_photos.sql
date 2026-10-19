begin;

create schema if not exists private;
revoke all on schema private from public, anon;

create or replace function private.app_student_can_access_quiz(quiz_owner_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.users as student
    join public.users as quiz_owner on quiz_owner.id = quiz_owner_id
    where student.id = (select auth.uid())
      and student.role = 'student'
      and (
        quiz_owner.role = 'admin'
        or (
          quiz_owner.role = 'teacher'
          and quiz_owner.school_id = student.school_id
        )
      )
  )
$$;
revoke all on function private.app_student_can_access_quiz(uuid)
  from public, anon, authenticated;
grant usage on schema private to authenticated;
grant execute on function private.app_student_can_access_quiz(uuid)
  to authenticated;

update public.users as admin_user
set username = 'Wondev@Admin.edu'
where admin_user.id = 'bf883616-97a1-4797-8455-1d8df34917fa'::uuid
  and lower(admin_user.email) = 'wondedev369@gmail.com'
  and admin_user.role = 'admin'
  and lower(admin_user.username) = 'wondedev369@t.edu'
  and not exists (
    select 1
    from public.users as existing_user
    where lower(existing_user.username) = lower('Wondev@Admin.edu')
      and existing_user.id <> admin_user.id
  );

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

drop policy if exists profile_photos_public_read on storage.objects;
create policy profile_photos_public_read
  on storage.objects for select to public
  using (bucket_id = 'profile-photos');

drop policy if exists profile_photos_upload_own on storage.objects;
create policy profile_photos_upload_own
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists profile_photos_update_own on storage.objects;
create policy profile_photos_update_own
  on storage.objects for update to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists profile_photos_delete_own on storage.objects;
create policy profile_photos_delete_own
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists quizzes_students_read_published_same_school
  on public.quizzes;
create policy quizzes_students_read_published_same_school
  on public.quizzes for select to authenticated
  using (
    (select private.app_current_role()) = 'student'
    and is_published
    and (select private.app_student_can_access_quiz(teacher_id))
  );

commit;
