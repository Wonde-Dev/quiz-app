import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/core/services/student_password_reset_service.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _searchController = TextEditingController();
  final _resetService = StudentPasswordResetService();

  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  bool _loading = true;
  String? _error;
  String? _resettingId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilter);
    _loadStudents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final currentUser = ref.read(authStateProvider).user;
    if (currentUser == null) {
      setState(() {
        _error = 'Please sign in to view students.';
        _loading = false;
      });
      return;
    }

    try {
      final client = Supabase.instance.client;
      var query = client
          .from('users')
          .select('id, username, full_name, role, school_id')
          .eq('role', AppRoles.student);

      if (currentUser.role != AppRoles.admin && currentUser.schoolId != null) {
        query = query.eq('school_id', currentUser.schoolId!);
      }

      final rows = await query.order('full_name');
      final list = List<Map<String, dynamic>>.from(rows)
          .where((user) => user['id'] != currentUser.id)
          .toList();

      if (!mounted) return;
      setState(() {
        _students = list;
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load students: $e';
        _loading = false;
      });
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredStudents = List.from(_students);
      } else {
        _filteredStudents = _students.where((s) {
          final name = (s['full_name'] as String? ?? '').toLowerCase();
          final username = (s['username'] as String? ?? '').toLowerCase();
          return name.contains(query) || username.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _resetPassword(Map<String, dynamic> student) async {
    final studentId = student['id'] as String;
    setState(() => _resettingId = studentId);

    try {
      final result = await _resetService.resetAccounts([studentId]);

      if (!mounted) return;

      if (result.results.isNotEmpty) {
        final newPassword = result.results.first.temporaryPassword;
        _showCredentialsDialog(student, newPassword);
      } else if (result.failures.isNotEmpty) {
        _showErrorSnackBar(result.failures.first.message);
      } else {
        _showErrorSnackBar('Password reset did not return new credentials.');
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('Reset failed: $e');
    } finally {
      if (mounted) setState(() => _resettingId = null);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showCredentialsDialog(
    Map<String, dynamic> student,
    String newPassword,
  ) {
    final name =
        student['full_name'] as String? ??
        student['username'] as String? ??
        'Student';
    final username = student['username'] as String? ?? '';
    bool copied = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final theme = Theme.of(ctx);
          return AlertDialog(
            icon: Icon(
              Icons.lock_reset_rounded,
              size: 40,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Password Reset Successful'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Temporary password generated for:',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '$name ($username)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          newPassword,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy password',
                        icon: Icon(
                          copied ? Icons.check_circle : Icons.copy_rounded,
                          color: copied
                              ? Colors.green
                              : theme.colorScheme.primary,
                        ),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: newPassword),
                          );
                          setDialogState(() => copied = true);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Give this temporary password to the student. They will be asked to update their password upon sign-in.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTeacher = ref.watch(authStateProvider).user?.role == AppRoles.teacher;

    return DashboardShell(
      title: 'Reset student passwords',
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isTeacher
                      ? 'Select a student to reset their password.'
                      : 'Reset student passwords across the school.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by student name or username...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: _searchController.clear,
                          )
                        : null,
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildBody(context),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
                onPressed: _loadStudents,
              ),
            ],
          ),
        ),
      );
    }

    if (_students.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.people_outline_rounded,
                size: 56,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                'No students found in your school.',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredStudents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No students matching "${_searchController.text}"',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadStudents,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _filteredStudents.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final student = _filteredStudents[i];
          final id = student['id'] as String;
          final fullName = student['full_name'] as String? ?? '';
          final username = student['username'] as String? ?? '';
          final isResetting = _resettingId == id;
          final displayName = fullName.isNotEmpty ? fullName : username;

          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 6,
              ),
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'S',
                  style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                displayName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '@$username',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              trailing: isResetting
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : FilledButton.tonalIcon(
                      icon: const Icon(Icons.lock_reset_rounded, size: 18),
                      label: const Text('Reset'),
                      onPressed: _resettingId != null
                          ? null
                          : () => _resetPassword(student),
                    ),
            ),
          );
        },
      ),
    );
  }
}
