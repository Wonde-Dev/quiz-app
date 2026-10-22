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
      Map<String, dynamic>? studentProfile,
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
      Map<String, dynamic>? studentProfile,
    })
  >
  _loadDashboard() async {
    final client = Supabase.instance.client;

    // 1. Quizzes with resilient fallback and targeting columns
    List<Map<String, dynamic>> quizzes = [];
    try {
      final res = await client
          .from('quizzes')
          .select(
            'id, title, description, time_limit_minutes, total_points, section_id, target_grade, target_section, '
            'section:sections(id, name, grade, grade_id, school_grades(name))',
          )
          .eq('is_published', true)
          .order('created_at', ascending: false);
      quizzes = List<Map<String, dynamic>>.from(res);
    } catch (_) {
      try {
        final res = await client
            .from('quizzes')
            .select(
              'id, title, description, time_limit_minutes, total_points, section_id',
            )
            .eq('is_published', true)
            .order('created_at', ascending: false);
        quizzes = List<Map<String, dynamic>>.from(res);
      } catch (e) {
        debugPrint('Student quizzes load fallback error: $e');
      }
    }

    // 2. Grades
    List<Map<String, dynamic>> grades = [];
    try {
      final res = await client
          .from('grades')
          .select('quiz_id, score, total_points, percentage, passed, submitted_at')
          .eq('student_id', widget.studentId)
          .order('submitted_at', ascending: false);
      grades = List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('Student grades load error: $e');
    }

    // 3. Enrolled Sections
    List<Map<String, dynamic>> enrolledSections = [];
    try {
      final res = await client
          .from('student_sections')
          .select('section_id, section:sections(id, name, school_grades(name))')
          .eq('student_id', widget.studentId);
      enrolledSections = List<Map<String, dynamic>>.from(res);
    } catch (_) {
      try {
        final res = await client
            .from('student_sections')
            .select('section_id')
            .eq('student_id', widget.studentId);
        enrolledSections = List<Map<String, dynamic>>.from(res);
      } catch (e) {
        debugPrint('Student sections load fallback error: $e');
      }
    }

    // 4. Student profile metadata (requested_grade and requested_class)
    Map<String, dynamic>? studentProfile;
    try {
      final res = await client
          .from('users')
          .select('id, school_id, requested_grade, requested_class')
          .eq('id', widget.studentId)
          .maybeSingle();
      studentProfile = res;
    } catch (e) {
      debugPrint('Student profile load note: $e');
    }

    return (
      quizzes: quizzes,
      grades: grades,
      enrolledSections: enrolledSections,
      studentProfile: studentProfile,
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
          Map<String, dynamic>? studentProfile,
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

          // Collect Student's grade and section identifiers
          final studentGradeNames = <String>{};
          final studentSectionNames = <String>{};

          for (final s in result.enrolledSections) {
            final sec = s['section'] as Map<String, dynamic>?;
            final g = sec?['school_grades'] as Map<String, dynamic>?;
            final gName = g?['name'] as String?;
            final sName = sec?['name'] as String?;
            final secGrade = sec?['grade'] as String?;
            if (gName != null && gName.trim().isNotEmpty) {
              studentGradeNames.add(gName.trim().toLowerCase());
            }
            if (secGrade != null && secGrade.trim().isNotEmpty) {
              studentGradeNames.add('grade ${secGrade.trim()}'.toLowerCase());
              studentGradeNames.add(secGrade.trim().toLowerCase());
            }
            if (sName != null && sName.trim().isNotEmpty) {
              studentSectionNames.add(sName.trim().toLowerCase());
            }
          }

          final profGrade = result.studentProfile?['requested_grade'] as String?;
          final profClass = result.studentProfile?['requested_class'] as String?;
          if (profGrade != null && profGrade.trim().isNotEmpty) {
            studentGradeNames.add(profGrade.trim().toLowerCase());
          }
          if (profClass != null && profClass.trim().isNotEmpty) {
            studentSectionNames.add(profClass.trim().toLowerCase());
          }

          // Section labels
          final sectionLabels = result.enrolledSections.map((s) {
            final sec = s['section'] as Map<String, dynamic>?;
            final g = sec?['school_grades'] as Map<String, dynamic>?;
            final gName = g?['name'] as String? ?? '';
            final sName = sec?['name'] as String? ?? '';
            return gName.isNotEmpty ? '$gName · $sName' : sName;
          }).where((l) => l.isNotEmpty).toList();

          if (sectionLabels.isEmpty && (profGrade != null || profClass != null)) {
            final gStr = profGrade ?? '';
            final cStr = profClass ?? '';
            if (gStr.isNotEmpty && cStr.isNotEmpty) {
              sectionLabels.add('$gStr · $cStr');
            } else if (gStr.isNotEmpty) {
              sectionLabels.add(gStr);
            } else if (cStr.isNotEmpty) {
              sectionLabels.add(cStr);
            }
          }

          final enrolledLabel = sectionLabels.isNotEmpty
              ? sectionLabels.join(', ')
              : 'Enrolled Student';

          // Strictly filter quizzes for this student's grade and class/section
          final availableQuizzes = result.quizzes.where((quiz) {
            // Exclude already submitted quizzes
            if (gradesByQuiz.containsKey(quiz['id'])) return false;

            final quizSectionId = quiz['section_id'] as String?;
            final quizTargetGrade = (quiz['target_grade'] as String?)?.trim().toLowerCase();
            final quizTargetSection = (quiz['target_section'] as String?)?.trim().toLowerCase();

            // Match directly by enrolled section ID
            if (quizSectionId != null && studentSectionIds.contains(quizSectionId)) {
              return true;
            }

            final sec = quiz['section'] as Map<String, dynamic>?;
            final g = sec?['school_grades'] as Map<String, dynamic>?;
            final qGradeName = ((g?['name'] ?? quizTargetGrade) as String?)?.trim().toLowerCase();
            final qSecName = ((sec?['name'] ?? quizTargetSection) as String?)?.trim().toLowerCase();

            // When quiz has target grade or section metadata
            if (qGradeName != null && qGradeName.isNotEmpty) {
              if (studentGradeNames.isNotEmpty) {
                final gradeMatches = studentGradeNames.any((sg) =>
                    sg == qGradeName ||
                    sg.replaceAll('grade', '').trim() == qGradeName.replaceAll('grade', '').trim());

                if (!gradeMatches) return false;

                if (qSecName != null && qSecName.isNotEmpty && studentSectionNames.isNotEmpty) {
                  final sectionMatches = studentSectionNames.any((sn) =>
                      sn == qSecName ||
                      sn.replaceAll('section', '').trim() == qSecName.replaceAll('section', '').trim());
                  if (!sectionMatches) return false;
                }

                return true;
              }
            }

            // General school quiz with no specific section/grade constraint
            if (quizSectionId == null && (quizTargetGrade == null || quizTargetGrade.isEmpty)) {
              return true;
            }

            return false;
          }).toList();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = passed ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    final dateStr = DateTime.tryParse(grade['submitted_at'] as String? ?? '')
            ?.toLocal()
            .toString()
            .split('.')
            .first ??
        'Submitted';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          // Prominent percentage score gauge
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor.withValues(alpha: 0.12),
              border: Border.all(color: statusColor, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              '$percentage%',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: statusColor,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  'Score: $score out of $total points ($percentage%)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: statusColor.withValues(alpha: 0.5)),
            ),
            child: Text(
              passed ? 'PASSED' : 'FAILED',
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w900,
                fontSize: 11,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
