-- Migration: 20261029050000_ciro_high_school_name_and_cleanup.sql
-- Description: Sets the school name to "Ciro High School" and removes any obsolete school rows.

begin;

update public.schools
set name = 'Ciro High School',
    is_active = true
where id = '00000000-0000-4000-8000-000000000001';

-- Reassign any remaining records to Ciro High School
update public.users
set school_id = '00000000-0000-4000-8000-000000000001'
where school_id is null or school_id <> '00000000-0000-4000-8000-000000000001';

update public.courses
set school_id = '00000000-0000-4000-8000-000000000001'
where school_id is null or school_id <> '00000000-0000-4000-8000-000000000001';

update public.sections
set school_id = '00000000-0000-4000-8000-000000000001'
where school_id is null or school_id <> '00000000-0000-4000-8000-000000000001';

update public.school_grades
set school_id = '00000000-0000-4000-8000-000000000001'
where school_id is null or school_id <> '00000000-0000-4000-8000-000000000001';

update public.quizzes
set school_id = '00000000-0000-4000-8000-000000000001'
where school_id is null or school_id <> '00000000-0000-4000-8000-000000000001';

update public.course_resources
set school_id = '00000000-0000-4000-8000-000000000001'
where school_id is null or school_id <> '00000000-0000-4000-8000-000000000001';

-- Clean up any other schools
delete from public.schools
where id <> '00000000-0000-4000-8000-000000000001';

commit;

