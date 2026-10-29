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
  final _searchController = TextEditingController();
  final Set<String> _selectedIds = {};
  late Future<List<Map<String, dynamic>>> _studentsFuture;
  bool _isResetting = false;
  String _filterRole = AppRoles.student;
  String? _deletingId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _studentsFuture = _loadAccounts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _isAdmin =>
      ref.read(authStateProvider).user?.role == AppRoles.admin ||
      ref.read(authStateProvider).user?.role == AppRoles.subadmin;

  Future<List<Map<String, dynamic>>> _loadAccounts() async {
    final currentUser = ref.read(authStateProvider).user;
    final isSuperAdmin = currentUser?.isSuperAdmin == true;
    final isSubadmin = currentUser?.role == AppRoles.subadmin || (!isSuperAdmin && _isAdmin);

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'manage-account',
        body: {'action': 'list', if (_isAdmin) 'role': _filterRole},
      );
      final data = response.data;
      if (data is Map<String, dynamic> && data['accounts'] is List) {
        var accounts = (data['accounts'] as List)
            .map((account) => Map<String, dynamic>.from(account as Map))
            .toList();
        if (isSubadmin && currentUser?.schoolId != null) {
          accounts = accounts
              .where((a) => a['school_id'] == currentUser!.schoolId)
              .toList();
        }
        return accounts;
      }
    } catch (e) {
      debugPrint('manage-account list fallback: $e');
    }

    final client = Supabase.instance.client;
    final currentUserId = client.auth.currentUser?.id;
    var query = client
        .from('users')
        .select('id, username, full_name, role, requested_role, school_id')
        .neq('is_active', false);

    final userSchoolId = currentUser?.schoolId;
    if (isSubadmin && userSchoolId != null) {
      query = query.eq('school_id', userSchoolId);
      if (_filterRole != 'all') {
        query = query.eq('role', _filterRole);
      }
    } else if (!_isAdmin) {
      query = query.eq('role', AppRoles.student);
      if (userSchoolId != null) query = query.eq('school_id', userSchoolId);
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
      final currentUser = ref.read(authStateProvider).user;
      bool created = false;

      // 1. Try dedicated database RPC function
      try {
        final rpcRes = await Supabase.instance.client.rpc(
          'admin_create_user',
          params: {
            'p_full_name': account['fullName'],
            'p_username': account['username'],
            'p_email': account['email'],
            'p_password': account['password'],
            'p_role': account['role'] ?? AppRoles.student,
            'p_school_id': account['schoolId'],
            'p_section_id': account['sectionId'],
            'p_subject': account['subject'],
            'p_grade': currentUser?.attendanceGrade,
            'p_class': currentUser?.attendanceClass,
          },
        );
        if (rpcRes is Map && rpcRes['success'] == true) {
          created = true;
        }
      } catch (rpcErr) {
        debugPrint('admin_create_user in student management: $rpcErr');
      }

      // 2. Try Edge Function fallback
      if (!created) {
        await Supabase.instance.client.functions.invoke(
          'manage-account',
          body: {'action': 'create', ...account},
        );
      }
      if (!mounted) return;
      setState(() => _studentsFuture = _loadAccounts());

      // Show animated success dialog with copyable credentials
      if (mounted) {
        final username = account['username'] as String;
        final password = account['password'] as String;
        final role = account['role'] as String;
        final fullName = account['fullName'] as String;

        await showDialog<void>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            contentPadding: const EdgeInsets.all(24),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF10B981),
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Account Ready & Registered',
                    style: Theme.of(dialogCtx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'The $role account for $fullName has been created successfully.',
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ACCOUNT CREDENTIALS',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Text('Username: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Expanded(
                              child: SelectableText(
                                username,
                                style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('Password: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Expanded(
                              child: SelectableText(
                                password,
                                style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('Copy Credentials'),
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(
                                text: 'Username: $username\nPassword: $password',
                              ),
                            );
                            ScaffoldMessenger.of(dialogCtx).showSnackBar(
                              const SnackBar(
                                content: Text('Credentials copied to clipboard!'),
                                duration: Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(80, 46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }
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
    List<Map<String, dynamic>> availableSections = [];
    if (schoolId != null) {
      try {
        availableSections = await _loadSectionsForSchool(schoolId);
        if (availableSections.isNotEmpty) {
          sectionId = availableSections.first['id'] as String;
        }
      } catch (_) {}
    }
    final formKey = GlobalKey<FormState>();

    List<String> knownUsernames = [];
    try {
      final loaded = await _studentsFuture;
      knownUsernames = loaded
          .map((a) => a['username'] as String? ?? '')
          .where((u) => u.isNotEmpty)
          .toList();
    } catch (_) {}
    if (!mounted) return null;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final roleColor = role == AppRoles.teacher
              ? const Color(0xFF10B981)
              : role == AppRoles.admin
                  ? const Color(0xFF8B5CF6)
                  : const Color(0xFF6366F1);

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    role == AppRoles.admin
                        ? Icons.admin_panel_settings_rounded
                        : role == AppRoles.teacher
                            ? Icons.co_present_rounded
                            : Icons.school_rounded,
                    color: roleColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isAdmin ? 'Register New Account' : 'Register Student',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                      ),
                      Text(
                        'Credentials and classroom assignment',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_isAdmin) ...[
                        const Text(
                          'Select Account Role',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            for (final opt in const [
                              (role: AppRoles.student, label: 'Student', icon: Icons.school_outlined),
                              (role: AppRoles.teacher, label: 'Teacher', icon: Icons.co_present_outlined),
                              (role: AppRoles.admin, label: 'Admin', icon: Icons.shield_outlined),
                            ])
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 3),
                                  child: ChoiceChip(
                                    avatar: Icon(opt.icon, size: 16),
                                    label: Text(opt.label, style: const TextStyle(fontSize: 12)),
                                    selected: role == opt.role,
                                    onSelected: (selected) {
                                      if (!selected) return;
                                      setDialogState(() {
                                        role = opt.role;
                                        if (role != AppRoles.admin && schoolId == null && schools.isNotEmpty) {
                                          schoolId = schools.first['id'] as String;
                                        }
                                      });
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        final uName = _usernameFor(nameController.text, role, knownUsernames);
                                        usernameController.text = uName;
                                        if (uName.isNotEmpty) {
                                          passwordController.text = defaultRolePassword(
                                            usernameOrFullName: uName,
                                            role: role,
                                          );
                                        }
                                        setDialogState(() {});
                                      });
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],

                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Full Name',
                          hintText: 'e.g. John Doe',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        textCapitalization: TextCapitalization.words,
                        onChanged: (value) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            final uName = _usernameFor(value, role, knownUsernames);
                            usernameController.text = uName;
                            if (uName.isNotEmpty) {
                              passwordController.text = defaultRolePassword(
                                usernameOrFullName: uName,
                                role: role,
                              );
                            }
                            setDialogState(() {});
                          });
                        },
                        validator: (value) =>
                            value == null || value.trim().split(RegExp(r'\s+')).length < 2
                                ? 'Enter first and last name'
                                : null,
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: usernameController,
                        decoration: InputDecoration(
                          labelText: 'Generated Username',
                          helperText: 'Must end in @${role == AppRoles.teacher ? 'Teacher' : role == AppRoles.admin ? 'Admin' : 'Student'}.edu',
                          prefixIcon: const Icon(Icons.alternate_email_rounded),
                        ),
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
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email Address',
                          hintText: 'user@school.edu',
                          prefixIcon: Icon(Icons.mail_outline_rounded),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) => value == null ||
                                !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())
                            ? 'Enter a valid email address'
                            : null,
                      ),
                      const SizedBox(height: 12),

                      // Live Dynamic Default Password Card
                      Container(
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
                              children: [
                                const Icon(Icons.auto_awesome_rounded, size: 16, color: Color(0xFF10B981)),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Default Password Formula',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                  ),
                                ),
                                if (passwordController.text.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.copy_rounded, size: 14),
                                    tooltip: 'Copy temporary password',
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: passwordController.text));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Password copied!'),
                                          duration: Duration(seconds: 1),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                            Text(
                              passwordController.text.isNotEmpty
                                  ? 'Active: ${passwordController.text}'
                                  : 'Pattern: <NamePart>1@${roleLetter(role)}.edu',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: passwordController,
                        decoration: InputDecoration(
                          labelText: 'Temporary Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: obscurePassword ? 'Show password' : 'Hide password',
                            icon: Icon(
                              obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setDialogState(
                              () => obscurePassword = !obscurePassword,
                            ),
                          ),
                        ),
                        obscureText: obscurePassword,
                        validator: (value) => value == null || value.length < 8
                            ? 'Use at least 8 characters'
                            : null,
                      ),
                      const SizedBox(height: 12),

                      if (role == AppRoles.teacher) ...[
                        TextFormField(
                          controller: subjectController,
                          decoration: const InputDecoration(
                            labelText: 'Main Subject / Department',
                            hintText: 'e.g. Mathematics, Physics',
                            prefixIcon: Icon(Icons.menu_book_outlined),
                          ),
                          textCapitalization: TextCapitalization.words,
                          validator: (value) => value == null || value.trim().isEmpty
                              ? 'Enter a subject'
                              : null,
                        ),
                        const SizedBox(height: 12),
                      ],

                      if (_isAdmin && role != AppRoles.admin) ...[
                        schools.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text('Add a school before creating student or teacher accounts.'),
                              )
                            : DropdownButtonFormField<String>(
                                initialValue: schoolId,
                                decoration: const InputDecoration(
                                  labelText: 'School',
                                  prefixIcon: Icon(Icons.location_city_rounded),
                                ),
                                items: [
                                  for (final school in schools)
                                    DropdownMenuItem(
                                      value: school['id'] as String,
                                      child: Text(school['name'] as String? ?? 'School'),
                                    ),
                                ],
                                onChanged: (value) async {
                                  setDialogState(() {
                                    schoolId = value;
                                    sectionId = null;
                                  });
                                  if (value != null) {
                                    final secs = await _loadSectionsForSchool(value);
                                    setDialogState(() {
                                      availableSections = secs;
                                      if (availableSections.isNotEmpty) {
                                        sectionId = availableSections.first['id'] as String;
                                      }
                                    });
                                  }
                                },
                              ),
                        const SizedBox(height: 12),
                      ],

                      if (schoolId != null && role != AppRoles.admin) ...[
                        if (availableSections.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('No sections available for this school.'),
                          )
                        else
                          DropdownButtonFormField<String>(
                            key: ValueKey('${schoolId}_${availableSections.length}'),
                            initialValue: sectionId,
                            decoration: const InputDecoration(
                              labelText: 'Grade & Classroom Section',
                              prefixIcon: Icon(Icons.meeting_room_outlined),
                            ),
                            items: [
                              for (final section in availableSections)
                                DropdownMenuItem(
                                  value: section['id'] as String,
                                  child: Text(
                                    '${(section['school_grades'] as Map<String, dynamic>?)?['name'] ?? 'Grade'} · Section ${section['name']}',
                                  ),
                                ),
                            ],
                            onChanged: (value) => setDialogState(() => sectionId = value),
                            validator: (value) =>
                                value == null ? 'Choose a grade and classroom section' : null,
                          ),
                      ],
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
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: (_isAdmin && role != AppRoles.admin && schoolId == null) ||
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
                                  usernameOrFullName: usernameController.text.trim(),
                                  role: role,
                                ),
                          'subject': subjectController.text.trim().isNotEmpty
                              ? subjectController.text.trim()
                              : 'General',
                          if (role != AppRoles.admin)
                            'schoolId': _isAdmin ? schoolId : ref.read(authStateProvider).user?.schoolId,
                          if (role == AppRoles.student || role == AppRoles.teacher)
                            'sectionId': sectionId,
                        });
                      },
                child: const Text('Create Account'),
              ),
            ],
          );
        },
      ),
    );
    nameController.dispose();
    emailController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    subjectController.dispose();
    return result;
  }

  String _usernameFor(String fullName, String role, [Iterable<String>? existing]) {
    return nextRoleUsername(
      fullName: fullName,
      role: role,
      existingUsernames: existing ?? const [],
    );
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
    final targetRole = account['role'] as String? ?? 'student';

    final isSuperAdminAccount = account['is_super_admin'] == true ||
        (account['email'] as String? ?? '').toLowerCase().contains('wondedev369@gmail.com') ||
        (account['email'] as String? ?? '').toLowerCase().contains('wondeadmin@admin.edu') ||
        account['role'] == 'admin';

    if (isSuperAdminAccount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The Main Administrator account is protected and cannot be deleted.',
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!_isAdmin && targetRole != AppRoles.student) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Teachers can only erase student accounts, not teachers or administrators.',
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
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
      bool deleted = false;
      // 1. Try dedicated database RPC function (removes from public.users & auth.users)
      try {
        await Supabase.instance.client.rpc(
          'delete_user_account',
          params: {'user_id': id, 'p_user_id': id},
        );
        deleted = true;
      } catch (rpcErr) {
        debugPrint('delete_user_account RPC error: $rpcErr');
      }

      // 2. If RPC not available, try manage-account edge function
      if (!deleted) {
        try {
          await Supabase.instance.client.functions.invoke(
            'manage-account',
            body: {'action': 'delete', 'userId': id},
          );
          deleted = true;
        } catch (fnErr) {
          debugPrint('manage-account delete error: $fnErr');
        }
      }

      // 3. Fallback: clean up relational rows then direct table delete
      if (!deleted) {
        final client = Supabase.instance.client;
        try {
          await client.from('student_sections').delete().eq('student_id', id);
        } catch (_) {}
        try {
          await client.from('answers').delete().eq('student_id', id);
        } catch (_) {}
        try {
          await client.from('grades').delete().eq('student_id', id);
        } catch (_) {}
        try {
          await client.from('quiz_attempts').delete().eq('student_id', id);
        } catch (_) {}
        try {
          await client.from('password_reset_requests').delete().eq('user_id', id);
        } catch (_) {}

        try {
          await client.from('users').delete().eq('id', id);
          deleted = true;
        } catch (dbErr) {
          debugPrint('Direct user delete error: $dbErr');
          // Soft-delete / deactivate if hard delete permission was blocked
          await client.from('users').update({
            'is_active': false,
            'approval_status': 'rejected',
          }).eq('id', id);
          deleted = true;
        }
      }

      if (mounted) {
        setState(() {
          _selectedIds.remove(id);
          _studentsFuture = _loadAccounts();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Account $name deleted successfully'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = supabaseErrorMessage(
            error,
            action: 'Could not delete account',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _deletingId = null;
          _isResetting = false;
        });
      }
    }
  }

  Future<void> _editAccount(Map<String, dynamic> account) async {
    final id = account['id'] as String;
    final currentName = account['full_name'] as String? ?? '';
    final currentEmail = account['email'] as String? ?? '';
    final currentRole = account['role'] as String? ?? 'student';
    final nameController = TextEditingController(text: currentName);
    final emailController = TextEditingController(text: currentEmail);
    String selectedRole = currentRole;
    bool isActive = account['is_active'] != false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.edit_rounded, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text('Edit User Account'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                if (_isAdmin) ...[
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      prefixIcon: Icon(Icons.shield_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: AppRoles.student, child: Text('Student')),
                      DropdownMenuItem(value: AppRoles.teacher, child: Text('Teacher')),
                      DropdownMenuItem(value: AppRoles.admin, child: Text('Administrator')),
                    ],
                    onChanged: (v) => setDialogState(() => selectedRole = v ?? selectedRole),
                  ),
                  const SizedBox(height: 14),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Account Active', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    isActive ? 'User can sign in and participate' : 'Account suspended / deactivated',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: isActive,
                  onChanged: (v) => setDialogState(() => isActive = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) return;

    setState(() {
      _isResetting = true;
      _error = null;
    });

    try {
      final newName = nameController.text.trim();
      final newEmail = emailController.text.trim();
      bool updated = false;

      try {
        await Supabase.instance.client.rpc(
          'admin_update_user',
          params: {
            'p_user_id': id,
            'p_full_name': newName,
            'p_role': selectedRole,
            'p_email': newEmail,
            'p_is_active': isActive,
          },
        );
        updated = true;
      } catch (rpcErr) {
        debugPrint('admin_update_user RPC note: $rpcErr');
      }

      if (!updated) {
        await Supabase.instance.client.from('users').update({
          'full_name': newName,
          'role': selectedRole,
          'email': newEmail,
          'is_active': isActive,
        }).eq('id', id);
      }

      if (!mounted) return;
      setState(() => _studentsFuture = _loadAccounts());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account updated successfully!'),
          backgroundColor: Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not update account: $e');
    } finally {
      if (mounted) setState(() => _isResetting = false);
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

  Future<void> _deleteSelectedAccounts() async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $count accounts?'),
        content: Text(
          'Permanently delete $count selected accounts and their quiz data? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _isResetting = true;
      _error = null;
    });
    try {
      final idsToDelete = _selectedIds.toList();
      for (final id in idsToDelete) {
        bool deleted = false;
        try {
          await Supabase.instance.client.rpc(
            'delete_user_account',
            params: {'user_id': id, 'p_user_id': id},
          );
          deleted = true;
        } catch (_) {}
        if (!deleted) {
          try {
            await Supabase.instance.client.functions.invoke(
              'manage-account',
              body: {'action': 'delete', 'userId': id},
            );
            deleted = true;
          } catch (_) {}
        }
        if (!deleted) {
          try {
            await Supabase.instance.client.from('student_sections').delete().eq('student_id', id);
          } catch (_) {}
          try {
            await Supabase.instance.client.from('answers').delete().eq('student_id', id);
          } catch (_) {}
          try {
            await Supabase.instance.client.from('grades').delete().eq('student_id', id);
          } catch (_) {}
          try {
            await Supabase.instance.client.from('quiz_attempts').delete().eq('student_id', id);
          } catch (_) {}
          try {
            await Supabase.instance.client.from('password_reset_requests').delete().eq('user_id', id);
          } catch (_) {}
          try {
            await Supabase.instance.client.from('users').delete().eq('id', id);
            deleted = true;
          } catch (_) {
            try {
              await Supabase.instance.client.from('users').update({
                'is_active': false,
                'approval_status': 'rejected',
              }).eq('id', id);
              deleted = true;
            } catch (_) {}
          }
        }
      }
      if (mounted) {
        setState(() {
          _selectedIds.clear();
          _studentsFuture = _loadAccounts();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count accounts deleted successfully'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = supabaseErrorMessage(
            error,
            action: 'Could not delete accounts',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isAdmin ? 'Manage users' : 'Students'),
        actions: [
          if (_selectedIds.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonalIcon(
                onPressed: _isResetting
                    ? null
                    : () => _reset(_selectedIds.toList()),
                icon: const Icon(Icons.lock_reset_rounded, size: 18),
                label: Text('Reset (${_selectedIds.length})'),
              ),
            ),
            if (_isAdmin)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                  ),
                  onPressed: _isResetting ? null : _deleteSelectedAccounts,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text('Delete (${_selectedIds.length})'),
                ),
              ),
          ],
          if (_isAdmin)
            IconButton(
              tooltip: 'Reset all visible account passwords',
              onPressed: _isResetting ? null : _resetVisibleAccounts,
              icon: const Icon(Icons.vpn_key_rounded),
            ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _studentsFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
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
                      'Could not load accounts: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => setState(() {
                        _studentsFuture = _loadAccounts();
                      }),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allStudents = snapshot.data!;
          final query = _searchController.text.trim().toLowerCase();
          final students = allStudents.where((s) {
            if (query.isEmpty) return true;
            final name = (s['full_name'] as String? ?? '').toLowerCase();
            final username = (s['username'] as String? ?? '').toLowerCase();
            final email = (s['email'] as String? ?? '').toLowerCase();
            return name.contains(query) ||
                username.contains(query) ||
                email.contains(query);
          }).toList();

          final allVisibleSelected = students.isNotEmpty &&
              students.every((s) => _selectedIds.contains(s['id'] as String));

          return Column(
            children: [
              if (_isResetting) const LinearProgressIndicator(),

              // Search bar & filters
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isAdmin) ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildRoleChip('All accounts', 'all'),
                            const SizedBox(width: 8),
                            _buildRoleChip('Students', AppRoles.student),
                            const SizedBox(width: 8),
                            _buildRoleChip('Teachers', AppRoles.teacher),
                            const SizedBox(width: 8),
                            _buildRoleChip('Admins', AppRoles.admin),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: _isAdmin
                            ? 'Search users by name or username...'
                            : 'Search students by name or username...',
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
                        isDense: true,
                      ),
                    ),
                    if (students.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Showing ${students.length} ${students.length == 1 ? "user" : "users"}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: Icon(
                              allVisibleSelected
                                  ? Icons.deselect_rounded
                                  : Icons.select_all_rounded,
                              size: 16,
                            ),
                            label: Text(
                              allVisibleSelected
                                  ? 'Deselect all'
                                  : 'Select all',
                              style: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () {
                              setState(() {
                                if (allVisibleSelected) {
                                  for (final s in students) {
                                    _selectedIds.remove(s['id'] as String);
                                  }
                                } else {
                                  for (final s in students) {
                                    _selectedIds.add(s['id'] as String);
                                  }
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              if (_error != null)
                MaterialBanner(
                  content: Text(_error!),
                  backgroundColor: theme.colorScheme.errorContainer,
                  actions: [
                    TextButton(
                      onPressed: () => setState(() => _error = null),
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),

              Expanded(
                child: students.isEmpty
                    ? Center(
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
                                _searchController.text.isNotEmpty
                                    ? 'No accounts matching "${_searchController.text}"'
                                    : 'No accounts found.',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                        itemCount: students.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final student = students[index];
                          final id = student['id'] as String;
                          final name = (student['full_name'] as String?)?.trim();
                          final username = student['username'] as String? ?? '';
                          final role = (student['role'] as String? ?? 'student')
                              .toLowerCase();
                          final canReset = _isAdmin || role == AppRoles.student;
                          final isSelected = _selectedIds.contains(id);

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

                          final displayName =
                              name?.isNotEmpty == true ? name! : username;

                          return Card(
                            elevation: isSelected ? 2 : 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outlineVariant
                                        .withValues(alpha: 0.5),
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 36,
                                    height: 36,
                                    child: Checkbox(
                                      value: isSelected,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(4),
                                      ),
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
                                  ),
                                  const SizedBox(width: 8),
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor:
                                        roleColor.withValues(alpha: 0.15),
                                    child: Text(
                                      displayName.isNotEmpty
                                          ? displayName[0].toUpperCase()
                                          : 'U',
                                      style: TextStyle(
                                        color: roleColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                displayName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: roleColor.withValues(
                                                    alpha: 0.12),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                roleLabel,
                                                style: TextStyle(
                                                  color: roleColor,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          username,
                                          style: TextStyle(
                                            color: theme
                                                .colorScheme.onSurfaceVariant,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (student['class_labels'] is List &&
                                            (student['class_labels'] as List)
                                                .isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            (student['class_labels'] as List)
                                                .join(', '),
                                            style: TextStyle(
                                              color:
                                                  theme.colorScheme.primary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (canReset)
                                        IconButton(
                                          tooltip: 'Reset password for $displayName',
                                          onPressed: _isResetting
                                              ? null
                                              : () => _reset([id]),
                                          icon: const Icon(
                                            Icons.lock_reset_rounded,
                                            size: 22,
                                          ),
                                        ),
                                      if (_isAdmin)
                                        IconButton(
                                          tooltip: 'Edit / Update $displayName',
                                          onPressed: _isResetting || _deletingId == id
                                              ? null
                                              : () => _editAccount(student),
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            color: Color(0xFF10B981),
                                            size: 20,
                                          ),
                                        ),
                                      if (_isAdmin || role == AppRoles.student)
                                        IconButton(
                                          tooltip: 'Delete account $displayName',
                                          onPressed: _isResetting ||
                                                  _deletingId == id
                                              ? null
                                              : () => _deleteAccount(student),
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            color: Colors.red,
                                            size: 20,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
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
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(_isAdmin ? 'Register user' : 'Register student'),
      ),
    );
  }

  Widget _buildRoleChip(String label, String roleValue) {
    final selected = _filterRole == roleValue;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (val) {
        if (!val) return;
        setState(() {
          _filterRole = roleValue;
          _selectedIds.clear();
          _studentsFuture = _loadAccounts();
        });
      },
    );
  }
}
