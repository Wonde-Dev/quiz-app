import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class TeacherDashboardScreen extends ConsumerStatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  ConsumerState<TeacherDashboardScreen> createState() =>
      _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState
    extends ConsumerState<TeacherDashboardScreen> {
  int _studentCount = 0;
  int _quizCount = 0;
  int _submissionCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    final client = Supabase.instance.client;
    final user = ref.read(authStateProvider).user;

    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      var studentsQuery = client
          .from('users')
          .select('id')
          .eq('role', AppRoles.student);
      if (user.schoolId != null) {
        studentsQuery = studentsQuery.eq('school_id', user.schoolId!);
      }

      final teacherQuizzesQuery = client
          .from('quizzes')
          .select('id')
          .eq('teacher_id', user.id);

      final results = await Future.wait([
        studentsQuery,
        teacherQuizzesQuery,
      ]);

      final studentsList = results[0] as List;
      final quizzesList = results[1] as List;
      final quizIds =
          quizzesList.map((q) => q['id'] as String).toList();

      int submissionCount = 0;
      if (quizIds.isNotEmpty) {
        final submissions = await client
            .from('grades')
            .select('id')
            .inFilter('quiz_id', quizIds);
        submissionCount = (submissions as List).length;
      }

      if (!mounted) return;
      setState(() {
        _studentCount = studentsList.length;
        _quizCount = quizzesList.length;
        _submissionCount = submissionCount;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Teacher stats loading note: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = ref.watch(authStateProvider).user;
    final teacherName = currentUser?.fullName?.isNotEmpty == true
        ? currentUser!.fullName!
        : currentUser?.username ?? 'Teacher';

    return DashboardShell(
      title: 'Teacher dashboard',
      body: RefreshIndicator(
        onRefresh: _loadStats,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Welcome Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF5847D8),
                    const Color(0xFF7E6DF0),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF5847D8).withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.school_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome, $teacherName',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Create engaging quizzes & evaluate student progress',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Live metrics
            Row(
              children: [
                Expanded(
                  child: _TeacherStatCard(
                    title: 'Students',
                    value: '$_studentCount',
                    loading: _loading,
                    icon: Icons.people_outline_rounded,
                    color: const Color(0xFF5847D8),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TeacherStatCard(
                    title: 'My Quizzes',
                    value: '$_quizCount',
                    loading: _loading,
                    icon: Icons.quiz_outlined,
                    color: Colors.teal.shade700,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TeacherStatCard(
                    title: 'Submissions',
                    value: '$_submissionCount',
                    loading: _loading,
                    icon: Icons.fact_check_outlined,
                    color: Colors.indigo.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Text(
              'Teaching & Exam Actions',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // Action Tiles
            _TeacherActionTile(
              icon: Icons.add_circle_outline_rounded,
              color: const Color(0xFF5847D8),
              title: 'Prepare a Quiz',
              subtitle:
                  'Create exams choosing Grade 9 to 12 and Section A, B, C (or custom section).',
              buttonText: 'Create Quiz',
              onTap: () => context.push('/teacher/quizzes/new'),
            ),
            const SizedBox(height: 10),

            _TeacherActionTile(
              icon: Icons.fact_check_rounded,
              color: Colors.green.shade700,
              title: 'Evaluate Quizzes & Results',
              subtitle:
                  'Review student answers question-by-question, evaluate responses, and adjust scores.',
              buttonText: 'Evaluate',
              onTap: () => context.push('/teacher/results'),
            ),
            const SizedBox(height: 10),

            _TeacherActionTile(
              icon: Icons.person_add_alt_1_rounded,
              color: Colors.teal.shade700,
              title: 'Register Students',
              subtitle:
                  'Register new students in your classes and school with their temporary credentials.',
              buttonText: 'Register Students',
              onTap: () => context.push('/teacher/students'),
            ),
            const SizedBox(height: 10),

            _TeacherActionTile(
              icon: Icons.lock_reset_rounded,
              color: Colors.orange.shade800,
              title: 'Reset Student Passwords',
              subtitle:
                  'Reset student passwords with one tap. Generates new temporary credentials securely.',
              buttonText: 'Reset Password',
              onTap: () => context.push('/teacher/reset-passwords'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _TeacherStatCard extends StatelessWidget {
  const _TeacherStatCard({
    required this.title,
    required this.value,
    required this.loading,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final bool loading;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
            const SizedBox(height: 2),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeacherActionTile extends StatelessWidget {
  const _TeacherActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        onPressed: onTap,
                        child: Text(buttonText),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
