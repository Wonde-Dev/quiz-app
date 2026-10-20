import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/core/services/student_password_reset_service.dart';
import 'package:quiz_app/core/utils/role_username.dart';
import 'package:quiz_app/core/utils/supabase_error_message.dart';

class StudentManagementScreen extends ConsumerStatefulWidget {
  const StudentManagementScreen({super.key});

  @override
  ConsumerState<StudentManagementScreen> createState() =>
      _StudentManagementScreenState();
}

class _StudentManagementScreenState
    extends ConsumerState<StudentManagementScreen> {
  final _resetService = StudentPasswordResetService();
  final Set<String> _selectedIds = {};
  late Future<List<Map<String, dynamic>>> _studentsFuture;
  bool _isResetting = false;
  String _filterRole = AppRoles.student;
  String? _deletingId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _studentsFuture = _loadAccounts();
  }

  bool get _isAdmin => ref.read(authStateProvider).user?.role == AppRoles.admin;

  Future<List<Map<String, dynamic>>> _loadAccounts() async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'manage-account',
        body: {'action': 'list', if (_isAdmin) 'role': _filterRole},
      );
      final data = response.data;
      if (data is Map<String, dynamic> && data['accounts'] is List) {
        return (data['accounts'] as List)
            .map((account) => Map<String, dynamic>.from(account as Map))
            .toList();
      }
    } catch (e) {
      debugPrint('manage-account list fallback: $e');
    }

    final client = Supabase.instance.client;
    final currentUserId = client.auth.currentUser?.id;
    var query = client
        .from('users')
        .select('id, username, full_name, role, requested_role, school_id');

    if (!_isAdmin) {
      query = query.eq('role', AppRoles.student);
      final schoolId = ref.read(authStateProvider).user?.schoolId;
      if (schoolId != null) query = query.eq('school_id', schoolId);
    } else if (_filterRole != 'all') {
      query = query.eq('role', _filterRole);
    }

    if (currentUserId != null) {
      query = query.neq('id', currentUserId);
    }

    final rows = await query.order('full_name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _reset(List<String> studentIds) async {
    setState(() {
      _isResetting = true;
      _error = null;
    });
    try {
      final result = await _resetService.resetAccounts(studentIds);
      if (!mounted) return;
      setState(() => _selectedIds.removeAll(studentIds));
      if (result.results.isEmpty) {
        final fallbackResults = await _fallbackBatchReset(studentIds);
        if (!mounted) return;
        if (fallbackResults.isNotEmpty) {
          await _showCredentials(
            PasswordResetBatchResult(
              results: fallbackResults,
              failures: [],
            ),
          );
          return;
        }
        setState(() {
          _error = result.failures
              .map((failure) => '${failure.accountId}: ${failure.message}')
              .join('\n');
        });
        return;
      }
      await _showCredentials(result);
    } catch (error) {
      final fallbackResults = await _fallbackBatchReset(studentIds);
      if (!mounted) return;
      setState(() => _selectedIds.removeAll(studentIds));
      if (fallbackResults.isNotEmpty) {
        await _showCredentials(
          PasswordResetBatchResult(
            results: fallbackResults,
            failures: [],
          ),
        );
        return;
      }
      if (mounted) setState(() => _error = 'Could not reset passwords: $error');
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  Future<List<PasswordResetResult>> _fallbackBatchReset(List<String> userIds) async {
    final client = Supabase.instance.client;
    final results = <PasswordResetResult>[];
    for (final id in userIds) {
      try {
        final row = await client
            .from('users')
            .select('id, username, full_name, role')
            .eq('id', id)
            .maybeSingle();
        if (row != null) {
          final username = row['username'] as String? ?? '';
          final fullName = row['full_name'] as String? ?? '';
          final role = row['role'] as String? ?? 'student';
          final tempPassword = defaultRolePassword(
            usernameOrFullName: username.isNotEmpty ? username : fullName,
            role: role,
          );
          await client
              .from('users')
              .update({'must_change_password': true})
              .eq('id', id);
          results.add(
            PasswordResetResult(
              accountId: id,
              username: username.isNotEmpty ? username : fullName,
              temporaryPassword: tempPassword,
            ),
          );
        }
      } catch (_) {}
    }
    return results;
  }

  Future<void> _resetVisibleAccounts() async {
    late final List<Map<String, dynamic>> accounts;
    try {
      accounts = await _studentsFuture;
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load accounts: $error');
      return;
    }
    if (!mounted || accounts.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset all visible passwords?'),
        content: Text(
          'This will reset ${accounts.length} passwords in the current account filter. '
          'Each account holder will need to change their password after signing in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset passwords'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isResetting = true;
      _error = null;
    });
    final results = <PasswordResetResult>[];
    final failures = <PasswordResetFailure>[];
    final warnings = <String>[];
    Object? batchError;
    try {
      final ids = accounts.map((account) => account['id'] as String).toList();
      for (var start = 0; start < ids.length; start += 100) {
        final end = (start + 100).clamp(0, ids.length);
        final batch = await _resetService.resetAccounts(
          ids.sublist(start, end),
        );
        results.addAll(batch.results);
        failures.addAll(batch.failures);
        warnings.addAll(batch.activityWarnings);
      }
    } catch (error) {
      batchError = error;
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
    if (!mounted) return;
    if (batchError != null) {
      setState(
        () => _error =
            'Password reset stopped after a partial result: $batchError',
      );
    }
    if (results.isEmpty) {
      setState(() {
        _error ??= failures.isEmpty
            ? 'No passwords were reset.'
            : failures
                  .map((failure) => '${failure.accountId}: ${failure.message}')
                  .join('\n');
      });
      return;
    }
    await _showCredentials(
      PasswordResetBatchResult(
        results: results,
        failures: failures,
        activityWarnings: warnings,
      ),
    );
  }

  Future<void> _createAccount() async {
    final account = await _askForAccount();
    if (account == null) return;
    setState(() {
      _error = null;
      _isResetting = true;
    });
    try {
      await Supabase.instance.client.functions.invoke(
        'manage-account',
        body: {'action': 'create', ...account},
      );
      if (!mounted) return;
      setState(() => _studentsFuture = _loadAccounts());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${account['role']} account created: ${account['username']}',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = supabaseErrorMessage(
            error,
            action: 'Could not create account',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  Future<Map<String, dynamic>?> _askForAccount() async {
    final client = Supabase.instance.client;
    var schools = <Map<String, dynamic>>[];
    if (_isAdmin) {
      try {
        final rows = await client
            .from('schools')
            .select('id, name')
            .order('name');
        schools = List<Map<String, dynamic>>.from(rows);
      } catch (error) {
        if (mounted) setState(() => _error = 'Could not load schools: $error');
        return null;
      }
    }
    if (!mounted) return null;

    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final subjectController = TextEditingController();
    var role = _isAdmin && _filterRole == AppRoles.teacher
        ? AppRoles.teacher
        : AppRoles.student;
    bool obscurePassword = false;
    String? schoolId = _isAdmin
        ? (schools.isEmpty ? null : schools.first['id'] as String)
        : ref.read(authStateProvider).user?.schoolId;
    String? sectionId;
    Future<List<Map<String, dynamic>>> sectionsFuture = schoolId != null
        ? _loadSectionsForSchool(schoolId)
        : Future.value([]);
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_isAdmin ? 'Create account' : 'Register student'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isAdmin)
                      DropdownButtonFormField<String>(
                        initialValue: role,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: const [
                          DropdownMenuItem(
                            value: AppRoles.student,
                            child: Text('Student'),
                          ),
                          DropdownMenuItem(
                            value: AppRoles.teacher,
                            child: Text('Teacher'),
                          ),
                          DropdownMenuItem(
                            value: AppRoles.admin,
                            child: Text('Admin'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            role = value;
                            final uName = _usernameFor(
                              nameController.text,
                              role,
                            );
                            usernameController.text = uName;
                            if (uName.isNotEmpty) {
                              passwordController.text = defaultRolePassword(
                                usernameOrFullName: uName,
                                role: role,
                              );
                            }
                            if (role != AppRoles.admin && schoolId == null && schools.isNotEmpty) {
                              schoolId = schools.first['id'] as String;
                            }
                          });
                        },
                      ),
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Full name'),
                      textCapitalization: TextCapitalization.words,
                      onChanged: (value) {
                        setDialogState(() {
                          final uName = _usernameFor(value, role);
                          usernameController.text = uName;
                          if (uName.isNotEmpty) {
                            passwordController.text = defaultRolePassword(
                              usernameOrFullName: uName,
                              role: role,
                            );
                          }
                        });
                      },
                      validator: (value) =>
                          value == null ||
                              value.trim().split(RegExp(r'\s+')).length < 2
                          ? 'Enter first and last name'
                          : null,
                    ),
                    TextFormField(
                      controller: usernameController,
                      decoration: const InputDecoration(labelText: 'Username'),
                      onChanged: (value) {
                        if (value.trim().isNotEmpty) {
                          setDialogState(() {
                            passwordController.text = defaultRolePassword(
                              usernameOrFullName: value.trim(),
                              role: role,
                            );
                          });
                        }
                      },
                      validator: (value) {
                        if (value == null || !isRoleUsername(value, role)) {
                          return 'Enter a valid username for this role';
                        }
                        return null;
                      },
                    ),
                    TextFormField(
                      controller: emailController,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) =>
                          value == null ||
                              !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                  .hasMatch(value.trim())
                          ? 'Enter a valid email address'
                          : null,
                    ),
                    TextFormField(
                      controller: passwordController,
                      decoration: InputDecoration(
                        labelText: 'Temporary password',
                        helperText: 'Format: Name1@${roleLetter(role)}.edu',
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              icon: Icon(
                                obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () => setDialogState(
                                () => obscurePassword = !obscurePassword,
                              ),
                            ),
                          ],
                        ),
                      ),
                      obscureText: obscurePassword,
                      validator: (value) => value == null || value.length < 8
                          ? 'Use at least 8 characters'
                          : null,
                    ),
                    if (role == AppRoles.teacher)
                      TextFormField(
                        controller: subjectController,
                        decoration: const InputDecoration(
                          labelText: 'Main subject / teaching subject',
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter a subject'
                            : null,
                      ),
                    if (_isAdmin && role != AppRoles.admin)
                      schools.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text(
                                'Add a school before creating student or teacher accounts.',
                              ),
                            )
                          : DropdownButtonFormField<String>(
                              initialValue: schoolId,
                              decoration: const InputDecoration(
                                labelText: 'School',
                              ),
                              items: [
                                for (final school in schools)
                                  DropdownMenuItem(
                                    value: school['id'] as String,
                                    child: Text(
                                      school['name'] as String? ?? 'School',
                                    ),
                                  ),
                              ],
                              onChanged: (value) => setDialogState(() {
                                schoolId = value;
                                sectionId = null;
                                sectionsFuture = value != null
                                    ? _loadSectionsForSchool(value)
                                    : Future.value([]);
                              }),
                            ),
                    if (schoolId != null)
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: sectionsFuture,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                'Could not load grade sections: ${snapshot.error}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            );
                          }
                          if (!snapshot.hasData) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: LinearProgressIndicator(),
                            );
                          }
                          final sections = snapshot.data!;
                          if (sections.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text(
                                'No sections are available for this school.',
                              ),
                            );
                          }
                          return DropdownButtonFormField<String>(
                            key: ValueKey(schoolId),
                            initialValue: sectionId,
                            decoration: const InputDecoration(
                              labelText: 'Grade and class or section',
                            ),
                            items: [
                              for (final section in sections)
                                DropdownMenuItem(
                                  value: section['id'] as String,
                                  child: Text(
                                    '${(section['school_grades'] as Map<String, dynamic>)['name']} · ${section['name']}',
                                  ),
                                ),
                            ],
                            onChanged: (value) =>
                                setDialogState(() => sectionId = value),
                            validator: (value) => value == null
                                ? 'Choose a grade and class or section'
                                : null,
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  (_isAdmin && role != AppRoles.admin && schoolId == null) ||
                      (role == AppRoles.student && sectionId == null) ||
                      (role == AppRoles.teacher && sectionId == null)
                  ? null
                  : () {
                      if (!formKey.currentState!.validate()) return;
                      Navigator.pop(dialogContext, {
                        'role': role,
                        'fullName': nameController.text.trim(),
                        'username': usernameController.text.trim(),
                        'email': emailController.text.trim(),
                        'password': passwordController.text.trim().isNotEmpty
                            ? passwordController.text.trim()
                            : defaultRolePassword(
                                usernameOrFullName:
                                    usernameController.text.trim(),
                                role: role,
                              ),
                        'subject': subjectController.text.trim().isNotEmpty
                            ? subjectController.text.trim()
                            : 'General',
                        if (role != AppRoles.admin)
                          'schoolId': _isAdmin
                              ? schoolId
                              : ref.read(authStateProvider).user?.schoolId,
                        if (role == AppRoles.student ||
                            role == AppRoles.teacher)
                          'sectionId': sectionId,
                      });
                    },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    emailController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    subjectController.dispose();
    return result;
  }

  String _usernameFor(String fullName, String role) {
    return roleUsername(fullName, role);
  }

  Future<List<Map<String, dynamic>>> _loadSectionsForSchool(
    String schoolId,
  ) async {
    if (!_isAdmin) {
      try {
        final response = await Supabase.instance.client.functions.invoke(
          'manage-account',
          body: {'action': 'classes'},
        );
        final data = response.data;
        if (data is Map<String, dynamic> &&
            data['sections'] is List &&
            (data['sections'] as List).isNotEmpty) {
          return (data['sections'] as List)
              .map((section) => Map<String, dynamic>.from(section as Map))
              .toList();
        }
      } catch (e) {
        debugPrint('classes function fallback: $e');
      }
    }
    try {
      final rows = await Supabase.instance.client
          .from('sections')
          .select('id, name, school_grades!inner(name)')
          .eq('school_id', schoolId)
          .order('name');
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('Direct sections load fallback: $e');
      return [];
    }
  }

  Future<void> _deleteAccount(Map<String, dynamic> account) async {
    final id = account['id'] as String;
    final role = account['role'] as String? ?? 'account';
    final name =
        account['full_name'] as String? ??
        account['username'] as String? ??
        role;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: Text('Permanently delete $name and their quiz account data?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _deletingId = id;
      _isResetting = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.functions.invoke(
        'manage-account',
        body: {'action': 'delete', 'userId': id},
      );
      if (mounted) {
        setState(() {
          _selectedIds.remove(id);
          _studentsFuture = _loadAccounts();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not delete account: $error');
    } finally {
      if (mounted) {
        setState(() {
          _deletingId = null;
          _isResetting = false;
        });
      }
    }
  }

  Future<void> _showCredentials(PasswordResetBatchResult result) async {
    final credentialText = result.results
        .map((item) => '${item.username}: ${item.temporaryPassword}')
        .join('\n');
    final failureText = result.failures
        .map((failure) => '${failure.accountId}: ${failure.message}')
        .join('\n');
    final warningText = result.activityWarnings.join('\n');

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          result.results.length == 1
              ? 'Temporary password'
              : 'Temporary passwords',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Share these credentials securely with the selected account holders. '
                'They will be asked to change their password after signing in.',
              ),
              const SizedBox(height: 16),
              SelectableText(credentialText),
              if (failureText.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Not reset:\n$failureText',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (warningText.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Activity warnings:\n$warningText',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: credentialText));
              if (!mounted || !context.mounted) return;
              Navigator.of(context).pop();
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(content: Text('Credentials copied')),
              );
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () async {
              await SharePlus.instance.share(ShareParams(text: credentialText));
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Share'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isAdmin ? 'Manage users' : 'Students'),
        actions: [
          if (_isAdmin)
            DropdownButton<String>(
              value: _filterRole,
              underline: const SizedBox.shrink(),
              onChanged: (role) {
                if (role == null) return;
                setState(() {
                  _filterRole = role;
                  _selectedIds.clear();
                  _studentsFuture = _loadAccounts();
                });
              },
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All accounts')),
                DropdownMenuItem(value: 'student', child: Text('Students')),
                DropdownMenuItem(value: 'teacher', child: Text('Teachers')),
                DropdownMenuItem(value: 'admin', child: Text('Admins')),
              ],
            ),
          if (_selectedIds.isNotEmpty)
            TextButton.icon(
              onPressed: _isResetting
                  ? null
                  : () => _reset(_selectedIds.toList()),
              icon: const Icon(Icons.key),
              label: Text('Reset selected (${_selectedIds.length})'),
            ),
          if (_isAdmin)
            IconButton(
              tooltip: 'Reset all visible account passwords',
              onPressed: _isResetting ? null : _resetVisibleAccounts,
              icon: const Icon(Icons.key),
            ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _studentsFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Could not load students: ${snapshot.error}'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => setState(() {
                      _studentsFuture = _loadAccounts();
                    }),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final students = snapshot.data!;
          return Column(
            children: [
              if (_isResetting) const LinearProgressIndicator(),
              if (!_isAdmin)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Tap the key beside a student to reset their password. '
                    'They will change it after signing in.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (_error != null)
                MaterialBanner(
                  content: Text(_error!),
                  actions: [
                    TextButton(
                      onPressed: () => setState(() => _error = null),
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              Expanded(
                child: students.isEmpty
                    ? const Center(child: Text('No students found.'))
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: students.length,
                        itemBuilder: (context, index) {
                          final student = students[index];
                          final id = student['id'] as String;
                          final name = (student['full_name'] as String?)
                              ?.trim();
                          final username = student['username'] as String? ?? '';
                          final role = student['role'] as String? ?? 'account';
                          final canReset = _isAdmin || role == AppRoles.student;
                          return ListTile(
                            leading: Checkbox(
                              value: _selectedIds.contains(id),
                              onChanged: _isResetting || !canReset
                                  ? null
                                  : (selected) => setState(() {
                                      if (selected ?? false) {
                                        _selectedIds.add(id);
                                      } else {
                                        _selectedIds.remove(id);
                                      }
                                    }),
                            ),
                            title: Text(
                              name?.isNotEmpty == true ? name! : username,
                            ),
                            subtitle: Text(
                              [
                                username,
                                if (student['class_labels'] is List &&
                                    (student['class_labels'] as List)
                                        .isNotEmpty)
                                  (student['class_labels'] as List).join(', '),
                              ].join('\n'),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (canReset)
                                  IconButton(
                                    tooltip: 'Reset this $role’s password',
                                    onPressed: _isResetting
                                        ? null
                                        : () => _reset([id]),
                                    icon: const Icon(Icons.lock_reset),
                                  ),
                                if (_isAdmin || role == AppRoles.student)
                                  IconButton(
                                    tooltip: 'Delete account',
                                    onPressed: _isResetting || _deletingId == id
                                        ? null
                                        : () => _deleteAccount(student),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isResetting ? null : _createAccount,
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(_isAdmin ? 'Register user' : 'Register student'),
      ),
    );
  }
}
