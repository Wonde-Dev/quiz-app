begin;

grant select on public.school_grades, public.sections to anon;

drop policy if exists school_grades_read_for_registration
  on public.school_grades;
create policy school_grades_read_for_registration
  on public.school_grades for select to anon
  using (true);

drop policy if exists sections_read_for_registration
  on public.sections;
create policy sections_read_for_registration
  on public.sections for select to anon
  using (true);

commit;
