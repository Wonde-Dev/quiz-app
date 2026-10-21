import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/shared/widgets/dashboard_welcome_banner.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class StudentDashboardScreen extends ConsumerWidget {
  const StudentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    return DashboardShell(
      title: 'Student dashboard',
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : _StudentQuizList(studentId: user.id),
    );
  }
}

class _StudentQuizList extends StatefulWidget {
  const _StudentQuizList({required this.studentId});

  final String studentId;

  @override
  State<_StudentQuizList> createState() => _StudentQuizListState();
}

class _StudentQuizListState extends State<_StudentQuizList> {
  late Future<
    ({
      List<Map<String, dynamic>> quizzes,
      List<Map<String, dynamic>> grades,
      List<Map<String, dynamic>> enrolledSections,
    })
  >
  _dashboard;

  @override
  void initState() {
    super.initState();
    _dashboard = _loadDashboard();
  }

  Future<
    ({
      List<Map<String, dynamic>> quizzes,
      List<Map<String, dynamic>> grades,
      List<Map<String, dynamic>> enrolledSections,
    })
  >
  _loadDashboard() async {
    final client = Supabase.instance.client;

    final responses = await Future.wait([
      // 1. Quizzes
      client
          .from('quizzes')
          .select(
            'id, title, description, time_limit_minutes, total_points, section_id, '
            'section:sections(id, name, school_grades(name))',
          )
          .eq('is_published', true)
          .order('created_at', ascending: false),

      // 2. Grades
      client
          .from('grades')
          .select('quiz_id, score, total_points, percentage, passed, submitted_at')
          .eq('student_id', widget.studentId)
          .order('submitted_at', ascending: false),

      // 3. Enrolled Sections
      client
          .from('student_sections')
          .select('section_id, section:sections(id, name, school_grades(name))')
          .eq('student_id', widget.studentId),
    ]);

    return (
      quizzes: List<Map<String, dynamic>>.from(responses[0]),
      grades: List<Map<String, dynamic>>.from(responses[1]),
      enrolledSections: List<Map<String, dynamic>>.from(responses[2]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () async => setState(() => _dashboard = _loadDashboard()),
      child: FutureBuilder<
        ({
          List<Map<String, dynamic>> quizzes,
          List<Map<String, dynamic>> grades,
          List<Map<String, dynamic>> enrolledSections,
        })
      >(
        future: _dashboard,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Could not load quizzes and results: ${snapshot.error}',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _dashboard = _loadDashboard()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final result = snapshot.data!;
          final quizTitles = {
            for (final quiz in result.quizzes)
              quiz['id'] as String: quiz['title'] as String? ?? 'Quiz',
          };

          final gradesByQuiz = <String, Map<String, dynamic>>{};
          for (final grade in result.grades) {
            gradesByQuiz.putIfAbsent(
              grade['quiz_id'] as String,
              () => grade,
            );
          }

          final studentSectionIds = result.enrolledSections
              .map((s) => s['section_id'] as String?)
              .whereType<String>()
              .toSet();

          // Section labels
          final sectionLabels = result.enrolledSections.map((s) {
            final sec = s['section'] as Map<String, dynamic>?;
            final g = sec?['school_grades'] as Map<String, dynamic>?;
            final gName = g?['name'] as String? ?? '';
            final sName = sec?['name'] as String? ?? '';
            return gName.isNotEmpty ? '$gName · $sName' : sName;
          }).where((l) => l.isNotEmpty).toList();

          final enrolledLabel = sectionLabels.isNotEmpty
              ? sectionLabels.join(', ')
              : 'Enrolled Student';

          // Quizzes partition
          final availableQuizzes = result.quizzes
              .where((q) => !gradesByQuiz.containsKey(q['id']))
              .toList();
          final submittedGrades = result.grades;

          // Stats
          final totalCompleted = submittedGrades.length;
          final passedCount =
              submittedGrades.where((g) => g['passed'] == true).length;
          final avgScore = totalCompleted > 0
              ? (submittedGrades.fold<num>(
                          0, (sum, g) => sum + (g['percentage'] as num? ?? 0)) /
                      totalCompleted)
                  .round()
              : 0;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DashboardWelcomeBanner(
                subtitle:
                    'Welcome! Ready for your next exam in $enrolledLabel?',
              ),
              const SizedBox(height: 16),

              // Student Progress Stats Row
              Row(
                children: [
                  Expanded(
                    child: _StudentStatCard(
                      label: 'Completed',
                      value: '$totalCompleted',
                      icon: Icons.task_alt_rounded,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StudentStatCard(
                      label: 'Average',
                      value: '$avgScore%',
                      icon: Icons.insights_rounded,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StudentStatCard(
                      label: 'Passed',
                      value: '$passedCount',
                      icon: Icons.military_tech_rounded,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Available Exams
              Row(
                children: [
                  Icon(
                    Icons.play_circle_outline_rounded,
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Available Quizzes & Exams',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (availableQuizzes.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 44,
                            color: Colors.green.shade600,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'You’re all caught up!',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'There are no new published quizzes waiting for you right now.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                for (final quiz in availableQuizzes) ...[
                  _QuizCard(
                    quiz: quiz,
                    isForStudentSection: quiz['section_id'] == null ||
                        studentSectionIds.contains(quiz['section_id']),
                    onStart: () =>
                        context.push('/student/quiz/${quiz['id']}'),
                  ),
                  const SizedBox(height: 10),
                ],

              const SizedBox(height: 28),

              // My Results Section
              Row(
                children: [
                  Icon(
                    Icons.history_edu_rounded,
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'My Exam Results',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (submittedGrades.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No submitted quiz results yet. Once you complete a quiz, your score and evaluation will show here.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                )
              else
                for (final grade in submittedGrades)
                  _GradeResultTile(
                    grade: grade,
                    title: quizTitles[grade['quiz_id']] ?? 'Quiz Result',
                  ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }
}

class _StudentStatCard extends StatelessWidget {
  const _StudentStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
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
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
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

class _QuizCard extends StatelessWidget {
  const _QuizCard({
    required this.quiz,
    required this.isForStudentSection,
    required this.onStart,
  });

  final Map<String, dynamic> quiz;
  final bool isForStudentSection;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = quiz['title'] as String? ?? 'Quiz';
    final desc = quiz['description'] as String? ?? '';
    final timeLimit = quiz['time_limit_minutes'] as int?;
    final totalPoints = quiz['total_points'] as int? ?? 0;

    final sec = quiz['section'] as Map<String, dynamic>?;
    final g = sec?['school_grades'] as Map<String, dynamic>?;
    final gName = g?['name'] as String? ?? '';
    final sName = sec?['name'] as String? ?? '';
    final classLabel = gName.isNotEmpty ? '$gName · $sName' : sName;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                    ),
                  ),
                ),
                if (classLabel.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isForStudentSection
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      classLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isForStudentSection
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                desc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  timeLimit != null ? '$timeLimit mins' : 'No time limit',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(width: 14),
                Icon(
                  Icons.quiz_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '$totalPoints points',
                  style: theme.textTheme.bodySmall,
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Take Exam'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GradeResultTile extends StatelessWidget {
  const _GradeResultTile({required this.grade, required this.title});

  final Map<String, dynamic> grade;
  final String title;

  @override
  Widget build(BuildContext context) {
    final passed = grade['passed'] == true;
    final score = grade['score'] ?? 0;
    final total = grade['total_points'] ?? 0;
    final percentage = grade['percentage'] ?? 0;

    final dateStr = DateTime.tryParse(grade['submitted_at'] as String? ?? '')
            ?.toLocal()
            .toString()
            .split('.')
            .first ??
        'Submitted';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: passed
              ? Colors.green.withValues(alpha: 0.15)
              : Colors.orange.withValues(alpha: 0.15),
          child: Icon(
            passed ? Icons.check_circle : Icons.rule_rounded,
            color: passed ? Colors.green.shade700 : Colors.orange.shade800,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('Score: $score / $total ($percentage%) · $dateStr'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: passed
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: passed ? Colors.green : Colors.red,
              width: 1,
            ),
          ),
          child: Text(
            passed ? 'Passed' : 'Failed',
            style: TextStyle(
              color: passed ? Colors.green.shade800 : Colors.red.shade800,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
