import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/services/announcement_service.dart';
import 'package:quiz_app/core/services/audit_log_service.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/shared/models/audit_log.dart';
import 'package:quiz_app/shared/models/school_announcement.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  static const String _ciroSchoolId = '00000000-0000-4000-8000-000000000001';

  int _totalUsersCount = 0;
  int _schoolUsersCount = 0; // Excludes Super Admin for Director
  int _subadminCount = 0;
  int _studentCount = 0;
  int _teacherCount = 0;
  int _quizCount = 0;
  int _pendingCount = 0;
  List<Map<String, dynamic>> _gradeStats = [];
  List<AuditLog> _recentLogs = [];
  List<SchoolAnnouncement> _announcements = [];
  bool _loading = true;
  late final AnimationController _pulseController;
  RealtimeChannel? _realtimeChannel;
  RealtimeChannel? _announcementsChannel;
  final _announcementService = AnnouncementService();

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

  void _setupRealtime() {
    try {
      _realtimeChannel = Supabase.instance.client
          .channel('public:users_stats_changes')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'users',
            callback: (payload) {
              if (mounted) _loadStats();
            },
          )
          .subscribe();

      _announcementsChannel = Supabase.instance.client
          .channel('public:school_announcements_changes')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'school_announcements',
            callback: (payload) {
              if (mounted) _loadStats();
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Realtime subscription notice: $e');
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    if (_realtimeChannel != null) {
      Supabase.instance.client.removeChannel(_realtimeChannel!);
    }
    if (_announcementsChannel != null) {
      Supabase.instance.client.removeChannel(_announcementsChannel!);
    }
    super.dispose();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    final client = Supabase.instance.client;
    final auditService = AuditLogService();
    final currentUser = ref.read(authStateProvider).user;
    final isSubAdmin = currentUser?.role == AppRoles.subadmin;

    try {
      final results = await Future.wait<dynamic>([
        client.rpc('get_school_user_stats', params: {
          'p_school_id': _ciroSchoolId,
        }),
        client.from('quizzes').select('id').eq('is_published', true),
        auditService.fetchLogs(limit: 5),
        _announcementService.fetchAnnouncements(schoolId: _ciroSchoolId, limit: 6),
      ]);

      if (!mounted) return;
      final rpcRes = results[0];
      final publishedQuizzes = results[1] as List;
      final recentLogs = results[2] as List<AuditLog>;
      final announcements = results[3] as List<SchoolAnnouncement>;

      if (rpcRes is Map) {
        final subadmins = (rpcRes['subadmins'] as num?)?.toInt() ?? 0;
        final teachers = (rpcRes['teachers'] as num?)?.toInt() ?? 0;
        final students = (rpcRes['students'] as num?)?.toInt() ?? 0;
        final schoolUsers = (rpcRes['school_users'] as num?)?.toInt() ?? (subadmins + teachers + students);
        final pendingTeachers = (rpcRes['pending_teachers'] as num?)?.toInt() ?? 0;
        final pendingAll = (rpcRes['pending'] as num?)?.toInt() ?? 0;

        setState(() {
          _totalUsersCount = (rpcRes['total_users'] as num?)?.toInt() ?? 0;
          _schoolUsersCount = schoolUsers;
          _subadminCount = subadmins;
          _teacherCount = teachers;
          _studentCount = students;
          _pendingCount = isSubAdmin ? pendingTeachers : pendingAll;
          _gradeStats = List<Map<String, dynamic>>.from(rpcRes['grades'] ?? []);
          _quizCount = publishedQuizzes.length;
          _recentLogs = recentLogs;
          _announcements = announcements;
          _loading = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('get_school_user_stats RPC note: $e');
    }

    try {
      final results = await Future.wait<dynamic>([
        client.from('users').select('id, role, is_active, approval_status'),
        client.from('quizzes').select('id').eq('is_published', true),
        auditService.fetchLogs(limit: 5),
        _announcementService.fetchAnnouncements(schoolId: _ciroSchoolId, limit: 6),
      ]);

      if (!mounted) return;
      final allUsers = (results[0] as List).cast<Map<String, dynamic>>();
      final publishedQuizzes = results[1] as List;
      final recentLogs = results[2] as List<AuditLog>;
      final announcements = results[3] as List<SchoolAnnouncement>;

      final activeUsers = allUsers.where((u) => u['is_active'] != false).toList();
      final subadminCount = activeUsers.where((u) => u['role'] == 'subadmin').length;
      final studentCount = activeUsers.where((u) => u['role'] == 'student').length;
      final teacherCount = activeUsers.where((u) => u['role'] == 'teacher').length;
      final schoolUsers = subadminCount + studentCount + teacherCount;
      final totalUsers = activeUsers.length;
      final pendingCount = allUsers.where((u) => u['approval_status'] == 'pending').length;
      final pendingTeachers = allUsers
          .where((u) => u['approval_status'] == 'pending' && u['role'] == 'teacher')
          .length;

      setState(() {
        _totalUsersCount = totalUsers;
        _schoolUsersCount = schoolUsers;
        _subadminCount = subadminCount;
        _studentCount = studentCount;
        _teacherCount = teacherCount;
        _quizCount = publishedQuizzes.length;
        _pendingCount = isSubAdmin ? pendingTeachers : pendingCount;
        _recentLogs = recentLogs;
        _announcements = announcements;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Admin stats loading note: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _postAnnouncementDialog() async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    String selectedAudience = 'all';
    bool isPinned = false;
    final currentUser = ref.read(authStateProvider).user;
    final isSubAdmin = currentUser?.role == AppRoles.subadmin;
    final authorRole = isSubAdmin ? 'School Director' : 'Administrator';
    final authorName = currentUser?.fullName?.isNotEmpty == true
        ? currentUser!.fullName!
        : (currentUser?.username ?? authorRole);

    final audienceOptions = [
      {'value': 'all', 'label': 'All Members (School-wide)'},
      {'value': 'teachers', 'label': 'Faculty Teachers Only'},
      {'value': 'students', 'label': 'Enrolled Students Only'},
      {'value': 'Grade 9', 'label': 'Grade 9 Students'},
      {'value': 'Grade 10', 'label': 'Grade 10 Students'},
      {'value': 'Grade 11', 'label': 'Grade 11 Students'},
      {'value': 'Grade 12', 'label': 'Grade 12 Students'},
    ];

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          title: const Row(
            children: [
              Icon(Icons.campaign_rounded, color: Color(0xFF10B981), size: 26),
              SizedBox(width: 10),
              Text(
                'Post School Announcement',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Broadcast an official announcement to Ciro High School members.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Announcement Title *',
                      hintText: 'e.g. Midterm Examination Schedule',
                      prefixIcon: Icon(Icons.title_rounded),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedAudience,
                    decoration: const InputDecoration(
                      labelText: 'Target Audience *',
                      prefixIcon: Icon(Icons.groups_rounded),
                    ),
                    items: audienceOptions
                        .map((opt) => DropdownMenuItem(
                              value: opt['value'],
                              child: Text(opt['label']!),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedAudience = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contentController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Message / Content *',
                      hintText: 'Provide details, instructions, or deadlines for school members...',
                      alignLabelWithHint: true,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Pin to Top of Feed',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Highlighted notice displayed prominently for all users',
                        style: TextStyle(fontSize: 11)),
                    value: isPinned,
                    onChanged: (val) => setDialogState(() => isPinned = val),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Broadcast Now'),
              onPressed: () async {
                final title = titleController.text.trim();
                final content = contentController.text.trim();
                if (title.isEmpty || content.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter both title and content.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                Navigator.pop(dialogCtx);
                try {
                  await _announcementService.createAnnouncement(
                    title: title,
                    content: content,
                    authorName: authorName,
                    authorRole: authorRole,
                    targetAudience: selectedAudience,
                    isPinned: isPinned,
                    schoolId: _ciroSchoolId,
                  );
                  _loadStats();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Announcement broadcasted successfully!'),
                        backgroundColor: Color(0xFF10B981),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to post announcement: $e'),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAnnouncement(SchoolAnnouncement item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Announcement?'),
        content: Text('Remove "${item.title}" from the school bulletin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _announcementService.deleteAnnouncement(item.id);
        _loadStats();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Announcement removed.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not delete announcement: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _openQuizzesModerationSheet() async {
    final client = Supabase.instance.client;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.quiz_rounded, color: Color(0xFF8B5CF6), size: 24),
                      SizedBox(width: 10),
                      Text(
                        'Faculty Quizzes Oversight',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Quizzes are prepared exclusively by faculty teachers. Administrators and directors have oversight to review preparations and delete invalid or outdated exams.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                ),
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: () async {
                    final rows = await client
                        .from('quizzes')
                        .select(
                          'id, title, description, time_limit_minutes, total_points, is_published, created_at, target_grade, target_section, school_id, '
                          'teacher:users!quizzes_teacher_id_fkey(id, full_name, username)',
                        )
                        .order('created_at', ascending: false);
                    return List<Map<String, dynamic>>.from(rows);
                  }(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text('Could not load quizzes: ${snapshot.error}'),
                      );
                    }
                    final quizzes = snapshot.data ?? [];
                    if (quizzes.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.quiz_outlined, size: 48, color: Colors.grey),
                              SizedBox(height: 12),
                              Text('No quizzes prepared yet',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              SizedBox(height: 4),
                              Text(
                                'When teachers publish exams or quizzes, they will appear here.',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: quizzes.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, idx) {
                        final q = quizzes[idx];
                        final teacherMap = q['teacher'] as Map<String, dynamic>?;
                        final teacherName = teacherMap?['full_name']?.toString().isNotEmpty == true
                            ? teacherMap!['full_name']
                            : teacherMap?['username'] ?? 'Faculty Member';
                        final grade = q['target_grade']?.toString() ?? '';
                        final section = q['target_section']?.toString() ?? '';

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.grey.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.description_outlined,
                                    color: Color(0xFF8B5CF6), size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      q['title']?.toString() ?? 'Untitled Quiz',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Prepared by $teacherName',
                                      style: const TextStyle(
                                          fontSize: 12, color: Color(0xFF64748B)),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        if (grade.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              grade,
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.blue),
                                            ),
                                          ),
                                        if (section.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Class $section',
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green),
                                            ),
                                          ),
                                        Text(
                                          '${q['time_limit_minutes'] ?? 30} mins · ${q['total_points'] ?? 100} pts',
                                          style: const TextStyle(
                                              fontSize: 11, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    color: Colors.red),
                                tooltip: 'Delete Quiz Preparation',
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: ctx,
                                    builder: (dialogCtx) => AlertDialog(
                                      title: const Text('Delete Quiz Preparation?'),
                                      content: Text(
                                        'Are you sure you want to delete "${q['title']}" prepared by $teacherName?\n\n'
                                        'All questions and student attempts will be permanently deleted.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(dialogCtx, false),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                              backgroundColor: Colors.red),
                                          onPressed: () => Navigator.pop(dialogCtx, true),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirmed == true) {
                                    try {
                                      await client.rpc('admin_delete_quiz',
                                          params: {'p_quiz_id': q['id']});
                                    } catch (_) {
                                      await client
                                          .from('quizzes')
                                          .delete()
                                          .eq('id', q['id']);
                                    }
                                    setSheetState(() {});
                                    _loadStats();
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentUser = ref.watch(authStateProvider).user;
    final isSubAdmin = currentUser?.role == AppRoles.subadmin;
    final adminName = currentUser?.fullName?.isNotEmpty == true
        ? currentUser!.fullName!
        : currentUser?.username ?? (isSubAdmin ? 'Director' : 'Administrator');

    return DashboardShell(
      title: isSubAdmin ? 'Ciro High School · Director Center' : 'Ciro High School · Admin Center',
      body: RefreshIndicator(
        onRefresh: _loadStats,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Welcome Header - Institutional Luxury Card for Ciro High School
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
                            // Status Badge with pulsing green indicator
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
                                    'CIRO HIGH SCHOOL · ACTIVE',
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
                              tooltip: 'Refresh system stats',
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
                              child: Icon(
                                isSubAdmin
                                    ? Icons.admin_panel_settings_rounded
                                    : Icons.shield_rounded,
                                color: const Color(0xFF34D399),
                                size: 32,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isSubAdmin
                                              ? const Color(0xFF6366F1).withValues(alpha: 0.3)
                                              : const Color(0xFFF59E0B).withValues(alpha: 0.3),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: isSubAdmin
                                                ? const Color(0xFF818CF8)
                                                : const Color(0xFFFBBF24),
                                            width: 1,
                                          ),
                                        ),
                                        child: Text(
                                          isSubAdmin
                                              ? 'SCHOOL DIRECTOR'
                                              : 'SUPER ADMINISTRATOR',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.6,
                                            color: isSubAdmin
                                                ? const Color(0xFFC7D2FE)
                                                : const Color(0xFFFEF3C7),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Welcome, $adminName',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isSubAdmin
                                        ? 'Director oversight for Ciro High School faculty teachers, grade enrollment totals, and official announcements.'
                                        : 'Institutional administrative control for Ciro High School. Manage directors, faculty, students, and surveillance.',
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
                              icon: const Icon(Icons.person_add_rounded, size: 18),
                              label: Text(isSubAdmin
                                  ? 'Register Faculty Teacher'
                                  : 'Register User (Director/Staff/Student)'),
                              onPressed: () async {
                                await context.push('/admin/register-user');
                                if (mounted) _loadStats();
                              },
                            ),
                            FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.25),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.campaign_rounded, size: 18),
                              label: const Text('Post Announcement'),
                              onPressed: _postAnnouncementDialog,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Live Metrics Section
            Text(
              isSubAdmin
                  ? 'Ciro High School Community Metrics (Excludes Super Admin)'
                  : 'Ciro High School System Totals',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),

            if (!isSubAdmin) ...[
              // SUPER ADMIN: Role totals only (No grade/section breakdown)
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      title: 'Total System Users',
                      subtitle: 'Including all institutional accounts',
                      count: _totalUsersCount,
                      loading: _loading,
                      icon: Icons.groups_rounded,
                      color: isDark
                          ? const Color(0xFF38BDF8)
                          : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricCard(
                      title: 'School Directors',
                      subtitle: 'Campus administrative directors',
                      count: _subadminCount,
                      loading: _loading,
                      icon: Icons.admin_panel_settings_rounded,
                      color: const Color(0xFF6366F1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      title: 'Faculty Teachers',
                      subtitle: 'Teaching & attendance staff',
                      count: _teacherCount,
                      loading: _loading,
                      icon: Icons.co_present_rounded,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricCard(
                      title: 'Enrolled Students',
                      subtitle: 'Active registered learners',
                      count: _studentCount,
                      loading: _loading,
                      icon: Icons.school_rounded,
                      color: const Color(0xFF3B82F6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _MetricCard(
                title: 'Faculty Quizzes Prepared (Teacher Created Only)',
                subtitle: 'Tap to review submissions and delete outdated preparations',
                count: _quizCount,
                loading: _loading,
                icon: Icons.quiz_rounded,
                color: const Color(0xFF8B5CF6),
                onTap: _openQuizzesModerationSheet,
              ),
            ] else ...[
              // SUB-ADMIN (DIRECTOR): School total users strictly EXCLUDES Super Admin
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      title: 'School Total Users',
                      subtitle: 'Directors, Teachers & Students (Excludes Super Admin)',
                      count: _schoolUsersCount,
                      loading: _loading,
                      icon: Icons.school_rounded,
                      color: isDark
                          ? const Color(0xFF38BDF8)
                          : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricCard(
                      title: 'Faculty Teachers',
                      subtitle: 'Verified teaching staff',
                      count: _teacherCount,
                      loading: _loading,
                      icon: Icons.co_present_rounded,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      title: 'Enrolled Students',
                      subtitle: 'Official registered students',
                      count: _studentCount,
                      loading: _loading,
                      icon: Icons.groups_rounded,
                      color: const Color(0xFF3B82F6),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricCard(
                      title: 'Faculty Quizzes',
                      subtitle: 'Teacher-prepared exams',
                      count: _quizCount,
                      loading: _loading,
                      icon: Icons.quiz_rounded,
                      color: const Color(0xFF8B5CF6),
                      onTap: _openQuizzesModerationSheet,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Grade Breakdown Card for Director (Grades 9 to 12 only, strictly no sections)
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
                          child: const Icon(Icons.grade_rounded,
                              color: Color(0xFF10B981), size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ciro High School Enrollment by Grade Level',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                              Text(
                                'Official teacher and student tallies for Grade 9, 10, 11, and 12 (grade totals only)',
                                style: TextStyle(
                                    fontSize: 11, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_loading)
                      const Center(
                          child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator()))
                    else
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 2.1,
                        children: [
                          for (final gradeName in const [
                            'Grade 9',
                            'Grade 10',
                            'Grade 11',
                            'Grade 12'
                          ])
                            Builder(
                              builder: (context) {
                                final match = _gradeStats.firstWhere(
                                  (g) => g['grade'] == gradeName,
                                  orElse: () => {'students': 0, 'teachers': 0},
                                );
                                final students = match['students'] ?? 0;
                                final teachers = match['teachers'] ?? 0;

                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF0F172A)
                                        : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isDark
                                          ? const Color(0xFF334155)
                                          : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        gradeName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$students Students · $teachers Teachers',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? const Color(0xFF94A3B8)
                                              : const Color(0xFF475569),
                                        ),
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
            ],
            const SizedBox(height: 16),

            // Pending Approvals Alert (Shows pending teachers for director)
            if (_pendingCount > 0) ...[
              Card(
                color: const Color(0xFFFFFBEB),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFFDE68A)),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.notifications_active_rounded,
                      color: Color(0xFFD97706),
                    ),
                  ),
                  title: Text(
                    isSubAdmin
                        ? '$_pendingCount Pending Teacher Approval${_pendingCount > 1 ? 's' : ''}'
                        : '$_pendingCount Pending Registration Approval${_pendingCount > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF92400E),
                    ),
                  ),
                  subtitle: Text(
                    isSubAdmin
                        ? 'Newly registered teachers awaiting director verification'
                        : 'New user registration requests awaiting approval',
                    style: const TextStyle(color: Color(0xFFB45309)),
                  ),
                  trailing: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                    ),
                    onPressed: () async {
                      await context.push('/admin/approvals');
                      if (mounted) _loadStats();
                    },
                    child: const Text('Review'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // OFFICIAL SCHOOL ANNOUNCEMENTS HUB
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.campaign_rounded, color: Color(0xFF10B981), size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Ciro High School Announcements',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Post Notice'),
                  onPressed: _postAnnouncementDialog,
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_loading && _announcements.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_announcements.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFF64748B)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'No announcements posted yet. Tap "Post Notice" to broadcast messages to teachers and students.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Column(
                children: [
                  for (final item in _announcements) ...[
                    _AnnouncementCard(
                      announcement: item,
                      onDelete: () => _deleteAnnouncement(item),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            const SizedBox(height: 24),

            // Recent System & Admin Activities section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Admin & System Activities',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await context.push('/admin/audit-logs');
                    if (mounted) _loadStats();
                  },
                  child: const Text('View All Logs'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_loading && _recentLogs.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_recentLogs.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFF64748B)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'No recent audit activity recorded yet.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      for (int i = 0; i < _recentLogs.length; i++) ...[
                        _ActivityListTile(log: _recentLogs[i]),
                        if (i < _recentLogs.length - 1)
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      ],
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 24),
            Text(
              'Management & Control Actions',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),

            if (isSubAdmin) ...[
              // SUB-ADMIN ACTIONS: Strictly Teachers, Announcements, Quizzes Oversight
              _ActionTile(
                icon: Icons.person_add_alt_1_rounded,
                color: const Color(0xFF10B981),
                title: 'Register Faculty Teacher',
                subtitle:
                    'Create and activate new Faculty Teacher accounts for Ciro High School with Grade, Section, and Subject assignments.',
                buttonText: 'Register Teacher',
                onTap: () async {
                  await context.push('/admin/register-user');
                  if (mounted) _loadStats();
                },
              ),
              const SizedBox(height: 10),

              _ActionTile(
                icon: Icons.how_to_reg_rounded,
                color: const Color(0xFF059669),
                title: 'Review Teacher Approvals',
                subtitle:
                    'Review, approve, or reject pending teacher registration requests for Ciro High School.',
                buttonText: 'Teacher Approvals',
                onTap: () async {
                  await context.push('/admin/approvals');
                  if (mounted) _loadStats();
                },
              ),
              const SizedBox(height: 10),

              _ActionTile(
                icon: Icons.co_present_rounded,
                color: const Color(0xFF6366F1),
                title: 'Faculty Directory & Multi-Class Assignments',
                subtitle:
                    'Manage Ciro High School teachers, assign multiple grades and classes, reset passwords, or remove faculty.',
                buttonText: 'Manage Faculty',
                onTap: () async {
                  await context.push('/admin/teachers');
                  if (mounted) _loadStats();
                },
              ),
              const SizedBox(height: 10),

              _ActionTile(
                icon: Icons.campaign_rounded,
                color: const Color(0xFF0284C7),
                title: 'Broadcast School Announcement',
                subtitle:
                    'Post announcements and notices directly to teachers and students of Ciro High School.',
                buttonText: 'Post Notice',
                onTap: _postAnnouncementDialog,
              ),
              const SizedBox(height: 10),

              _ActionTile(
                icon: Icons.quiz_rounded,
                color: const Color(0xFF8B5CF6),
                title: 'Faculty Quizzes Oversight',
                subtitle:
                    'Quizzes are prepared exclusively by faculty teachers. Inspect exam preparations and remove outdated submissions.',
                buttonText: 'Review Quizzes',
                onTap: _openQuizzesModerationSheet,
              ),
              const SizedBox(height: 10),

              _ActionTile(
                icon: Icons.history_rounded,
                color: const Color(0xFF0F172A),
                title: 'School Audit Activity',
                subtitle:
                    'Chronological activity feed tracking Ciro High School accounts, logins, and audit events.',
                buttonText: 'Audit Surveillance',
                onTap: () async {
                  await context.push('/admin/audit-logs');
                  if (mounted) _loadStats();
                },
              ),
            ] else ...[
              // SUPER ADMIN ACTIONS: Full system control
              _ActionTile(
                icon: Icons.person_add_alt_1_rounded,
                color: const Color(0xFF10B981),
                title: 'Register New User (Director, Teacher, Student)',
                subtitle:
                    'Directly create and activate School Director, Faculty Teacher (with Grade & Section), or Student accounts with instant credentials.',
                buttonText: 'Register User',
                onTap: () async {
                  await context.push('/admin/register-user');
                  if (mounted) _loadStats();
                },
              ),
              const SizedBox(height: 10),

              _ActionTile(
                icon: Icons.how_to_reg_rounded,
                color: const Color(0xFF059669),
                title: 'Review Registration Requests',
                subtitle:
                    'Review, approve, or reject new student, faculty, and director registration applications.',
                buttonText: 'Registration Approvals',
                onTap: () async {
                  await context.push('/admin/approvals');
                  if (mounted) _loadStats();
                },
              ),
              const SizedBox(height: 10),

              _ActionTile(
                icon: Icons.co_present_rounded,
                color: const Color(0xFF6366F1),
                title: 'Faculty Directory & Multi-Class Allocations',
                subtitle:
                    'View approved teachers, assign multiple grades and subjects, and reset faculty passwords directly.',
                buttonText: 'Faculty Directory',
                onTap: () async {
                  await context.push('/admin/teachers');
                  if (mounted) _loadStats();
                },
              ),
              const SizedBox(height: 10),

              _ActionTile(
                icon: Icons.manage_accounts_rounded,
                color: const Color(0xFF0D9488),
                title: 'User Rosters & Account Deletion',
                subtitle:
                    'Browse registered student and teacher directories, view profiles, or delete user accounts.',
                buttonText: 'Manage Rosters',
                onTap: () async {
                  await context.push('/teacher/students');
                  if (mounted) _loadStats();
                },
              ),
              const SizedBox(height: 10),

              _ActionTile(
                icon: Icons.class_outlined,
                color: const Color(0xFF0284C7),
                title: 'Class & Section Allocations',
                subtitle:
                    'Manage Ciro High School grades (9, 10, 11, 12), classroom sections, and teacher multi-class allocations.',
                buttonText: 'Class Management',
                onTap: () async {
                  await context.push('/admin/classes');
                  if (mounted) _loadStats();
                },
              ),
              const SizedBox(height: 10),

              _ActionTile(
                icon: Icons.campaign_rounded,
                color: const Color(0xFF10B981),
                title: 'Post School Announcement',
                subtitle:
                    'Publish notices, schedules, or announcements for Ciro High School members.',
                buttonText: 'New Announcement',
                onTap: _postAnnouncementDialog,
              ),
              const SizedBox(height: 10),

              _ActionTile(
                icon: Icons.quiz_rounded,
                color: const Color(0xFF8B5CF6),
                title: 'Faculty Quizzes Oversight',
                subtitle:
                    'Quizzes are prepared exclusively by teachers. Review exams and moderate/delete preparations.',
                buttonText: 'Quizzes Oversight',
                onTap: _openQuizzesModerationSheet,
              ),
              const SizedBox(height: 10),

              _ActionTile(
                icon: Icons.auto_stories_rounded,
                color: const Color(0xFFF59E0B),
                title: 'Learning Materials Oversight',
                subtitle:
                    'Review faculty-uploaded study PDFs, worksheets, and educational videos, and moderate content.',
                buttonText: 'Inspect Materials',
                onTap: () async {
                  await context.push('/resources');
                  if (mounted) _loadStats();
                },
              ),
              const SizedBox(height: 10),

              _ActionTile(
                icon: Icons.history_rounded,
                color: const Color(0xFF0F172A),
                title: 'System Activity & Audit Logs',
                subtitle:
                    'Full chronological activity feed tracking institutional accounts, password resets, and audit actions.',
                buttonText: 'Audit Surveillance',
                onTap: () async {
                  await context.push('/admin/audit-logs');
                  if (mounted) _loadStats();
                },
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    required this.announcement,
    required this.onDelete,
  });

  final SchoolAnnouncement announcement;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final diff = DateTime.now().difference(announcement.createdAt);
    final timeStr = diff.inMinutes < 1
        ? 'Just now'
        : diff.inMinutes < 60
            ? '${diff.inMinutes}m ago'
            : diff.inHours < 24
                ? '${diff.inHours}h ago'
                : '${announcement.createdAt.month}/${announcement.createdAt.day}';

    final audienceLabel = switch (announcement.targetAudience) {
      'teachers' => 'Teachers Only',
      'students' => 'Students Only',
      'Grade 9' => 'Grade 9',
      'Grade 10' => 'Grade 10',
      'Grade 11' => 'Grade 11',
      'Grade 12' => 'Grade 12',
      _ => 'All School',
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: announcement.isPinned
              ? const Color(0xFF10B981)
              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          width: announcement.isPinned ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (announcement.isPinned) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.push_pin_rounded, size: 11, color: Color(0xFF059669)),
                      SizedBox(width: 4),
                      Text('PINNED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF059669))),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  audienceLabel,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6366F1),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                timeStr,
                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Delete Announcement',
                onPressed: onDelete,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            announcement.title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
          ),
          const SizedBox(height: 4),
          Text(
            announcement.content,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.person_pin_rounded, size: 14, color: Color(0xFF059669)),
              const SizedBox(width: 4),
              Text(
                'By ${announcement.authorName} (${announcement.authorRole})',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF059669)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityListTile extends StatelessWidget {
  const _ActivityListTile({required this.log});

  final AuditLog log;

  @override
  Widget build(BuildContext context) {
    final (color, icon, title) = _getMeta(log.action);
    final actor = log.details?['actor_name'] as String? ??
        (log.performedBy != null && log.performedBy!.length > 8
            ? log.performedBy!.substring(0, 8)
            : log.performedBy ?? 'System');

    final diff = DateTime.now().difference(log.createdAt);
    final timeStr = diff.inMinutes < 1
        ? 'Just now'
        : diff.inMinutes < 60
            ? '${diff.inMinutes}m ago'
            : diff.inHours < 24
                ? '${diff.inHours}h ago'
                : '${log.createdAt.month}/${log.createdAt.day}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'By $actor ${log.targetUser != null && log.targetUser!.isNotEmpty ? '• Target: ${log.targetUser!.length > 8 ? log.targetUser!.substring(0, 8) : log.targetUser}' : ''}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Text(
            timeStr,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  (Color, IconData, String) _getMeta(String action) {
    if (action.contains('account_created')) {
      return (const Color(0xFF10B981), Icons.person_add_rounded, 'Account Created');
    }
    if (action.contains('password_reset')) {
      return (const Color(0xFFF59E0B), Icons.lock_reset_rounded, 'Password Reset');
    }
    if (action.contains('password_changed')) {
      return (const Color(0xFF3B82F6), Icons.password_rounded, 'Password Changed');
    }
    if (action.contains('account_approved')) {
      return (const Color(0xFF10B981), Icons.verified_user_rounded, 'Account Approved');
    }
    if (action.contains('account_deleted')) {
      return (const Color(0xFFEF4444), Icons.delete_forever_rounded, 'Account Removed');
    }
    if (action.contains('quiz_created') || action.contains('quiz_published')) {
      return (const Color(0xFF8B5CF6), Icons.quiz_rounded, 'Quiz Published');
    }
    if (action.contains('quiz_submitted')) {
      return (const Color(0xFF06B6D4), Icons.assignment_turned_in_rounded, 'Quiz Submitted');
    }
    return (
      const Color(0xFF64748B),
      Icons.timeline_rounded,
      action.replaceAll('_', ' '),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.count,
    required this.loading,
    required this.icon,
    required this.color,
    this.subtitle,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final int count;
  final bool loading;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final cardContent = Container(
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
                  '$count',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
          const SizedBox(height: 2),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: cardContent,
        ),
      );
    }

    return cardContent;
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
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
