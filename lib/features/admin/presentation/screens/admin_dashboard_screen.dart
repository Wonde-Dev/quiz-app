import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/services/audit_log_service.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/shared/models/audit_log.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  int _totalUsersCount = 0;
  int _studentCount = 0;
  int _teacherCount = 0;
  int _quizCount = 0;
  int _pendingCount = 0;
  List<AuditLog> _recentLogs = [];
  bool _loading = true;
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
    } catch (e) {
      debugPrint('Realtime user subscription notice: $e');
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
    final auditService = AuditLogService();

    try {
      final results = await Future.wait<dynamic>([
        client.from('users').select('id, role, is_active, approval_status'),
        client.from('quizzes').select('id').eq('is_published', true),
        auditService.fetchLogs(limit: 5),
      ]);

      if (!mounted) return;
      final allUsers = (results[0] as List).cast<Map<String, dynamic>>();
      final publishedQuizzes = results[1] as List;
      final recentLogs = results[2] as List<AuditLog>;

      // Active users: count anyone where is_active is not explicitly false
      final activeUsers = allUsers.where((u) => u['is_active'] != false).toList();
      final studentCount = activeUsers.where((u) => u['role'] == 'student').length;
      final teacherCount = activeUsers.where((u) => u['role'] == 'teacher').length;
      final totalUsers = activeUsers.length;
      final pendingCount = allUsers.where((u) => u['approval_status'] == 'pending').length;

      setState(() {
        _studentCount = studentCount;
        _teacherCount = teacherCount;
        _totalUsersCount = totalUsers;
        _quizCount = publishedQuizzes.length;
        _pendingCount = pendingCount;
        _recentLogs = recentLogs;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Admin stats loading note: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentUser = ref.watch(authStateProvider).user;
    final adminName = currentUser?.fullName?.isNotEmpty == true
        ? currentUser!.fullName!
        : currentUser?.username ?? 'Administrator';

    return DashboardShell(
      title: 'Admin Control Center',
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
                                    'SYSTEM ACTIVE · ENCRYPTED',
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
                                  Text(
                                    'Hello, $adminName',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Full administrator access, role management, and audit surveillance.',
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
                        label: const Text('Register User (Admin/Staff/Student)'),
                        onPressed: () async {
                          await context.push('/admin/register-user');
                          if (mounted) _loadStats();
                        },
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
                        icon: const Icon(Icons.history_rounded, size: 18),
                        label: const Text('Audit Logs'),
                        onPressed: () async {
                          await context.push('/admin/audit-logs');
                          if (mounted) _loadStats();
                        },
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

            // Live Metrics Overview
            Text(
              'Institutional Metrics',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    title: 'Total Users',
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
                    title: 'Students',
                    count: _studentCount,
                    loading: _loading,
                    icon: Icons.school_rounded,
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
                    title: 'Teachers',
                    count: _teacherCount,
                    loading: _loading,
                    icon: Icons.co_present_rounded,
                    color: const Color(0xFF10B981),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricCard(
                    title: 'Quizzes',
                    count: _quizCount,
                    loading: _loading,
                    icon: Icons.quiz_rounded,
                    color: const Color(0xFF8B5CF6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

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
                    '$_pendingCount Pending Teacher Approval${_pendingCount > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF92400E),
                    ),
                  ),
                  subtitle: const Text(
                    'Newly registered teachers require verification',
                    style: TextStyle(color: Color(0xFFB45309)),
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

            // Main Action Cards
            _ActionTile(
              icon: Icons.person_add_alt_1_rounded,
              color: const Color(0xFF10B981),
              title: 'Register New User (Admin, Teacher, Student)',
              subtitle:
                  'Directly create and activate Administrator, Teacher, or Student accounts with instant institutional credentials.',
              buttonText: 'Register User',
              onTap: () async {
                await context.push('/admin/register-user');
                if (mounted) _loadStats();
              },
            ),
            const SizedBox(height: 10),

            _ActionTile(
              icon: Icons.manage_accounts_rounded,
              color: const Color(0xFF6366F1),
              title: 'User Rosters & Deletion',
              subtitle:
                  'Browse registered student and teacher directories, view profiles, or delete user accounts.',
              buttonText: 'Manage Users',
              onTap: () async {
                await context.push('/teacher/students');
                if (mounted) _loadStats();
              },
            ),
            const SizedBox(height: 10),

            _ActionTile(
              icon: Icons.lock_reset_rounded,
              color: const Color(0xFF0284C7),
              title: 'Reset User Passwords',
              subtitle:
                  'Instant password resets with generated temporary credentials matching institution format.',
              buttonText: 'Reset Tool',
              onTap: () async {
                await context.push('/teacher/reset-passwords');
                if (mounted) _loadStats();
              },
            ),
            const SizedBox(height: 10),

            _ActionTile(
              icon: Icons.how_to_reg_rounded,
              color: const Color(0xFF10B981),
              title: 'Review Registration Requests',
              subtitle:
                  'Review, approve, or reject new student and teacher registration applications.',
              buttonText: 'Registration Approvals',
              onTap: () async {
                await context.push('/admin/approvals');
                if (mounted) _loadStats();
              },
            ),
            const SizedBox(height: 10),

            _ActionTile(
              icon: Icons.co_present_rounded,
              color: const Color(0xFF059669),
              title: 'Faculty Directory & Passwords',
              subtitle:
                  'View approved teachers, assign subjects, and reset faculty passwords directly.',
              buttonText: 'Teachers Directory',
              onTap: () async {
                await context.push('/admin/teachers');
                if (mounted) _loadStats();
              },
            ),
            const SizedBox(height: 10),

            _ActionTile(
              icon: Icons.class_outlined,
              color: const Color(0xFF0D9488),
              title: 'Class & Section Assignments',
              subtitle:
                  'Manage school grades, classroom sections, and course allocations.',
              buttonText: 'Class Management',
              onTap: () async {
                await context.push('/admin/classes');
                if (mounted) _loadStats();
              },
            ),
            const SizedBox(height: 10),

            _ActionTile(
              icon: Icons.history_rounded,
              color: const Color(0xFF0F172A),
              title: 'System Activity & Audit Logs',
              subtitle:
                  'Chronological activity feed tracking accounts, password resets, and audit actions.',
              buttonText: 'Audit Surveillance',
              onTap: () async {
                await context.push('/admin/audit-logs');
                if (mounted) _loadStats();
              },
            ),
            const SizedBox(height: 32),
          ],
        ),
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
  });

  final String title;
  final int count;
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
