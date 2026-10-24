begin;

-- 1. Ensure all metadata columns exist on public.users
alter table public.users add column if not exists requested_class text;
alter table public.users add column if not exists requested_grade text;
alter table public.users add column if not exists requested_subject text;
alter table public.users add column if not exists section_id uuid;

-- 2. Grant table permissions to authenticated role on public.users
grant select, insert, update, delete on public.users to authenticated;
grant select on public.users to anon;

-- 3. Dedicated security definer RPC function to update own user profile safely
create or replace function public.update_own_profile(
  p_full_name text default null,
  p_avatar_url text default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'auth', 'pg_temp'
as $$
declare
  caller_id uuid := auth.uid();
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.users
  set
    full_name = coalesce(nullif(trim(p_full_name), ''), full_name),
    avatar_url = coalesce(nullif(trim(p_avatar_url), ''), avatar_url)
  where id = caller_id;

  -- Sync full_name into auth.users metadata if provided
  if p_full_name is not null and length(trim(p_full_name)) > 0 then
    update auth.users
    set raw_user_meta_data = raw_user_meta_data || jsonb_build_object('full_name', trim(p_full_name))
    where id = caller_id;
  end if;

  return jsonb_build_object('success', true);
end;
$$;

grant execute on function public.update_own_profile(text, text) to authenticated;

-- 4. Ensure course_resources table exists with full permissions
create table if not exists public.course_resources (
  id text primary key,
  title text not null,
  description text,
  file_name text not null,
  file_url text not null,
  file_type text not null default 'pdf',
  file_size integer not null default 0,
  school_id uuid references public.schools(id) on delete set null,
  teacher_id text not null,
  teacher_name text not null,
  target_grade text not null,
  target_section text not null,
  created_at timestamp with time zone not null default now()
);

alter table public.course_resources enable row level security;

grant select, insert, update, delete on public.course_resources to authenticated;

drop policy if exists course_resources_select_all on public.course_resources;
create policy course_resources_select_all
  on public.course_resources for select to authenticated
  using (true);

drop policy if exists course_resources_teacher_insert on public.course_resources;
create policy course_resources_teacher_insert
  on public.course_resources for insert to authenticated
  with check (true);

drop policy if exists course_resources_teacher_delete on public.course_resources;
create policy course_resources_teacher_delete
  on public.course_resources for delete to authenticated
  using (
    teacher_id = (select auth.uid())::text
    or (select role from public.users where id = auth.uid()) = 'admin'
  );

-- 5. Ensure course-materials storage bucket exists
insert into storage.buckets (id, name, public)
values ('course-materials', 'course-materials', true)
on conflict (id) do nothing;

drop policy if exists course_materials_bucket_public on storage.objects;
create policy course_materials_bucket_public
  on storage.objects for select
  using (bucket_id = 'course-materials');

drop policy if exists course_materials_bucket_auth_insert on storage.objects;
create policy course_materials_bucket_auth_insert
  on storage.objects for insert to authenticated
  with check (bucket_id = 'course-materials');

-- 6. Reload PostgREST schema cache
notify pgrst, 'reload schema';

commit;

