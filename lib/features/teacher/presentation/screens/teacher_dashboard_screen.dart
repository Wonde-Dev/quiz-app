import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/services/course_resource_service.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/shared/widgets/animated_press_button.dart';
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
  List<Map<String, dynamic>> _gradeStats = [];
  List<Map<String, dynamic>> _sectionStats = [];
  List<Map<String, dynamic>> _myAssignedCourses = [];
  bool _loading = true;
  bool _materialsLocked = false;
  bool _togglingLock = false;
  late final AnimationController _pulseController;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _loadStats();
    _setupRealtime();
  }

  Future<void> _toggleMaterialsLock() async {
    final user = ref.read(authStateProvider).user;
    setState(() => _togglingLock = true);
    final nextState = !_materialsLocked;
    await CourseResourceService().toggleMaterialsLock(nextState, schoolId: user?.schoolId);
    if (mounted) {
      setState(() {
        _materialsLocked = nextState;
        _togglingLock = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextState
                ? 'Exam Mode Enabled: PDFs & video lessons are locked for students!'
                : 'Exam Mode Disabled: Students can now access study materials.',
          ),
          backgroundColor: nextState ? Colors.amber.shade900 : const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _toggleQuizPermission(Map<String, dynamic> quiz) async {
    final quizId = quiz['id'] as String;
    final currentStatus = quiz['is_published'] == true;
    final newStatus = !currentStatus;

    try {
      await Supabase.instance.client
          .from('quizzes')
          .update({'is_published': newStatus})
          .eq('id', quizId);

      if (mounted) {
        setState(() {
          final index = _myQuizzes.indexWhere((q) => q['id'] == quizId);
          if (index != -1) {
            _myQuizzes[index]['is_published'] = newStatus;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus
                  ? 'Permission Granted: Students can now access and take "${quiz['title']}"!'
                  : 'Exam Access Revoked: Students can no longer access "${quiz['title']}".',
            ),
            backgroundColor: newStatus ? const Color(0xFF10B981) : Colors.amber.shade900,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update exam permission: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _setupRealtime() {
    try {
      _realtimeChannel = Supabase.instance.client
          .channel('public:teacher_dashboard_stats')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'users',
            callback: (_) {
              if (mounted) _loadStats();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'quizzes',
            callback: (_) {
              if (mounted) _loadStats();
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Teacher realtime notice: $e');
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    if (_realtimeChannel != null) {
      Supabase.instance.client.removeChannel(_realtimeChannel!);
    }
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

    CourseResourceService().isMaterialsLocked(schoolId: user.schoolId).then((locked) {
      if (mounted) setState(() => _materialsLocked = locked);
    });

    try {
      var studentsQuery = client
          .from('users')
          .select('id, is_active, assigned_grade, assigned_class, requested_grade, requested_class')
          .eq('role', AppRoles.student);
      if (user.schoolId != null) {
        studentsQuery = studentsQuery.eq('school_id', user.schoolId!);
      }

      final teacherQuizzesQuery = client
          .from('quizzes')
          .select('id, title, description, time_limit_minutes, total_points, is_published, created_at')
          .eq('teacher_id', user.id)
          .order('created_at', ascending: false);

      final rpcStatsQuery = client.rpc('get_school_user_stats', params: {
        'p_school_id': user.schoolId,
      });

      final teacherCoursesQuery = client
          .from('teacher_courses')
          .select('id, subject, section_id, sections(name, grade)')
          .eq('teacher_id', user.id);

      final results = await Future.wait<dynamic>([
        studentsQuery,
        teacherQuizzesQuery,
        rpcStatsQuery,
        teacherCoursesQuery,
      ]);

      final allStudents = (results[0] as List).cast<Map<String, dynamic>>();
      final quizzesList = results[1] as List;
      final rpcRes = results[2];
      final myCoursesList = (results[3] as List).cast<Map<String, dynamic>>();

      // Collect this teacher's assigned grades and sections
      final assignedGradesSet = <String>{};
      final assignedSectionsSet = <String>{};

      if (user.assignedGrade != null && user.assignedGrade!.trim().isNotEmpty) {
        assignedGradesSet.add(user.assignedGrade!.trim().toLowerCase());
      }
      if (user.attendanceGrade != null && user.attendanceGrade!.trim().isNotEmpty) {
        assignedGradesSet.add(user.attendanceGrade!.trim().toLowerCase());
      }
      if (user.assignedClass != null && user.assignedClass!.trim().isNotEmpty) {
        assignedSectionsSet.add(user.assignedClass!.trim().toLowerCase());
      }
      if (user.attendanceClass != null && user.attendanceClass!.trim().isNotEmpty) {
        assignedSectionsSet.add(user.attendanceClass!.trim().toLowerCase());
      }

      for (final course in myCoursesList) {
        final secMap = course['sections'] as Map<String, dynamic>?;
        if (secMap != null) {
          final g = secMap['grade']?.toString().trim().toLowerCase();
          final n = secMap['name']?.toString().trim().toLowerCase();
          if (g != null && g.isNotEmpty) assignedGradesSet.add(g);
          if (n != null && n.isNotEmpty) assignedSectionsSet.add(n);
        }
      }

      final activeStudents = allStudents.where((s) {
        if (s['is_active'] == false) return false;
        if (assignedGradesSet.isEmpty && assignedSectionsSet.isEmpty) return true;
        final sGrade = (s['assigned_grade'] ?? s['requested_grade'] ?? '').toString().trim().toLowerCase();
        final sClass = (s['assigned_class'] ?? s['requested_class'] ?? '').toString().trim().toLowerCase();

        final gradeMatch = assignedGradesSet.isEmpty || assignedGradesSet.any((ag) =>
            sGrade == ag || sGrade.contains(ag) || ag.contains(sGrade));
        final sectionMatch = assignedSectionsSet.isEmpty || assignedSectionsSet.any((asect) =>
            sClass == asect || sClass.contains(asect) || asect.contains(sClass));

        return gradeMatch && sectionMatch;
      }).toList();

      List<Map<String, dynamic>> filteredGrades = [];
      List<Map<String, dynamic>> filteredSections = [];
      if (rpcRes is Map) {
        final allG = List<Map<String, dynamic>>.from(rpcRes['grades'] ?? []);
        final allS = List<Map<String, dynamic>>.from(rpcRes['sections'] ?? []);

        if (assignedGradesSet.isNotEmpty) {
          filteredGrades = allG.where((g) {
            final name = (g['grade'] ?? g['name'] ?? '').toString().trim().toLowerCase();
            return assignedGradesSet.any((ag) => name == ag || name.contains(ag) || ag.contains(name));
          }).toList();
        } else {
          filteredGrades = allG;
        }

        if (assignedSectionsSet.isNotEmpty) {
          filteredSections = allS.where((s) {
            final name = (s['section'] ?? s['name'] ?? '').toString().trim().toLowerCase();
            return assignedSectionsSet.any((asect) => name == asect || name.contains(asect) || asect.contains(name));
          }).toList();
        } else {
          filteredSections = allS;
        }
      }

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
        _studentCount = activeStudents.length;
        _quizCount = quizzesList.length;
        _submissionCount = submissionCount;
        _gradeStats = filteredGrades;
        _sectionStats = filteredSections;
        _myAssignedCourses = myCoursesList;
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
            // Welcome Header - Luxury Branded Card with Home Illustration
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFF10B981).withValues(alpha: 0.35),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.16),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.4)
                        : const Color(0xFF0F172A).withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Illustration Background
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/home.jpeg',
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: const Color(0xFF064E3B),
                      ),
                    ),
                  ),
                  // Luxury Gradient Tint
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? [
                                  const Color(0xF5064E3B),
                                  const Color(0xF80F172A),
                                  const Color(0xF2022C22),
                                ]
                              : [
                                  const Color(0xEE064E3B),
                                  const Color(0xEA0F172A),
                                  const Color(0xDC047857),
                                ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(22),
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
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
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
                                        color: const Color(0xFF34D399),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF34D399).withValues(
                                              alpha: 0.4 + (_pulseController.value * 0.5),
                                            ),
                                            blurRadius: 6,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'TEACHER PORTAL · ACTIVE',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            IconButton.filledTonal(
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white.withValues(alpha: 0.2),
                                foregroundColor: Colors.white,
                              ),
                              tooltip: 'Refresh teaching stats',
                              onPressed: _loading ? null : _loadStats,
                              icon: _loading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
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
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.25),
                                ),
                              ),
                              child: const Icon(
                                Icons.school_rounded,
                                color: Color(0xFF34D399),
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
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Create engaging quizzes, evaluate submissions, and guide student success.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: const Color(0xFFE2E8F0),
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
                            AnimatedPressButton(
                              onTap: () => context.push('/teacher/quizzes/new'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add_circle_outline_rounded, size: 18, color: Colors.white),
                                    SizedBox(width: 8),
                                    Text(
                                      'Prepare New Quiz',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            AnimatedPressButton(
                              onTap: () => context.push('/teacher/results'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white38),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.fact_check_rounded, size: 18, color: Colors.white),
                                    SizedBox(width: 8),
                                    Text(
                                      'Evaluate Submissions',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            AnimatedPressButton(
                              onTap: () => context.push('/resources'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white38),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.video_library_rounded, size: 18, color: Colors.white),
                                    SizedBox(width: 8),
                                    Text(
                                      'Worksheets & Videos',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Exam Mode One-Button Toggle Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _materialsLocked
                    ? const Color(0xFF78350F).withValues(alpha: isDark ? 0.35 : 0.12)
                    : const Color(0xFF10B981).withValues(alpha: isDark ? 0.18 : 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _materialsLocked ? const Color(0xFFD97706) : const Color(0xFF10B981),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _materialsLocked ? const Color(0xFFD97706) : const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _materialsLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _materialsLocked
                              ? 'EXAM LOCKDOWN: ACTIVE'
                              : 'STUDY MATERIALS: ACCESSIBLE',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 0.3,
                            color: _materialsLocked ? const Color(0xFFD97706) : const Color(0xFF047857),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _materialsLocked
                              ? 'PDFs and videos are blocked for all students during quiz time.'
                              : 'Students can open and watch worksheets & video lessons.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedPressButton(
                    onTap: _togglingLock ? null : _toggleMaterialsLock,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _materialsLocked ? const Color(0xFF10B981) : const Color(0xFFD97706),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: _togglingLock
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _materialsLocked ? Icons.lock_open_rounded : Icons.lock_clock_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _materialsLocked ? 'Unlock' : 'Lock for Exam',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

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
                    title: 'Total Students',
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
            const SizedBox(height: 18),

            // Multi-Class Teaching Allocations Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
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
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.class_rounded, color: Color(0xFF10B981), size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'My Teaching Allocations & Assigned Classes',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                            Text(
                              'Teachers can be assigned to multiple grades, classes, and subjects across Ciro School',
                              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (currentUser?.assignedClass != null && currentUser!.assignedClass!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.school_outlined, size: 14, color: Color(0xFF10B981)),
                              const SizedBox(width: 6),
                              Text(
                                '${currentUser.assignedGrade ?? "Grade 9"} · Class ${currentUser.assignedClass}${currentUser.assignedSubject != null ? " (${currentUser.assignedSubject})" : ""}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF047857)),
                              ),
                            ],
                          ),
                        ),
                      for (final course in _myAssignedCourses)
                        Builder(
                          builder: (context) {
                            final secMap = course['sections'] as Map<String, dynamic>?;
                            final secName = secMap?['name']?.toString() ?? 'Section';
                            final secGrade = secMap?['grade']?.toString() ?? 'Grade';
                            final subj = course['subject']?.toString() ?? 'Course';

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.25)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.bookmark_outline_rounded, size: 14, color: Color(0xFF6366F1)),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$secGrade · Class $secName ($subj)',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4338CA)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      if (currentUser?.isAttendanceTeacher == true)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD97706).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.verified_user_rounded, size: 14, color: Color(0xFFD97706)),
                              const SizedBox(width: 6),
                              Text(
                                'Attendance Master: ${currentUser?.attendanceClass ?? "Class"}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Section-by-Section Student Numbers Card for Teachers
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
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
                          color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.people_alt_rounded, color: Color(0xFF0284C7), size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Students by Section across Grades',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                            Text(
                              'Faculty view of enrolled students in Section A, B, C per grade level',
                              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_loading)
                    const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                  else
                    Column(
                      children: [
                        for (final grade in const ['Grade 9', 'Grade 10', 'Grade 11', 'Grade 12'])
                          Builder(
                            builder: (context) {
                              final gradeMatch = _gradeStats.firstWhere(
                                (g) => g['grade'] == grade,
                                orElse: () => {'students': 0},
                              );
                              final gradeTotal = gradeMatch['students'] ?? 0;
                              final matchingSections = _sectionStats.where((s) {
                                final sGrade = s['grade']?.toString() ?? '';
                                return sGrade == grade || sGrade == grade.replaceAll('Grade ', '');
                              }).toList();

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          grade,
                                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                        ),
                                        Text(
                                          '$gradeTotal Students Total',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        if (matchingSections.isEmpty)
                                          for (final sec in const ['A', 'B', 'C'])
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                'Class $sec: 0 students',
                                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                                              ),
                                            )
                                        else
                                          for (final s in matchingSections)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF0284C7).withValues(alpha: 0.08),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.2)),
                                              ),
                                              child: Text(
                                                'Class ${s['section']}: ${s['students'] ?? 0} students',
                                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0369A1)),
                                              ),
                                            ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            Text(
              'Teaching & Exam Actions',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),

            // Attendance Teacher / Class Master Card if designated
            if (currentUser?.isAttendanceTeacher == true) ...[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF065F46), Color(0xFF047857), Color(0xFF064E3B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.how_to_reg_rounded,
                            color: Color(0xFF34D399),
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'OFFICIAL ATTENDANCE MASTER',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.2,
                                      color: Color(0xFF6EE7B7),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF34D399),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      currentUser!.attendanceClass ?? '9A',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF064E3B),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Class ${currentUser.attendanceClass ?? '9A'} (${currentUser.attendanceGrade ?? 'Grade 9'}) Authority',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'As the designated Attendance Teacher for Class ${currentUser.attendanceClass ?? '9A'}, you can register new students of your class and review/approve student registration requests waiting to join ${currentUser.attendanceClass ?? '9A'}.',
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFFE2E8F0), height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF064E3B),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                            label: Text('Register for ${currentUser.attendanceClass ?? '9A'}'),
                            onPressed: () => context.push('/teacher/students'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.verified_user_rounded, size: 18),
                          label: const Text('Review Approvals'),
                          onPressed: () => context.push('/admin/approvals'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Action Tiles
            _TeacherActionTile(
              icon: Icons.add_circle_outline_rounded,
              color: const Color(0xFF10B981),
              title: 'Prepare & Publish a Quiz',
              subtitle:
                  'Create exams choosing Grade 9 to 12 and Section A, B, C (or custom section) with question images.',
              buttonText: 'Prepare Quiz',
              onTap: () => context.push('/teacher/quizzes/new'),
            ),
            const SizedBox(height: 10),

            _TeacherActionTile(
              icon: Icons.upload_file_rounded,
              color: const Color(0xFF0284C7),
              title: 'Upload Worksheets & Exam PDFs',
              subtitle:
                  'Distribute official PDF worksheets, reference guides, and exam question papers directly to specific grades and sections.',
              buttonText: 'Class Worksheets',
              onTap: () => context.push('/resources'),
            ),
            const SizedBox(height: 10),

            _TeacherActionTile(
              icon: Icons.fact_check_rounded,
              color: const Color(0xFF059669),
              title: 'Evaluate Quizzes & Results',
              subtitle:
                  'Review student answers question-by-question, evaluate responses, inspect images, and adjust scores.',
              buttonText: 'Evaluate',
              onTap: () => context.push('/teacher/results'),
            ),
            const SizedBox(height: 10),

            if (currentUser?.isAttendanceTeacher == true) ...[
              _TeacherActionTile(
                icon: Icons.person_add_alt_1_rounded,
                color: const Color(0xFF0D9488),
                title: 'Register Students (${currentUser?.attendanceClass ?? "Homeroom"})',
                subtitle:
                    'Register new students in your designated attendance class with their temporary credentials and auto-password formula.',
                buttonText: 'Register Students',
                onTap: () => context.push('/teacher/students'),
              ),
              const SizedBox(height: 10),

              _TeacherActionTile(
                icon: Icons.lock_reset_rounded,
                color: const Color(0xFFF59E0B),
                title: 'Reset Class Student Passwords',
                subtitle:
                    'Reset student passwords for your class with one tap. Generates new temporary credentials securely (Student1@S.edu).',
                buttonText: 'Reset Password',
                onTap: () => context.push('/teacher/reset-passwords'),
              ),
              const SizedBox(height: 10),
            ] else ...[
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFBBF7D0),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.school_rounded, color: Color(0xFF10B981), size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Academic Subject Faculty',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: isDark ? Colors.white : const Color(0xFF065F46),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'You have academic authority to prepare quizzes, upload worksheets, evaluate submissions, and grant students permission/time limits to take exams. Student registrations and rosters are managed exclusively by designated Attendance Teachers.',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF047857),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 28),

            // Quizzes List Section
            Row(
              children: [
                const Icon(
                  Icons.quiz_rounded,
                  color: Color(0xFF10B981),
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
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF10B981),
                  ),
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
                  onTogglePermission: () => _toggleQuizPermission(quiz),
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
    required this.onTogglePermission,
  });

  final Map<String, dynamic> quiz;
  final bool isDark;
  final VoidCallback onEvaluate;
  final VoidCallback onPreview;
  final VoidCallback onTogglePermission;

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
                      isPublished ? 'Published (Active)' : 'Draft (Locked)',
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
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: isPublished
                      ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                      : const Color(0xFF10B981).withValues(alpha: 0.15),
                  foregroundColor: isPublished
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF10B981),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onTogglePermission,
                icon: Icon(
                  isPublished ? Icons.lock_clock_rounded : Icons.lock_open_rounded,
                  size: 14,
                ),
                label: Text(
                  isPublished ? 'Revoke Student Access' : 'Grant Exam Permission',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
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
