import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/services/announcement_service.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/shared/models/school_announcement.dart';
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

class _StudentQuizList extends ConsumerStatefulWidget {
  const _StudentQuizList({required this.studentId});

  final String studentId;

  @override
  ConsumerState<_StudentQuizList> createState() => _StudentQuizListState();
}

class _StudentQuizListState extends ConsumerState<_StudentQuizList> {
  late Future<
    ({
      List<Map<String, dynamic>> quizzes,
      List<Map<String, dynamic>> grades,
      List<Map<String, dynamic>> enrolledSections,
      Map<String, dynamic>? studentProfile,
      List<SchoolAnnouncement> announcements,
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
      List<SchoolAnnouncement> announcements,
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

    // 4. Student profile metadata (assigned_grade, assigned_class, requested_grade, requested_class)
    Map<String, dynamic>? studentProfile;
    try {
      final res = await client
          .from('users')
          .select('id, school_id, assigned_grade, assigned_class, requested_grade, requested_class')
          .eq('id', widget.studentId)
          .maybeSingle();
      studentProfile = res;
    } catch (e) {
      // Fallback: query without assigned_class if column is not yet migrated
      try {
        final res = await client
            .from('users')
            .select('id, school_id, requested_grade, requested_class')
            .eq('id', widget.studentId)
            .maybeSingle();
        studentProfile = res;
      } catch (_) {
        debugPrint('Student profile load note: $e');
      }
    }

    // 5. School Announcements with notification preference filtering
    List<SchoolAnnouncement> announcements = [];
    try {
      final fetched = await AnnouncementService().fetchAnnouncements(
        schoolId: (studentProfile?['school_id'] as String?) ?? AnnouncementService.ciroSchoolId,
      );
      final currentUser = ref.read(authStateProvider).user;
      final allowAdmin = currentUser?.allowAdminNotifications ?? (studentProfile?['allow_admin_notifications'] as bool? ?? true);
      final allowDirector = currentUser?.allowDirectorNotifications ?? (studentProfile?['allow_director_notifications'] as bool? ?? true);

      announcements = fetched.where((ann) {
        final r = ann.authorRole.toLowerCase();
        if (r.contains('admin')) {
          if (!allowAdmin) return false;
        }
        if (r.contains('director') || r.contains('subadmin')) {
          if (!allowDirector) return false;
        }
        final target = ann.targetAudience.toLowerCase();
        if (target != 'all' && !target.contains('student')) {
          return false;
        }
        return true;
      }).toList();
    } catch (e) {
      debugPrint('Student announcements load note: $e');
    }

    return (
      quizzes: quizzes,
      grades: grades,
      enrolledSections: enrolledSections,
      studentProfile: studentProfile,
      announcements: announcements,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(authStateProvider).user;
    final studentName = user?.fullName?.isNotEmpty == true
        ? user!.fullName!
        : user?.username ?? 'Student';

    return RefreshIndicator(
      onRefresh: () async {
        final future = _loadDashboard();
        setState(() {
          _dashboard = future;
        });
        await future;
      },
      child: FutureBuilder<
        ({
          List<Map<String, dynamic>> quizzes,
          List<Map<String, dynamic>> grades,
          List<Map<String, dynamic>> enrolledSections,
          Map<String, dynamic>? studentProfile,
          List<SchoolAnnouncement> announcements,
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
                  onPressed: () {
                    setState(() {
                      _dashboard = _loadDashboard();
                    });
                  },
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

          final profGrade = (result.studentProfile?['assigned_grade'] ??
                  result.studentProfile?['requested_grade'] ??
                  user?.assignedGrade) as String?;
          final profClass = (result.studentProfile?['assigned_class'] ??
                  result.studentProfile?['requested_class'] ??
                  user?.assignedClass) as String?;
          if (profGrade != null && profGrade.trim().isNotEmpty) {
            studentGradeNames.add(profGrade.trim().toLowerCase());
            studentGradeNames.add(profGrade.replaceAll('Grade', '').trim().toLowerCase());
          }
          if (profClass != null && profClass.trim().isNotEmpty) {
            studentSectionNames.add(profClass.trim().toLowerCase());
            studentSectionNames.add(profClass.replaceAll('Section', '').replaceAll('Class', '').trim().toLowerCase());
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
                title: 'Welcome, $studentName',
                badgeText: 'STUDENT PORTAL',
                subtitle:
                    'Ready for your next assessment in $enrolledLabel? Complete active quizzes and access worksheets below.',
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
              const SizedBox(height: 16),

              // Worksheets Banner Card
              Card(
                color: const Color(0xFFF0FDF4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFBBF7D0)),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: Color(0xFF10B981),
                    ),
                  ),
                  title: const Text(
                    'Class Worksheets & Exam PDFs',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Study worksheets and exam question papers from your teachers',
                    style: TextStyle(fontSize: 12, color: Color(0xFF047857)),
                  ),
                  trailing: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: () => context.push('/resources'),
                    child: const Text('View PDFs'),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Official School Announcements & Notifications
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: theme.brightness == Brightness.dark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.brightness == Brightness.dark
                          ? Colors.black.withValues(alpha: 0.2)
                          : const Color(0xFF0F172A).withValues(alpha: 0.04),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.campaign_rounded, color: Color(0xFF6366F1), size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Official School Notices',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                              Text(
                                'Direct from Super Admin & School Directorate',
                                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Notification Preferences',
                          icon: const Icon(Icons.tune_rounded, size: 20, color: Color(0xFF6366F1)),
                          onPressed: () => context.push('/profile'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Notification preference status indicator
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: theme.brightness == Brightness.dark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.brightness == Brightness.dark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                user?.allowAdminNotifications == true
                                    ? Icons.check_circle_rounded
                                    : Icons.do_not_disturb_on_rounded,
                                size: 13,
                                color: user?.allowAdminNotifications == true
                                    ? const Color(0xFF10B981)
                                    : Colors.orange,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                user?.allowAdminNotifications == true ? 'Admin: On' : 'Admin: Muted',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: user?.allowAdminNotifications == true
                                      ? const Color(0xFF10B981)
                                      : Colors.orange,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(
                                user?.allowDirectorNotifications == true
                                    ? Icons.check_circle_rounded
                                    : Icons.do_not_disturb_on_rounded,
                                size: 13,
                                color: user?.allowDirectorNotifications == true
                                    ? const Color(0xFF10B981)
                                    : Colors.orange,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                user?.allowDirectorNotifications == true ? 'Director: On' : 'Director: Muted',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: user?.allowDirectorNotifications == true
                                      ? const Color(0xFF10B981)
                                      : Colors.orange,
                                ),
                              ),
                            ],
                          ),
                          InkWell(
                            onTap: () => context.push('/profile'),
                            child: const Text(
                              'Settings',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6366F1),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (result.announcements.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.brightness == Brightness.dark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          (user?.allowAdminNotifications == false && user?.allowDirectorNotifications == false)
                              ? 'Admin & Director announcements are muted in your settings.'
                              : 'No school announcements posted for students currently.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      )
                    else
                      ...result.announcements.map((ann) {
                        final isAdminNotice = ann.authorRole.toLowerCase().contains('admin');
                        final isDirectorNotice = ann.authorRole.toLowerCase().contains('director') || ann.authorRole.toLowerCase().contains('subadmin');
                        final badgeColor = isAdminNotice
                            ? const Color(0xFF6366F1)
                            : isDirectorNotice
                                ? const Color(0xFF059669)
                                : const Color(0xFF0284C7);
                        final badgeLabel = isAdminNotice
                            ? 'Super Admin'
                            : isDirectorNotice
                                ? 'School Directorate'
                                : ann.authorRole;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: theme.brightness == Brightness.dark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: theme.brightness == Brightness.dark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: badgeColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isAdminNotice
                                              ? Icons.security_rounded
                                              : isDirectorNotice
                                                  ? Icons.account_balance_rounded
                                                  : Icons.person_rounded,
                                          size: 12,
                                          color: badgeColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'From: $badgeLabel (${ann.authorName})',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: badgeColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                  if (ann.isPinned)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'PINNED',
                                        style: TextStyle(
                                          color: Colors.amber,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                ann.title,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                ann.content,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: theme.brightness == Brightness.dark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
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
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              'assets/images/exam_prep.jpeg',
                              height: 120,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Icon(
                                Icons.check_circle_outline_rounded,
                                size: 44,
                                color: Colors.green.shade600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
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
                    onStart: () async {
                      await context.push('/student/quiz/${quiz['id']}');
                      if (mounted) {
                        setState(() {
                          _dashboard = _loadDashboard();
                        });
                      }
                    },
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
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
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
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
    final isDark = theme.brightness == Brightness.dark;
    final title = quiz['title'] as String? ?? 'Quiz';
    final desc = quiz['description'] as String? ?? '';
    final timeLimit = quiz['time_limit_minutes'] as int?;
    final totalPoints = quiz['total_points'] as int? ?? 0;

    final sec = quiz['section'] as Map<String, dynamic>?;
    final g = sec?['school_grades'] as Map<String, dynamic>?;
    final gName = (g?['name'] ?? quiz['target_grade']) as String? ?? '';
    final sName = (sec?['name'] ?? quiz['target_section']) as String? ?? '';
    final classLabel = gName.isNotEmpty
        ? (sName.isNotEmpty ? '$gName · Section $sName' : gName)
        : (sName.isNotEmpty ? 'Section $sName' : 'Ciro High School Assessment');

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isForStudentSection
              ? const Color(0xFF10B981).withValues(alpha: 0.35)
              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          width: isForStudentSection ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.quiz_rounded,
                    color: Color(0xFF10B981),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isForStudentSection
                              ? const Color(0xFF10B981).withValues(alpha: 0.15)
                              : (isDark
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isForStudentSection
                                ? const Color(0xFF10B981).withValues(alpha: 0.3)
                                : Colors.transparent,
                          ),
                        ),
                        child: Text(
                          classLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isForStudentSection
                                ? const Color(0xFF047857)
                                : (isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? const Color(0xFFCBD5E1)
                      : const Color(0xFF475569),
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Exam Duration Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.timer_outlined,
                        size: 15,
                        color: Color(0xFF0284C7),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        timeLimit != null && timeLimit > 0
                            ? '$timeLimit Mins Exam'
                            : '30 Mins Exam',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                    ],
                  ),
                ),

                // Total Points Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.military_tech_outlined,
                        size: 15,
                        color: Color(0xFF8B5CF6),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$totalPoints Points',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF8B5CF6),
                        ),
                      ),
                    ],
                  ),
                ),

                // Anti-Cheat & Screen Protection Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 15,
                        color: Color(0xFF10B981),
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Screen Protected',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF047857),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'No recordings or screenshots allowed.',
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  onPressed: onStart,
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text(
                    'Take Exam',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
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
