import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/services/announcement_service.dart';
import 'package:quiz_app/core/services/audit_log_service.dart';
import 'package:quiz_app/core/services/teacher_activity_service.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/shared/models/audit_log.dart';
import 'package:quiz_app/shared/models/school_announcement.dart';
import 'package:quiz_app/shared/models/teacher_academic_activity.dart';
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
  int _directorCount = 0;
  int _studentCount = 0;
  int _teacherCount = 0;
  int _quizCount = 0;
  int _pendingCount = 0;
  List<Map<String, dynamic>> _gradeStats = [];
  List<AuditLog> _recentLogs = [];
  List<SchoolAnnouncement> _announcements = [];
  List<TeacherAcademicActivity> _teacherActivities = [];
  bool _loading = true;

  late final AnimationController _pulseController;
  RealtimeChannel? _realtimeChannel;
  RealtimeChannel? _announcementsChannel;

  final _announcementService = AnnouncementService();
  final _activityService = TeacherActivityService();

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
            callback: (_) {
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
            callback: (_) {
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

    try {
      final results = await Future.wait<dynamic>([
        // 0. School stats RPC
        client.rpc('get_school_user_stats', params: {
          'p_school_id': _ciroSchoolId,
        }),
        // 1. Quizzes
        client.from('quizzes').select('id').eq('is_published', true),
        // 2. Audit logs
        auditService.fetchLogs(limit: 6),
        // 3. Announcements
        _announcementService.fetchAnnouncements(schoolId: _ciroSchoolId, limit: 6),
        // 4. Teacher Academic Activities
        _activityService.fetchActivities(schoolId: _ciroSchoolId, limit: 10),
      ]);

      if (!mounted) return;
      final rpcRes = results[0];
      final publishedQuizzes = results[1] as List;
      final recentLogs = results[2] as List<AuditLog>;
      final announcements = results[3] as List<SchoolAnnouncement>;
      final activities = results[4] as List<TeacherAcademicActivity>;

      if (rpcRes is Map) {
        final directors = (rpcRes['subadmins'] as num?)?.toInt() ?? 0;
        final teachers = (rpcRes['teachers'] as num?)?.toInt() ?? 0;
        final students = (rpcRes['students'] as num?)?.toInt() ?? 0;
        final pendingAll = (rpcRes['pending'] as num?)?.toInt() ?? 0;

        setState(() {
          _totalUsersCount = (rpcRes['total_users'] as num?)?.toInt() ?? 0;
          _directorCount = directors;
          _teacherCount = teachers;
          _studentCount = students;
          _pendingCount = pendingAll;
          _gradeStats = List<Map<String, dynamic>>.from(rpcRes['grades'] ?? []);
          _quizCount = publishedQuizzes.length;
          _recentLogs = recentLogs;
          _announcements = announcements;
          _teacherActivities = activities;
          _loading = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('get_school_user_stats RPC note: $e');
    }

    // Direct fallback
    try {
      final results = await Future.wait<dynamic>([
        client.from('users').select('id, role, is_active, approval_status'),
        client.from('quizzes').select('id').eq('is_published', true),
        auditService.fetchLogs(limit: 6),
        _announcementService.fetchAnnouncements(schoolId: _ciroSchoolId, limit: 6),
        _activityService.fetchActivities(schoolId: _ciroSchoolId, limit: 10),
      ]);

      if (!mounted) return;
      final allUsers = (results[0] as List).cast<Map<String, dynamic>>();
      final publishedQuizzes = results[1] as List;
      final recentLogs = results[2] as List<AuditLog>;
      final announcements = results[3] as List<SchoolAnnouncement>;
      final activities = results[4] as List<TeacherAcademicActivity>;

      final activeUsers = allUsers.where((u) => u['is_active'] != false).toList();
      final directorCount = activeUsers.where((u) => u['role'] == 'subadmin' || u['role'] == 'director').length;
      final studentCount = activeUsers.where((u) => u['role'] == 'student').length;
      final teacherCount = activeUsers.where((u) => u['role'] == 'teacher').length;
      final totalUsers = activeUsers.length;
      final pendingCount = allUsers.where((u) => u['approval_status'] == 'pending').length;

      setState(() {
        _totalUsersCount = totalUsers;
        _directorCount = directorCount;
        _studentCount = studentCount;
        _teacherCount = teacherCount;
        _quizCount = publishedQuizzes.length;
        _pendingCount = pendingCount;
        _recentLogs = recentLogs;
        _announcements = announcements;
        _teacherActivities = activities;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Admin stats fallback note: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showTransferSuperAdminOwnershipDialog() async {
    final client = Supabase.instance.client;
    final passwordController = TextEditingController();
    bool isSubmitting = false;
    bool obscurePassword = true;
    String? selectedUserId;
    String? selectedUserName;
    String? errorText;

    // Load active accounts eligible for ownership transfer (excluding current super admin)
    List<Map<String, dynamic>> eligibleUsers = [];
    try {
      final rows = await client
          .from('users')
          .select('id, full_name, username, email, role')
          .eq('is_active', true)
          .neq('role', 'admin')
          .order('full_name');
      eligibleUsers = List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('Error loading users for super admin transfer: $e');
    }

    if (!mounted) return;

    if (eligibleUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No eligible active accounts available for ownership transfer.'),
          backgroundColor: Color(0xFFD97706),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.security_update_warning_rounded, color: Color(0xFFDC2626), size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Transfer Super Admin Ownership',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_rounded, color: Color(0xFFDC2626), size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'CRITICAL SYSTEM ACTION: You are about to permanently transfer full Super Administrator control of Ciro High School. Your account will automatically demote to Faculty Teacher, and the selected user will inherit complete root administrative authority. There can only be ONE Super Administrator in the system.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF991B1B), height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Select Successor Account *',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedUserId,
                          hint: const Text('Choose eligible account...'),
                          isExpanded: true,
                          items: eligibleUsers.map((u) {
                            final name = (u['full_name'] as String?)?.trim().isNotEmpty == true
                                ? u['full_name'] as String
                                : u['username'] as String;
                            final role = (u['role'] as String? ?? 'user').toUpperCase();
                            return DropdownMenuItem<String>(
                              value: u['id'] as String,
                              child: Text('$name ($role) - ${u['email']}'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setDialogState(() {
                              selectedUserId = val;
                              final match = eligibleUsers.firstWhere((u) => u['id'] == val);
                              selectedUserName = match['full_name'] as String? ?? match['username'] as String?;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Confirm Your Current Super Admin Password *',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        hintText: 'Enter your password to authorize transfer',
                        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                          onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                errorText!,
                                style: const TextStyle(color: Colors.red, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: (isSubmitting || selectedUserId == null)
                    ? null
                    : () async {
                        final pass = passwordController.text.trim();
                        if (pass.isEmpty) {
                          setDialogState(() => errorText = 'Password confirmation is required.');
                          return;
                        }

                        setDialogState(() {
                          isSubmitting = true;
                          errorText = null;
                        });

                        try {
                          final res = await _activityService.transferSuperAdminOwnership(
                            targetUserId: selectedUserId!,
                            currentPassword: pass,
                          );

                          if (dialogCtx.mounted) {
                            Navigator.pop(dialogCtx);
                          }

                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(res['message']?.toString() ??
                                  'Super Admin ownership transferred to $selectedUserName!'),
                              backgroundColor: const Color(0xFF10B981),
                            ),
                          );

                          await ref.read(authStateProvider.notifier).refreshCurrentUser();
                          if (mounted) context.go('/teacher/dashboard');
                        } catch (e) {
                          setDialogState(() {
                            isSubmitting = false;
                            errorText = e.toString().replaceAll('Exception:', '').trim();
                          });
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Confirm Ownership Transfer'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDirectorOptionsDialog() async {
    final client = Supabase.instance.client;
    Map<String, dynamic>? director;
    try {
      final rows = await client
          .from('users')
          .select('id, full_name, username, email, is_active, created_at')
          .inFilter('role', ['subadmin', 'director'])
          .limit(1);
      if (rows.isNotEmpty) director = rows.first;
    } catch (_) {}

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.manage_accounts_rounded, color: Color(0xFF6366F1)),
            ),
            const SizedBox(width: 12),
            const Text('School Directorate'),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Currently Appointed Director:',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4338CA)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      director?['full_name'] as String? ?? 'Sultan Adinan',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    Text(
                      director?['username'] as String? ?? 'SultanAdinan1@Director.edu',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    Text(
                      director?['email'] as String? ?? 'wondetech404@gmail.com',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Ciro High School enforces strictly ONE active Director. You can transfer directorate authority to any available active faculty teacher.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              context.push('/admin/teachers');
            },
            icon: const Icon(Icons.people_outline, size: 16),
            label: const Text('Faculty List'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _showTransferDirectorDialog();
            },
            icon: const Icon(Icons.swap_horiz_rounded, size: 16),
            label: const Text('Transfer Directorate'),
          ),
        ],
      ),
    );
  }

  void _showTransferDirectorDialog() async {
    final client = Supabase.instance.client;
    final passwordController = TextEditingController();
    bool isSubmitting = false;
    bool obscurePassword = true;
    String? selectedTeacherId;
    String? selectedTeacherName;
    String? errorText;

    List<Map<String, dynamic>> eligibleTeachers = [];
    try {
      final rows = await client
          .from('users')
          .select('id, full_name, username, email, assigned_subject')
          .eq('role', AppRoles.teacher)
          .eq('is_active', true)
          .eq('approval_status', 'approved')
          .order('full_name');
      eligibleTeachers = List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('Error loading teachers for director transfer: $e');
    }

    if (!mounted) return;

    if (eligibleTeachers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No eligible active faculty teachers available for directorate transfer.'),
          backgroundColor: Color(0xFFD97706),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF6366F1), size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Transfer School Directorate',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Select an available active teacher to assume the position of School Director. The previous Director will transition to Faculty Teacher, preserving the strict 1-Director rule.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF92400E), height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text('Select New Director:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      hint: const Text('Choose an active teacher'),
                      initialValue: selectedTeacherId,
                      items: eligibleTeachers.map((t) {
                        final displayName = (t['full_name'] as String? ?? '').isNotEmpty
                            ? t['full_name'] as String
                            : (t['username'] as String? ?? t['email'] as String);
                        final subj = t['assigned_subject'] as String?;
                        return DropdownMenuItem<String>(
                          value: t['id'] as String,
                          child: Text(
                            '$displayName ${subj != null && subj.isNotEmpty ? "($subj)" : ""}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedTeacherId = val;
                          final match = eligibleTeachers.firstWhere((t) => t['id'] == val);
                          selectedTeacherName = (match['full_name'] as String? ?? '').isNotEmpty
                              ? match['full_name'] as String
                              : (match['username'] as String? ?? '');
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text('Your Admin Password to Confirm:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        hintText: 'Enter your password to authorize transfer',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                        ),
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (selectedTeacherId == null) {
                          setDialogState(() => errorText = 'Please select a teacher.');
                          return;
                        }
                        if (passwordController.text.isEmpty) {
                          setDialogState(() => errorText = 'Please enter your password to confirm.');
                          return;
                        }

                        setDialogState(() {
                          isSubmitting = true;
                          errorText = null;
                        });

                        try {
                          final res = await _activityService.transferDirectorPosition(
                            targetTeacherId: selectedTeacherId!,
                            currentPassword: passwordController.text,
                          );

                          if (dialogCtx.mounted) Navigator.pop(dialogCtx);

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(res['message']?.toString() ?? 'Director position transferred to $selectedTeacherName!'),
                                backgroundColor: const Color(0xFF10B981),
                              ),
                            );
                            _loadStats();
                          }
                        } catch (e) {
                          setDialogState(() {
                            isSubmitting = false;
                            errorText = e.toString().replaceAll('Exception: ', '');
                          });
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Transfer Directorate'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _postAnnouncementDialog() async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    String selectedAudience = 'all';
    bool isPinned = false;
    final currentUser = ref.read(authStateProvider).user;
    final authorName = currentUser?.fullName?.isNotEmpty == true
        ? currentUser!.fullName!
        : (currentUser?.username ?? 'Super Administrator');

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
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
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
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedAudience,
                    decoration: const InputDecoration(
                      labelText: 'Target Audience *',
                      prefixIcon: Icon(Icons.people_outline_rounded),
                    ),
                    items: audienceOptions
                        .map((opt) => DropdownMenuItem(
                              value: opt['value'],
                              child: Text(opt['label']!),
                            ))
                        .toList(),
                    onChanged: (v) => setDialogState(() => selectedAudience = v ?? 'all'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contentController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Announcement Message *',
                      hintText: 'Type your official message clearly here...',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Pin to Top of Feed',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Pins the announcement prominently for all users',
                        style: TextStyle(fontSize: 11)),
                    value: isPinned,
                    onChanged: (v) => setDialogState(() => isPinned = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Broadcast'),
              onPressed: () async {
                final title = titleController.text.trim();
                final content = contentController.text.trim();
                if (title.isEmpty || content.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter both title and message.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                Navigator.pop(ctx);
                try {
                  await _announcementService.createAnnouncement(
                    schoolId: _ciroSchoolId,
                    title: title,
                    content: content,
                    targetAudience: selectedAudience,
                    authorName: authorName,
                    authorRole: 'Super Administrator',
                    isPinned: isPinned,
                  );
                  _loadStats();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Announcement broadcasted successfully!'),
                        backgroundColor: Color(0xFF10B981),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to broadcast: $e'),
                        backgroundColor: Colors.red,
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
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Announcement'),
        content: Text('Are you sure you want to delete "${item.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
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
              content: Text('Announcement deleted.'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _openQuizzesModerationSheet() async {
    final client = Supabase.instance.client;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;

          return Container(
            height: MediaQuery.of(ctx).size.height * 0.85,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.quiz_rounded, color: Color(0xFF8B5CF6), size: 24),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Faculty Quizzes & Preparations',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: client
                        .from('quizzes')
                        .select('id, title, description, time_limit_minutes, is_published, teacher_id, target_grade, target_section, created_at')
                        .order('created_at', ascending: false),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      final quizzes = snapshot.data ?? [];
                      if (quizzes.isEmpty) {
                        return const Center(
                          child: Text('No quizzes created yet.', style: TextStyle(color: Colors.grey)),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: quizzes.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final q = quizzes[i];
                          final id = q['id']?.toString() ?? '';
                          final title = q['title']?.toString() ?? 'Untitled Quiz';
                          final grade = q['target_grade']?.toString() ?? 'All';
                          final sec = q['target_section']?.toString() ?? '';
                          final isPub = q['is_published'] == true;

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: (isPub ? const Color(0xFF10B981) : Colors.grey)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isPub ? Icons.fact_check_rounded : Icons.drafts_rounded,
                                    color: isPub ? const Color(0xFF10B981) : Colors.grey,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$grade $sec • ${isPub ? 'Published' : 'Draft'}',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                                  tooltip: 'Delete Outdated Quiz',
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: ctx,
                                      builder: (delCtx) => AlertDialog(
                                        title: const Text('Delete Quiz'),
                                        content: Text('Are you sure you want to delete "$title"?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(delCtx, false),
                                            child: const Text('Cancel'),
                                          ),
                                          FilledButton(
                                            style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                            onPressed: () => Navigator.pop(delCtx, true),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await client.from('quizzes').delete().eq('id', id);
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
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentUser = ref.watch(authStateProvider).user;
    final adminName = currentUser?.fullName?.isNotEmpty == true
        ? currentUser!.fullName!
        : (currentUser?.username ?? 'Super Administrator');

    return DashboardShell(
      title: 'Super Admin Portal',
      body: RefreshIndicator(
        onRefresh: _loadStats,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          children: [
            // 1. Institutional Luxury Welcome Header
            _buildSuperAdminHeader(isDark, adminName),
            const SizedBox(height: 24),

            // 2. System KPI Metrics Grid
            _buildMetricsSection(isDark),
            const SizedBox(height: 24),

            // 3. Quick Administrative Actions Grid
            _buildAdminActions(isDark),
            const SizedBox(height: 24),

            // 4. Ciro High School Grade Enrollment Totals
            _buildGradeStatsCard(isDark),
            const SizedBox(height: 24),

            // 5. Teacher Academic Activity Monitoring
            _buildTeacherAcademicActivityFeed(isDark),
            const SizedBox(height: 24),

            // 6. Recent Admin & Surveillance Activities
            _buildAuditLogsSection(isDark),
            const SizedBox(height: 24),

            // 7. Active School Announcements
            _buildAnnouncementsSection(isDark),
            const SizedBox(height: 36),
          ],
        ),
      ),
    );
  }

  Widget _buildSuperAdminHeader(bool isDark, String adminName) {
    final theme = Theme.of(context);

    return Container(
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
          Positioned.fill(
            child: Image.asset(
              'assets/images/home.jpeg',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: const Color(0xFF064E3B),
              ),
            ),
          ),
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
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
                            'CIRO HIGH SCHOOL · 1 ACTIVE SUPER ADMIN',
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
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                      ),
                      child: const Icon(
                        Icons.shield_rounded,
                        color: Color(0xFF34D399),
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFFBBF24), width: 1),
                            ),
                            child: const Text(
                              'SUPER ADMINISTRATOR',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6,
                                color: Color(0xFFFEF3C7),
                              ),
                            ),
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
                            'Institutional administrative control for Ciro High School. Manage directors, faculty, students, system configurations, and surveillance.',
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.person_add_rounded, size: 18),
                      label: const Text('Register User (Director/Staff/Student)'),
                      onPressed: () async {
                        await context.push('/admin/register-user');
                        if (mounted) _loadStats();
                      },
                    ),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.25),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.campaign_rounded, size: 18),
                      label: const Text('Post Announcement'),
                      onPressed: _postAnnouncementDialog,
                    ),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626).withValues(alpha: 0.3),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.security_update_warning_rounded, size: 18),
                      label: const Text('Transfer Ownership'),
                      onPressed: _showTransferSuperAdminOwnershipDialog,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ciro High School System Totals',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'Total System Users',
                subtitle: 'All registered institutional accounts',
                count: _totalUsersCount,
                loading: _loading,
                icon: Icons.groups_rounded,
                color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                title: 'School Director',
                subtitle: '1 Appointed Director (Strict Single Limit)',
                count: _directorCount == 0 ? 1 : _directorCount,
                loading: _loading,
                icon: Icons.manage_accounts_rounded,
                color: const Color(0xFF6366F1),
                onTap: _showDirectorOptionsDialog,
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
                onTap: () => context.push('/admin/teachers'),
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
                onTap: () => context.push('/teacher/students'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'Pending Approvals',
                subtitle: 'Student, teacher & staff requests',
                count: _pendingCount,
                loading: _loading,
                icon: Icons.pending_actions_rounded,
                color: const Color(0xFFF59E0B),
                onTap: () => context.push('/admin/approvals'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                title: 'Quizzes Prepared',
                subtitle: 'Teacher authoring only (Tap to moderate)',
                count: _quizCount,
                loading: _loading,
                icon: Icons.quiz_rounded,
                color: const Color(0xFF8B5CF6),
                onTap: _openQuizzesModerationSheet,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAdminActions(bool isDark) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Super Administrator Control Hub',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 12),
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
          title: 'User Rosters & Account Management',
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
          icon: Icons.shield_outlined,
          color: const Color(0xFF475569),
          title: 'Audit Logs & Account Surveillance',
          subtitle:
              'Inspect audit trails of all administrative actions, password resets, logins, and permission changes across Ciro High School.',
          buttonText: 'Inspect Audit Logs',
          onTap: () async {
            await context.push('/admin/audit-logs');
            if (mounted) _loadStats();
          },
        ),
        const SizedBox(height: 10),
        _ActionTile(
          icon: Icons.security_update_warning_rounded,
          color: const Color(0xFFDC2626),
          title: 'Transfer Super Admin Ownership',
          subtitle:
              'Transfer full Super Administrator institutional ownership to another eligible active account with password verification.',
          buttonText: 'Transfer Ownership',
          onTap: _showTransferSuperAdminOwnershipDialog,
        ),
      ],
    );
  }

  Widget _buildGradeStatsCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.bar_chart_rounded, color: Color(0xFF3B82F6), size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'Ciro High School Enrollment by Grade Level',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_gradeStats.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('Loading grade metrics...', style: TextStyle(color: Colors.grey))),
            )
          else
            LayoutBuilder(
              builder: (ctx, constraints) {
                final isWide = constraints.maxWidth > 550;
                final items = _gradeStats.map((g) {
                  final name = g['grade']?.toString() ?? 'Grade';
                  final count = (g['count'] as num?)?.toInt() ?? 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count Students',
                            style: const TextStyle(
                              color: Color(0xFF3B82F6),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList();

                if (isWide) {
                  return GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 10,
                    childAspectRatio: 3.5,
                    children: items,
                  );
                }

                return Column(
                  children: items
                      .map((item) => Padding(padding: const EdgeInsets.only(bottom: 8), child: item))
                      .toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTeacherAcademicActivityFeed(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.history_edu_rounded, color: Color(0xFF8B5CF6), size: 18),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Teacher Academic Activity Monitoring',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Supervise when teachers prepare quizzes, publish exams, and upload learning materials',
                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_teacherActivities.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text('No teacher academic activities recorded yet.',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _teacherActivities.length.clamp(0, 6),
              separatorBuilder: (_, _) => const Divider(height: 16),
              itemBuilder: (ctx, index) {
                final act = _teacherActivities[index];
                IconData actIcon = Icons.quiz_outlined;
                Color actColor = const Color(0xFF3B82F6);

                if (act.activityType == 'examination_published') {
                  actIcon = Icons.fact_check_rounded;
                  actColor = const Color(0xFF10B981);
                } else if (act.activityType == 'resource_uploaded') {
                  actIcon = Icons.menu_book_rounded;
                  actColor = const Color(0xFFF59E0B);
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: actColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(actIcon, size: 16, color: actColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                act.teacherName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              if (act.subject != null) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    act.subject!,
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                              const Spacer(),
                              Text(
                                act.status,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: act.status == 'Published' ? const Color(0xFF10B981) : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            act.description,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.grey[300] : const Color(0xFF334155),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Target: ${act.targetDisplay} • ${_formatRelativeTime(act.createdAt)}',
                            style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildAuditLogsSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent System & Admin Activities',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
      ],
    );
  }

  Widget _buildAnnouncementsSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.campaign_rounded, color: Color(0xFF10B981), size: 22),
                const SizedBox(width: 8),
                Text(
                  'Campus Announcements Feed',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                ),
              ],
            ),
            TextButton.icon(
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('New Notice'),
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
                      'No active announcements published for Ciro High School yet.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
      ],
    );
  }

  String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${time.day}/${time.month}/${time.year}';
  }
}

class _AnnouncementCard extends StatelessWidget {
  final SchoolAnnouncement announcement;
  final VoidCallback onDelete;

  const _AnnouncementCard({
    required this.announcement,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isPinned = announcement.isPinned;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPinned
              ? const Color(0xFF10B981)
              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          width: isPinned ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isPinned) ...[
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  announcement.targetAudience.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6366F1),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _formatDate(announcement.createdAt),
                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFF94A3B8)),
                onPressed: onDelete,
                tooltip: 'Delete announcement',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            announcement.title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            announcement.content,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.person_pin_rounded, size: 14, color: Color(0xFF059669)),
              const SizedBox(width: 4),
              Text(
                'By ${announcement.authorName} (${announcement.authorRole})',
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _ActivityListTile extends StatelessWidget {
  const _ActivityListTile({required this.log});

  final AuditLog log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final actionLabel = _formatAction(log.action);
    final target = log.targetUser ?? 'System';
    final detailsMap = log.details;
    final actor = detailsMap?['actor_name'] as String? ?? 'Admin';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _actionColor(log.action).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_actionIcon(log.action), color: _actionColor(log.action), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$actionLabel · $target',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  'By $actor',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Text(
            _formatTimestamp(log.createdAt),
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF94A3B8),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  String _formatAction(String action) {
    switch (action) {
      case 'user_created':
        return 'Created Account';
      case 'user_approved':
        return 'Approved Account';
      case 'user_declined':
        return 'Declined Account';
      case 'user_deleted':
        return 'Deleted Account';
      case 'password_reset':
        return 'Password Reset';
      case 'super_admin_ownership_transferred':
        return 'Transferred Super Admin';
      case 'director_position_transferred':
        return 'Transferred Director';
      case 'user_suspended':
        return 'Suspended User';
      case 'user_activated':
        return 'Activated User';
      default:
        return action.replaceAll('_', ' ');
    }
  }

  IconData _actionIcon(String action) {
    if (action.contains('approved')) return Icons.check_circle_rounded;
    if (action.contains('declined') || action.contains('deleted')) return Icons.delete_outline_rounded;
    if (action.contains('password')) return Icons.lock_reset_rounded;
    if (action.contains('transferred')) return Icons.swap_horiz_rounded;
    if (action.contains('suspended')) return Icons.pause_circle_outline_rounded;
    return Icons.person_add_rounded;
  }

  Color _actionColor(String action) {
    if (action.contains('approved')) return const Color(0xFF10B981);
    if (action.contains('declined') || action.contains('deleted')) return const Color(0xFFEF4444);
    if (action.contains('password')) return const Color(0xFFF59E0B);
    if (action.contains('transferred')) return const Color(0xFF6366F1);
    return const Color(0xFF64748B);
  }

  String _formatTimestamp(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}';
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final int count;
  final bool loading;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _MetricCard({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.loading,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final content = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.2) : const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
            loading ? '...' : '$count',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: content,
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.2) : const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: color,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  onPressed: onTap,
                  child: Text(buttonText, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
