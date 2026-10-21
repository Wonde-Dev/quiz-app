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
  int _studentCount = 0;
  int _teacherCount = 0;
  int _quizCount = 0;
  int _pendingCount = 0;
  List<AuditLog> _recentLogs = [];
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
    final auditService = AuditLogService();

    try {
      final results = await Future.wait<dynamic>([
        client.from('users').select('id').eq('role', 'student'),
        client.from('users').select('id').eq('role', 'teacher'),
        client.from('quizzes').select('id').eq('is_published', true),
        client.from('users').select('id').eq('approval_status', 'pending'),
        auditService.fetchLogs(limit: 5),
      ]);

      if (!mounted) return;
      setState(() {
        _studentCount = (results[0] as List).length;
        _teacherCount = (results[1] as List).length;
        _quizCount = (results[2] as List).length;
        _pendingCount = (results[3] as List).length;
        _recentLogs = results[4] as List<AuditLog>;
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
            // Welcome Header - Luxury White Card
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
                      // Status Badge with pulsing green indicator
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
                              'SYSTEM ACTIVE · ENCRYPTED',
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
                        tooltip: 'Refresh system stats',
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
                          Icons.shield_rounded,
                          color: Color(0xFF0F172A),
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
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Full administrator access, role management, and audit surveillance.',
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
                        icon: const Icon(Icons.person_add_rounded, size: 18),
                        label: const Text('Create User Account'),
                        onPressed: () => context.push('/teacher/students'),
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
                        onPressed: () => context.push('/admin/audit-logs'),
                      ),
                    ],
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
                    title: 'Students',
                    count: _studentCount,
                    loading: _loading,
                    icon: Icons.school_rounded,
                    color: const Color(0xFF6366F1),
                  ),
                ),
                const SizedBox(width: 10),
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
                    onPressed: () => context.push('/admin/approvals'),
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
                  onPressed: () => context.push('/admin/audit-logs'),
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
              icon: Icons.manage_accounts_rounded,
              color: const Color(0xFF6366F1),
              title: 'Register & Manage Users',
              subtitle:
                  'Register any student, teacher, or admin account, reset passwords, and remove accounts.',
              buttonText: 'Manage Users',
              onTap: () => context.push('/teacher/students'),
            ),
            const SizedBox(height: 10),

            _ActionTile(
              icon: Icons.lock_reset_rounded,
              color: const Color(0xFF0284C7),
              title: 'Reset User Passwords',
              subtitle:
                  'Instant password resets with generated temporary credentials matching institution format.',
              buttonText: 'Reset Tool',
              onTap: () => context.push('/teacher/reset-passwords'),
            ),
            const SizedBox(height: 10),

            _ActionTile(
              icon: Icons.history_rounded,
              color: const Color(0xFF0F172A),
              title: 'System Activity & Audit Logs',
              subtitle:
                  'Chronological activity feed tracking accounts, password resets, and exam actions.',
              buttonText: 'Audit Surveillance',
              onTap: () => context.push('/admin/audit-logs'),
            ),
            const SizedBox(height: 10),

            _ActionTile(
              icon: Icons.add_circle_outline_rounded,
              color: const Color(0xFF8B5CF6),
              title: 'Create & Publish Quiz',
              subtitle:
                  'Build exams selecting Grade 9 to 12 and Section A, B, C (or custom section).',
              buttonText: 'Create Quiz',
              onTap: () => context.push('/teacher/quizzes/new'),
            ),
            const SizedBox(height: 10),

            _ActionTile(
              icon: Icons.fact_check_rounded,
              color: const Color(0xFF10B981),
              title: 'Evaluate Quizzes & Results',
              subtitle:
                  'Review student attempts, evaluate questions, adjust scores, and inspect images.',
              buttonText: 'Evaluate',
              onTap: () => context.push('/teacher/results'),
            ),
            const SizedBox(height: 10),

            _ActionTile(
              icon: Icons.co_present_rounded,
              color: const Color(0xFF10B981),
              title: 'Faculty Directory & Passwords',
              subtitle:
                  'View approved teachers, assign subjects, and reset faculty passwords directly.',
              buttonText: 'Teachers',
              onTap: () => context.push('/admin/teachers'),
            ),
            const SizedBox(height: 10),

            _ActionTile(
              icon: Icons.class_outlined,
              color: const Color(0xFFF59E0B),
              title: 'Class & Section Assignments',
              subtitle:
                  'Manage school grades, classroom sections, and course allocations.',
              buttonText: 'Classes',
              onTap: () => context.push('/admin/classes'),
            ),
            const SizedBox(height: 10),

            _ActionTile(
              icon: Icons.verified_user_outlined,
              color: const Color(0xFF14B8A6),
              title: 'Review Role Requests',
              subtitle:
                  'Approve or decline elevated access requests from newly registered accounts.',
              buttonText: 'Approvals',
              onTap: () => context.push('/admin/approvals'),
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
