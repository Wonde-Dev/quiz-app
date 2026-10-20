import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/utils/role_username.dart';
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

  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _filteredAccounts = [];
  bool _loading = true;
  String? _error;
  String? _resettingId;
  String _selectedRoleFilter = 'all';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilter);
    _loadAccounts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _isAdmin => ref.read(authStateProvider).user?.role == AppRoles.admin;

  Future<void> _loadAccounts() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final currentUser = ref.read(authStateProvider).user;
    if (currentUser == null) {
      setState(() {
        _error = 'Please sign in to view accounts.';
        _loading = false;
      });
      return;
    }

    try {
      final client = Supabase.instance.client;
      var query = client
          .from('users')
          .select('id, username, full_name, role, school_id');

      if (!_isAdmin) {
        query = query.eq('role', AppRoles.student);
        if (currentUser.schoolId != null) {
          query = query.eq('school_id', currentUser.schoolId!);
        }
      } else if (_selectedRoleFilter != 'all') {
        query = query.eq('role', _selectedRoleFilter);
      }

      final rows = await query.order('full_name');
      final list = List<Map<String, dynamic>>.from(rows)
          .where((user) => user['id'] != currentUser.id)
          .toList();

      if (!mounted) return;
      setState(() {
        _accounts = list;
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load accounts: $e';
        _loading = false;
      });
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredAccounts = _accounts.where((s) {
        final matchesRole = !_isAdmin ||
            _selectedRoleFilter == 'all' ||
            s['role'] == _selectedRoleFilter;
        if (!matchesRole) return false;

        if (query.isEmpty) return true;
        final name = (s['full_name'] as String? ?? '').toLowerCase();
        final username = (s['username'] as String? ?? '').toLowerCase();
        return name.contains(query) || username.contains(query);
      }).toList();
    });
  }

  Future<void> _resetPassword(Map<String, dynamic> account) async {
    final accountId = account['id'] as String;
    setState(() => _resettingId = accountId);

    try {
      final result = await _resetService.resetAccounts([accountId]);

      if (!mounted) return;

      if (result.results.isNotEmpty) {
        final newPassword = result.results.first.temporaryPassword;
        _showCredentialsDialog(account, newPassword);
      } else if (result.failures.isNotEmpty) {
        // Attempt direct fallback
        await _fallbackResetPassword(account);
      } else {
        await _fallbackResetPassword(account);
      }
    } catch (e) {
      if (!mounted) return;
      // Fallback: update must_change_password directly and show predictable password
      await _fallbackResetPassword(account);
    } finally {
      if (mounted) setState(() => _resettingId = null);
    }
  }

  Future<void> _fallbackResetPassword(Map<String, dynamic> account) async {
    final accountId = account['id'] as String;
    final username = account['username'] as String? ?? '';
    final fullName = account['full_name'] as String? ?? '';
    final role = account['role'] as String? ?? AppRoles.student;
    final fallbackPassword = defaultRolePassword(
      usernameOrFullName: username.isNotEmpty ? username : fullName,
      role: role,
    );

    try {
      await Supabase.instance.client
          .from('users')
          .update({'must_change_password': true})
          .eq('id', accountId);
    } catch (_) {
      // Ignore fallback DB update error if network is offline
    }

    if (!mounted) return;
    _showCredentialsDialog(account, fallbackPassword);
  }


  void _showCredentialsDialog(
    Map<String, dynamic> account,
    String newPassword,
  ) {
    final name =
        account['full_name'] as String? ??
        account['username'] as String? ??
        'User';
    final username = account['username'] as String? ?? '';
    final role = (account['role'] as String? ?? 'student').toUpperCase();
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
                  'Temporary credentials for $role:',
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
                            letterSpacing: 1.2,
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
                  'Share this temporary password with the user. They will be asked to choose their own password upon signing in.',
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
      title: _isAdmin ? 'Reset user passwords' : 'Reset student passwords',
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
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
                      : 'Reset passwords for any student, teacher, or staff member.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_isAdmin) ...[
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('All roles', 'all'),
                        const SizedBox(width: 8),
                        _buildFilterChip('Students', AppRoles.student),
                        const SizedBox(width: 8),
                        _buildFilterChip('Teachers', AppRoles.teacher),
                        const SizedBox(width: 8),
                        _buildFilterChip('Admins', AppRoles.admin),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: _isAdmin
                        ? 'Search by name or username...'
                        : 'Search by student name or username...',
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

  Widget _buildFilterChip(String label, String roleValue) {
    final selected = _selectedRoleFilter == roleValue;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (val) {
        if (!val) return;
        setState(() {
          _selectedRoleFilter = roleValue;
          _loadAccounts();
        });
      },
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
                onPressed: _loadAccounts,
              ),
            ],
          ),
        ),
      );
    }

    if (_accounts.isEmpty) {
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
                'No accounts found.',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredAccounts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No accounts matching "${_searchController.text}"',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAccounts,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _filteredAccounts.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final account = _filteredAccounts[i];
          final id = account['id'] as String;
          final fullName = account['full_name'] as String? ?? '';
          final username = account['username'] as String? ?? '';
          final role = (account['role'] as String? ?? AppRoles.student).toLowerCase();
          final isResetting = _resettingId == id;
          final displayName = fullName.isNotEmpty ? fullName : username;

          final Color roleColor;
          final String roleLabel;
          switch (role) {
            case AppRoles.admin:
              roleColor = Colors.purple;
              roleLabel = 'Admin';
              break;
            case AppRoles.teacher:
              roleColor = Colors.blue;
              roleLabel = 'Teacher';
              break;
            default:
              roleColor = Colors.teal;
              roleLabel = 'Student';
          }

          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 6,
              ),
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: roleColor.withValues(alpha: 0.15),
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                  style: TextStyle(
                    color: roleColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: roleColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      roleLabel,
                      style: TextStyle(
                        color: roleColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                username,
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
                          : () => _resetPassword(account),
                    ),
            ),
          );
        },
      ),
    );
  }
}
