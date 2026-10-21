import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/services/student_password_reset_service.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class TeacherManagementScreen extends ConsumerStatefulWidget {
  const TeacherManagementScreen({super.key});

  @override
  ConsumerState<TeacherManagementScreen> createState() =>
      _TeacherManagementScreenState();
}

class _TeacherManagementScreenState
    extends ConsumerState<TeacherManagementScreen> {
  final _searchController = TextEditingController();
  final _resetService = StudentPasswordResetService();
  late Future<List<Map<String, dynamic>>> _teachersFuture;
  bool _isResetting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _teachersFuture = _loadTeachers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadTeachers() async {
    final client = Supabase.instance.client;
    final rows = await client
        .from('users')
        .select('id, full_name, username, email, school_id, approval_status, is_active, created_at, schools(name)')
        .eq('role', AppRoles.teacher)
        .order('full_name', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _resetTeacherPassword(Map<String, dynamic> teacher) async {
    final id = teacher['id'] as String;
    final name = teacher['full_name'] as String? ?? teacher['username'] as String? ?? 'Teacher';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        title: const Text('Reset Teacher Password?'),
        content: Text(
          'This will generate a secure temporary password matching institutional format for $name. '
          'They will be asked to update their password upon next sign in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset Password'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isResetting = true;
      _error = null;
    });

    try {
      final batch = await _resetService.resetAccounts([id]);
      if (!mounted) return;
      setState(() => _teachersFuture = _loadTeachers());

      if (batch.results.isEmpty) {
        setState(() => _error = 'Could not reset password for this teacher.');
        return;
      }
      final result = batch.results.first;

      // Show credentials dialog
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 30),
              ),
              const SizedBox(height: 14),
              const Text(
                'Password Reset Successful',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
              ),
              const SizedBox(height: 6),
              Text(
                'Temporary password for $name:',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: SelectableText(
                  result.temporaryPassword,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Color(0xFF0F172A),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy Password'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: result.temporaryPassword));
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Password copied to clipboard!'),
                            duration: Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not reset password: $e');
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DashboardShell(
      title: 'Teacher Directory & Credentials',
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _teachersFuture = _loadTeachers()),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Header summary card
            Container(
              padding: const EdgeInsets.all(20),
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
                        ? Colors.black.withValues(alpha: 0.3)
                        : const Color(0xFF0F172A).withValues(alpha: 0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.co_present_rounded,
                      color: Color(0xFF10B981),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Teacher Administration',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'View verified faculty members, manage institutional access, and reset passwords.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Search bar
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search faculty by name or username...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 16),

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
              ),
              const SizedBox(height: 12),
            ],

            FutureBuilder<List<Map<String, dynamic>>>(
              future: _teachersFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Could not load faculty directory: ${snapshot.error}'),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
                }

                final teachers = snapshot.data!;
                final q = _searchController.text.trim().toLowerCase();
                final filtered = teachers.where((t) {
                  if (q.isEmpty) return true;
                  final name = t['full_name']?.toString().toLowerCase() ?? '';
                  final username = t['username']?.toString().toLowerCase() ?? '';
                  final email = t['email']?.toString().toLowerCase() ?? '';
                  return name.contains(q) || username.contains(q) || email.contains(q);
                }).toList();

                if (filtered.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(36),
                      child: Center(
                        child: Text(
                          teachers.isEmpty ? 'No teachers found in the system.' : 'No faculty matches your search.',
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    for (final teacher in filtered) ...[
                      _TeacherDirectoryCard(
                        teacher: teacher,
                        isResetting: _isResetting,
                        onResetPassword: () => _resetTeacherPassword(teacher),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TeacherDirectoryCard extends StatelessWidget {
  const _TeacherDirectoryCard({
    required this.teacher,
    required this.isResetting,
    required this.onResetPassword,
  });

  final Map<String, dynamic> teacher;
  final bool isResetting;
  final VoidCallback onResetPassword;

  @override
  Widget build(BuildContext context) {
    final name = teacher['full_name'] as String? ?? 'Teacher';
    final username = teacher['username'] as String? ?? '';
    final school = (teacher['schools'] as Map<String, dynamic>?)?['name'] as String? ?? 'School';
    final status = teacher['approval_status'] as String? ?? 'approved';
    final isApproved = status == 'approved';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.co_present_rounded, color: Color(0xFF10B981), size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (isApproved ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isApproved ? 'Approved' : 'Pending',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isApproved ? const Color(0xFF059669) : const Color(0xFFD97706),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    username,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_city_rounded, size: 13, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 4),
                      Text(
                        school,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: isResetting ? null : onResetPassword,
                    icon: const Icon(Icons.lock_reset_rounded, size: 16),
                    label: const Text('Reset Teacher Password', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
