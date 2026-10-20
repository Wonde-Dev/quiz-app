import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  int _studentCount = 0;
  int _teacherCount = 0;
  int _quizCount = 0;
  int _pendingCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    final client = Supabase.instance.client;

    try {
      final results = await Future.wait([
        client.from('users').select('id').eq('role', 'student'),
        client.from('users').select('id').eq('role', 'teacher'),
        client.from('quizzes').select('id').eq('is_published', true),
        client.from('users').select('id').eq('approval_status', 'pending'),
      ]);

      if (!mounted) return;
      setState(() {
        _studentCount = (results[0] as List).length;
        _teacherCount = (results[1] as List).length;
        _quizCount = (results[2] as List).length;
        _pendingCount = (results[3] as List).length;
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
    final currentUser = ref.watch(authStateProvider).user;
    final adminName = currentUser?.fullName?.isNotEmpty == true
        ? currentUser!.fullName!
        : currentUser?.username ?? 'Administrator';

    return DashboardShell(
      title: 'Admin control center',
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
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
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
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.admin_panel_settings_rounded,
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
                              'Hello, $adminName',
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Full administrator access & school control',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Live Metrics Overview
            Text(
              'School Overview',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
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
                    color: const Color(0xFF5847D8),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricCard(
                    title: 'Teachers',
                    count: _teacherCount,
                    loading: _loading,
                    icon: Icons.person_outline_rounded,
                    color: Colors.teal.shade700,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricCard(
                    title: 'Quizzes',
                    count: _quizCount,
                    loading: _loading,
                    icon: Icons.quiz_rounded,
                    color: Colors.indigo.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            if (_pendingCount > 0) ...[
              Card(
                color: Colors.amber.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.amber.shade300),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.amber.shade200,
                    child: Icon(Icons.notifications_active_rounded,
                        color: Colors.amber.shade900),
                  ),
                  title: Text(
                    '$_pendingCount Pending Role Request${_pendingCount > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                    ),
                  ),
                  subtitle: const Text(
                    'Teachers are waiting for administrator approval',
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: () => context.push('/admin/approvals'),
                    child: const Text('Review'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            const SizedBox(height: 16),
            Text(
              'Management & Control Actions',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // Main Action Cards
            _ActionTile(
              icon: Icons.manage_accounts_rounded,
              color: const Color(0xFF5847D8),
              title: 'Register & Manage Users',
              subtitle:
                  'Register any student, teacher, or admin account, reset passwords, and remove accounts.',
              buttonText: 'Manage Users',
              onTap: () => context.push('/teacher/students'),
            ),
            const SizedBox(height: 10),

            _ActionTile(
              icon: Icons.lock_reset_rounded,
              color: Colors.blue.shade700,
              title: 'Reset User Passwords',
              subtitle:
                  'Instant password resets with generated temporary credentials and one-tap copy.',
              buttonText: 'Reset Tool',
              onTap: () => context.push('/teacher/reset-passwords'),
            ),
            const SizedBox(height: 10),

            _ActionTile(
              icon: Icons.add_circle_outline_rounded,
              color: Colors.purple.shade700,
              title: 'Create & Publish Quiz',
              subtitle:
                  'Build exams selecting Grade 9 to 12 and Section A, B, C (or custom section).',
              buttonText: 'Create Quiz',
              onTap: () => context.push('/teacher/quizzes/new'),
            ),
            const SizedBox(height: 10),

            _ActionTile(
              icon: Icons.fact_check_rounded,
              color: Colors.green.shade700,
              title: 'Evaluate Quizzes & Results',
              subtitle:
                  'Review student attempts, evaluate questions, adjust scores, and see pass/fail metrics.',
              buttonText: 'Evaluate',
              onTap: () => context.push('/teacher/results'),
            ),
            const SizedBox(height: 10),

            _ActionTile(
              icon: Icons.class_outlined,
              color: Colors.orange.shade800,
              title: 'Class & Section Assignments',
              subtitle:
                  'Manage school grades, classroom sections, and course allocations.',
              buttonText: 'Classes',
              onTap: () => context.push('/admin/classes'),
            ),
            const SizedBox(height: 10),

            _ActionTile(
              icon: Icons.verified_user_outlined,
              color: Colors.teal.shade800,
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
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 8),
            loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    '$count',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
            const SizedBox(height: 2),
            Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
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
