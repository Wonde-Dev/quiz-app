# Quiz App

Flutter quiz app with separate administrator, teacher, and student experiences,
using Supabase Auth and the `users`, `quizzes`, `questions`, and `grades` tables.

## Set up Supabase

1. In the Supabase SQL Editor, run `schema.sql` first and then
   `rls_policies.sql`. If not using the CLI, also apply every SQL migration in
   `supabase/migrations` in timestamp order. The schema keeps old school
   grade-level data in `school_grades` and uses `grades` for exam results.
   Back up the database before importing these files if it contains important
   data.
2. Set `SupabaseConstants` in `lib/core/constants/supabase_constants.dart` to
   the project URL and **publishable/anon** key.
3. If using the CLI, run `supabase db push` to apply the registration and
   approval migration, then deploy the functions:

   ```sh
   supabase db push
   supabase functions deploy login-by-username --no-verify-jwt
   supabase functions deploy review-account
   supabase functions deploy update-profile
   supabase functions deploy manage-account
   supabase functions deploy reset-student-password
   supabase functions deploy quiz-attempt
   ```

   `login-by-username` must have JWT verification disabled because it handles
   sign-in before a user has a session; it validates credentials through
   Supabase Auth and returns only session tokens. The other functions require
   an authenticated session and validate the caller's role themselves.
   Supabase provides the project URL and service-role secret to deployed
   functions. Never put a service-role key in the Flutter app.

New accounts requesting teacher or administrator access can use their student
profile immediately; an administrator must approve role elevation. A teacher
approval also requires the administrator to assign a school ID. The first
administrator is promoted by the schema/migration only if both the Supabase
Auth UID and email match the configured values. No password is created or
changed by the SQL.

`schema.sql` creates the Auth signup trigger and alias validation. The CLI
migration keeps that behavior aligned when applying incremental deployments.
After updating registration validation, run `supabase db push` and deploy the
updated `login-by-username` and `manage-account` functions. If registration
still fails with a generic Supabase database error, check Supabase Auth logs and
confirm that the username-format migration ran successfully; duplicate emails
and usernames are rejected.
The RLS script limits profile reads and protects role/request fields; profile
name updates and elevated-role changes are handled by authenticated server
functions. The schema exposes schools for read-only selection during sign-up,
and the Auth trigger validates the selected school.

The quiz-results screen reads `grades.incorrect_answers`. If it reports
PostgreSQL error `42703` for that column, run `supabase db push` or execute
`alter table public.grades add column if not exists incorrect_answers integer check (incorrect_answers >= 0);`
in the SQL Editor, then reload the app. The activity-history migration enables
administrators and teachers to view the shared activity feed; students see
activity involving their own account. Database triggers record profile,
account, quiz, and result changes; sign-ins and quiz starts are recorded by the
app, and account password resets are recorded by the reset function.

The sign-in screen accepts registered email addresses and usernames. New
accounts enter first and last name; usernames are generated without spaces as
`Firstnamelastname@A.edu` for administrators, `Firstnamelastname@T.edu` for
teachers, and `Firstnamelastname@S.edu` for students (for example,
`Wondeassegid@A.edu`). Aliases are unique, and the first letter is capitalized
while the remaining letters are lowercase. Existing legacy
`username@school.local`, `Name@T.edu`, and `Name@S.edu` accounts remain
supported. New profiles include a full name, unique username, email, school,
and requested role. Apply `20261018000000_role_username_format.sql` before
deploying this username format. Public teacher/admin registrations remain
approval-gated and do not grant elevated access until an administrator approves
them. Enable email confirmations in Supabase Auth. Users can
edit their name from their profile,
upload a JPG, PNG, or WebP profile photo (up to 5 MB), cycle between light,
dark, and system themes, and review their recent actions under **Activity** in
the navigation menu.

Students may self-register. Teachers can register and delete students in their
own school; administrators can create student, teacher, and administrator
accounts and delete student or teacher accounts. These operations use the
`manage-account` Edge Function, which checks the authenticated caller's role
and school before using the Supabase service role. Do not grant app clients
direct access to Supabase Auth administration.

The `20261017020000_grade_section_enrollment.sql` migration seeds Grades 9–12
and sections A, B, and C for every school. Student self-registration and
teacher-created student accounts must select one of those sections. Admins can
add more sections from **Classes and teacher assignments**; quizzes can target a
section, and both the quiz API and database policies restrict access to its
enrolled students. Migration `20261017040000_signup_class_lookup_access.sql`
allows signed-out users to read school grade and section choices needed by the
registration form; it does not grant access to account or quiz data. Apply all
pending migrations with `supabase db push` before deploying the updated app.

Administrators assign each teacher a subject and grade/section from **Classes
and teacher assignments**. Teachers can create quizzes only for their assigned
subject/section; this is enforced by database row-level security as well as the
quiz builder. Migration `20261017030000_teacher_assignments_and_result_counts.sql`
also stores the number of incorrect answers with each new quiz result. Older
results have no incorrect-answer count.
After applying this migration, redeploy `quiz-attempt` so new results include
the incorrect-answer count.

Administrators and teachers can change their own password from **My profile**.
The app verifies the current password before saving the new one; administrators
can also reset other users' passwords from account management.

The `profile-photos` public bucket stores public profile images. Uploads are
limited to each authenticated user's own storage folder; the `update-profile`
Edge Function validates the uploaded object before recording its public URL.

Password resets are performed by `reset-student-password`. It verifies the
current user's administrator/teacher role, restricts teachers to students in
their school, generates a temporary password, and marks the account to require
a password change. Generated values are returned only to the authorized
teacher/administrator for one-at-a-time or bulk sharing.

Quiz authors can publish multiple-choice, true/false, and fill-in-the-blank
questions with optional explanations. Teachers and administrators can review
the automatically calculated quiz results from their dashboards. Administrator
quizzes are available to students across schools; teacher quizzes are limited
to students in the teacher's school.

Students start and submit exams through `quiz-attempt`. Correct answers stay on
the server, scores are calculated there, and the resulting grade is returned to
the student. The app enables screenshot and screen-recording protections
across Android and iOS, and refuses to show its UI if native protection cannot
be enabled. Android's secure-window flag blocks system screenshots and most
recording; iOS uses the native screen-guard overlay and recording detection.
No app can prevent external cameras or guarantee capture blocking on rooted,
jailbroken, or modified devices. Web and desktop builds do not provide this
native protection.

Keep the `users`, `quizzes`, `questions`, and `grades` RLS policies enabled;
the Edge Functions use the server-side service-role secret only after
validating the caller.
