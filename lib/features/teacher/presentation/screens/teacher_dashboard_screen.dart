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
    extends ConsumerState<TeacherDashboardScreen>
    with SingleTickerProviderStateMixin {
  int _studentCount = 0;
  int _quizCount = 0;
  int _submissionCount = 0;
  List<Map<String, dynamic>> _myQuizzes = [];
  bool _loading = true;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _loadStats();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
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
          .select('id, title, description, time_limit_minutes, total_points, is_published, created_at')
          .eq('teacher_id', user.id)
          .order('created_at', ascending: false);

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
        _myQuizzes = List<Map<String, dynamic>>.from(quizzesList);
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
    final isDark = theme.brightness == Brightness.dark;
    final currentUser = ref.watch(authStateProvider).user;
    final teacherName = currentUser?.fullName?.isNotEmpty == true
        ? currentUser!.fullName!
        : currentUser?.username ?? 'Teacher';

    return DashboardShell(
      title: 'Teacher Control Center',
      body: RefreshIndicator(
        onRefresh: _loadStats,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Welcome Header - Crisp White Aesthetic
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.3)
                        : const Color(0xFF0F172A).withValues(alpha: 0.05),
                    blurRadius: 26,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Active Pulse Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF475569)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, _) => Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF10B981).withValues(
                                        alpha: 0.3 + (_pulseController.value * 0.5),
                                      ),
                                      blurRadius: 6,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'TEACHER PORTAL · ACTIVE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      IconButton.filledTonal(
                        tooltip: 'Refresh teaching stats',
                        onPressed: _loading ? null : _loadStats,
                        icon: _loading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh_rounded, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF0F172A)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: const Icon(
                          Icons.school_rounded,
                          color: Color(0xFF10B981),
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome, $teacherName',
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Create engaging quizzes, evaluate submissions, and guide student success.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                        label: const Text('Prepare New Quiz'),
                        onPressed: () => context.push('/teacher/quizzes/new'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(
                            color: isDark
                                ? const Color(0xFF475569)
                                : const Color(0xFFCBD5E1),
                          ),
                        ),
                        icon: const Icon(Icons.fact_check_rounded, size: 18),
                        label: const Text('Evaluate Submissions'),
                        onPressed: () => context.push('/teacher/results'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Live metrics
            Text(
              'Classroom Overview',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _TeacherStatCard(
                    title: 'Students',
                    value: '$_studentCount',
                    loading: _loading,
                    icon: Icons.school_rounded,
                    color: const Color(0xFF6366F1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TeacherStatCard(
                    title: 'My Quizzes',
                    value: '$_quizCount',
                    loading: _loading,
                    icon: Icons.quiz_rounded,
                    color: const Color(0xFF10B981),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TeacherStatCard(
                    title: 'Submissions',
                    value: '$_submissionCount',
                    loading: _loading,
                    icon: Icons.fact_check_rounded,
                    color: const Color(0xFF8B5CF6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Text(
              'Teaching & Exam Actions',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),

            // Action Tiles
            _TeacherActionTile(
              icon: Icons.add_circle_outline_rounded,
              color: const Color(0xFF8B5CF6),
              title: 'Prepare a Quiz',
              subtitle:
                  'Create exams choosing Grade 9 to 12 and Section A, B, C (or custom section).',
              buttonText: 'Create Quiz',
              onTap: () => context.push('/teacher/quizzes/new'),
            ),
            const SizedBox(height: 10),

            _TeacherActionTile(
              icon: Icons.fact_check_rounded,
              color: const Color(0xFF10B981),
              title: 'Evaluate Quizzes & Results',
              subtitle:
                  'Review student answers question-by-question, evaluate responses, inspect images, and adjust scores.',
              buttonText: 'Evaluate',
              onTap: () => context.push('/teacher/results'),
            ),
            const SizedBox(height: 10),

            _TeacherActionTile(
              icon: Icons.person_add_alt_1_rounded,
              color: const Color(0xFF6366F1),
              title: 'Register Students',
              subtitle:
                  'Register new students in your classes and school with their temporary credentials and auto-password formula.',
              buttonText: 'Register Students',
              onTap: () => context.push('/teacher/students'),
            ),
            const SizedBox(height: 10),

            _TeacherActionTile(
              icon: Icons.lock_reset_rounded,
              color: const Color(0xFFF59E0B),
              title: 'Reset Student Passwords',
              subtitle:
                  'Reset student passwords with one tap. Generates new temporary credentials securely (Student1@S.edu).',
              buttonText: 'Reset Password',
              onTap: () => context.push('/teacher/reset-passwords'),
            ),
            const SizedBox(height: 28),

            // Quizzes List Section
            Row(
              children: [
                Icon(
                  Icons.quiz_rounded,
                  color: const Color(0xFF8B5CF6),
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'My Prepared Quizzes',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => context.push('/teacher/quizzes/new'),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('New Quiz'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_myQuizzes.isEmpty)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.quiz_outlined,
                          size: 40,
                          color: isDark ? Colors.white38 : Colors.grey,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No quizzes prepared yet',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Prepare your first quiz with custom questions, diagrams, and section targeting.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => context.push('/teacher/quizzes/new'),
                          icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                          label: const Text('Prepare New Quiz'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              for (final quiz in _myQuizzes)
                _TeacherQuizCard(
                  quiz: quiz,
                  isDark: isDark,
                  onEvaluate: () => context.push('/teacher/results'),
                  onPreview: () => context.push('/student/quiz/${quiz['id']}'),
                ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _TeacherQuizCard extends StatelessWidget {
  const _TeacherQuizCard({
    required this.quiz,
    required this.isDark,
    required this.onEvaluate,
    required this.onPreview,
  });

  final Map<String, dynamic> quiz;
  final bool isDark;
  final VoidCallback onEvaluate;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = quiz['title'] as String? ?? 'Untitled Quiz';
    final desc = quiz['description'] as String? ?? '';
    final timeLimit = quiz['time_limit_minutes'] as int? ?? 30;
    final totalPoints = quiz['total_points'] as int? ?? 0;
    final isPublished = quiz['is_published'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isPublished
                      ? const Color(0xFF10B981).withValues(alpha: 0.12)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isPublished
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isPublished ? 'Published' : 'Draft',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isPublished
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              desc,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 14, color: isDark ? Colors.white60 : Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                '$timeLimit mins',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.grey.shade700,
                ),
              ),
              const SizedBox(width: 14),
              Icon(Icons.format_list_numbered_rounded, size: 14, color: isDark ? Colors.white60 : Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                '$totalPoints questions/points',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onPreview,
                icon: const Icon(Icons.visibility_outlined, size: 14),
                label: const Text('Preview', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onEvaluate,
                icon: const Icon(Icons.fact_check_rounded, size: 14),
                label: const Text('Evaluate', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
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
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 10),
          loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
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
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
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
                  child: Icon(icon, color: color, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        onPressed: onTap,
                        child: Text(buttonText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
