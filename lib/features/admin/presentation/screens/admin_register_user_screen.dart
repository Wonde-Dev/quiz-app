import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/utils/role_username.dart';
import 'package:quiz_app/core/utils/supabase_error_message.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class AdminRegisterUserScreen extends ConsumerStatefulWidget {
  const AdminRegisterUserScreen({super.key});

  @override
  ConsumerState<AdminRegisterUserScreen> createState() =>
      _AdminRegisterUserScreenState();
}

class _AdminRegisterUserScreenState
    extends ConsumerState<AdminRegisterUserScreen> {
  final _formKey = GlobalKey<FormState>();

  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _subjectController = TextEditingController();

  String _selectedRole = AppRoles.student;
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  List<Map<String, dynamic>> _schools = [];
  String? _selectedSchoolId;

  List<Map<String, dynamic>> _sections = [];
  String? _selectedSectionId;
  bool _loadingSections = false;

  List<String> _existingUsernames = [];
  List<String> _existingEmails = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final client = Supabase.instance.client;
    try {
      final results = await Future.wait<dynamic>([
        client.from('schools').select('id, name').order('name'),
        client.from('users').select('username, email'),
      ]);

      if (!mounted) return;

      final schoolRows = results[0] as List;
      final userRows = results[1] as List;

      setState(() {
        _schools = List<Map<String, dynamic>>.from(schoolRows);
        if (_schools.isNotEmpty) {
          _selectedSchoolId = _schools.first['id'] as String;
        }
        _existingUsernames = userRows
            .map((u) => u['username'] as String? ?? '')
            .where((u) => u.isNotEmpty)
            .toList();
        _existingEmails = userRows
            .map((u) => (u['email'] as String? ?? '').toLowerCase())
            .where((e) => e.isNotEmpty)
            .toList();
      });

      if (_selectedSchoolId != null) {
        _loadSectionsForSchool(_selectedSchoolId!);
      }
    } catch (e) {
      debugPrint('Error loading initial registration data: $e');
    }
  }

  Future<void> _loadSectionsForSchool(String schoolId) async {
    setState(() => _loadingSections = true);
    final client = Supabase.instance.client;
    try {
      final rows = await client
          .from('grade_sections')
          .select('id, name, school_grades!inner(name, school_id)')
          .eq('school_grades.school_id', schoolId)
          .order('name');

      if (!mounted) return;
      setState(() {
        _sections = List<Map<String, dynamic>>.from(rows);
        _selectedSectionId =
            _sections.isNotEmpty ? _sections.first['id'] as String : null;
        _loadingSections = false;
      });
    } catch (e) {
      debugPrint('Error loading sections: $e');
      if (mounted) setState(() => _loadingSections = false);
    }
  }

  void _onFullNameChanged(String value) {
    if (value.trim().isEmpty) return;

    final generated = nextRoleUsername(
      fullName: value,
      role: _selectedRole,
      existingUsernames: _existingUsernames,
    );

    if (generated.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _usernameController.text = generated;
        _emailController.text = generated.toLowerCase();
        _passwordController.text = defaultRolePassword(
          usernameOrFullName: generated,
          role: _selectedRole,
        );
        setState(() {});
      });
    }
  }

  void _onRoleChanged(String newRole) {
    setState(() => _selectedRole = newRole);
    if (_fullNameController.text.trim().isNotEmpty) {
      final generated = nextRoleUsername(
        fullName: _fullNameController.text,
        role: newRole,
        existingUsernames: _existingUsernames,
      );
      if (generated.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _usernameController.text = generated;
          _emailController.text = generated.toLowerCase();
          _passwordController.text = defaultRolePassword(
            usernameOrFullName: generated,
            role: newRole,
          );
          setState(() {});
        });
      }
    }
  }

  Future<void> _registerUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    var fullName = _fullNameController.text.trim();
    var username = _usernameController.text.trim();
    var email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final subject = _subjectController.text.trim();

    // Check if username already exists in local list, auto-advance to next sequential number
    if (_existingUsernames.map((u) => u.toLowerCase()).contains(username.toLowerCase())) {
      final nextUname = nextRoleUsername(
        fullName: fullName,
        role: _selectedRole,
        existingUsernames: _existingUsernames,
      );
      if (nextUname.isNotEmpty && nextUname != username) {
        username = nextUname;
        email = nextUname.toLowerCase();
        _usernameController.text = username;
        _emailController.text = email;
        _passwordController.text = defaultRolePassword(
          usernameOrFullName: username,
          role: _selectedRole,
        );
      }
    }

    try {
      bool createdViaFunction = false;

      // 1. Try dedicated database RPC function (security definer with instant email approval)
      try {
        final rpcRes = await Supabase.instance.client.rpc(
          'admin_create_user',
          params: {
            'p_full_name': fullName,
            'p_username': username,
            'p_email': email,
            'p_password': password,
            'p_role': _selectedRole,
            'p_school_id': _selectedRole != AppRoles.admin ? _selectedSchoolId : null,
            'p_section_id': _selectedRole != AppRoles.admin ? _selectedSectionId : null,
            'p_subject': _selectedRole == AppRoles.teacher && subject.isNotEmpty ? subject : null,
          },
        );
        if (rpcRes is Map) {
          if (rpcRes['success'] == true) {
            createdViaFunction = true;
          } else if (rpcRes['error'] != null) {
            throw Exception(rpcRes['error'].toString());
          }
        }
      } catch (rpcErr) {
        debugPrint('admin_create_user RPC note: $rpcErr');
        final errText = rpcErr.toString();
        if (errText.contains('already exists')) {
          // If conflict detected, auto-advance username with sequential number
          final nextUname = nextRoleUsername(
            fullName: fullName,
            role: _selectedRole,
            existingUsernames: [..._existingUsernames, username],
          );
          if (nextUname.isNotEmpty && nextUname != username) {
            _usernameController.text = nextUname;
            _emailController.text = nextUname.toLowerCase();
            _passwordController.text = defaultRolePassword(
              usernameOrFullName: nextUname,
              role: _selectedRole,
            );
            _existingUsernames.add(username);
            setState(() {
              _isLoading = false;
              _errorMessage =
                  'Username/email already existed. Automatically updated to unique credential: $nextUname. Please tap Register User to create.';
            });
            return;
          }
          rethrow;
        }
      }

      // 2. Try manage-account edge function
      if (!createdViaFunction) {
        try {
          final res = await Supabase.instance.client.functions.invoke(
            'manage-account',
            body: {
              'action': 'create',
              'role': _selectedRole,
              'fullName': fullName,
              'username': username,
              'email': email,
              'password': password,
              if (_selectedRole != AppRoles.admin) 'schoolId': _selectedSchoolId,
              if (_selectedRole != AppRoles.admin) 'sectionId': _selectedSectionId,
              if (_selectedRole == AppRoles.teacher)
                'subject': subject.isNotEmpty ? subject : 'General',
              'approval_status': 'approved',
              'is_active': true,
            },
          );
          if (res.status == 200 || res.status == 201) {
            createdViaFunction = true;
          }
        } catch (funcError) {
          debugPrint('manage-account invocation notice: $funcError');
        }
      }

      // 3. Direct Supabase Fallback if functions were unavailable
      if (!createdViaFunction) {
        final client = Supabase.instance.client;
        final authResponse = await client.auth.signUp(
          email: email,
          password: password,
          data: {
            'full_name': fullName,
            'username': username,
            'role': _selectedRole,
            'approval_status': 'approved',
            'is_active': true,
            if (_selectedRole != AppRoles.admin) 'school_id': _selectedSchoolId,
            if (_selectedRole != AppRoles.admin) 'section_id': _selectedSectionId,
            if (_selectedRole == AppRoles.teacher) 'subject': subject,
          },
        );

        final newUserId = authResponse.user?.id;
        if (newUserId != null) {
          await client.from('users').upsert({
            'id': newUserId,
            'email': email,
            'username': username,
            'full_name': fullName,
            'role': _selectedRole,
            'approval_status': 'approved',
            'is_active': true,
            if (_selectedRole != AppRoles.admin) 'school_id': _selectedSchoolId,
            if (_selectedRole != AppRoles.admin) 'section_id': _selectedSectionId,
          });
        }
      }

      if (!mounted) return;

      // Track registered username in local deduplication list
      _existingUsernames.add(username);
      _existingEmails.add(email.toLowerCase());

      // Show animated success dialog with copy options
      await _showSuccessDialog(
        fullName: fullName,
        username: username,
        password: password,
        role: _selectedRole,
      );

      // Reset form fields for subsequent registration outside build/pop frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _fullNameController.clear();
        _usernameController.clear();
        _emailController.clear();
        _passwordController.clear();
        _subjectController.clear();
        setState(() {});
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = supabaseErrorMessage(
            e,
            action: 'Could not register user account',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showSuccessDialog({
    required String fullName,
    required String username,
    required String password,
    required String role,
  }) async {
    final roleName = switch (role) {
      AppRoles.admin => 'Administrator',
      AppRoles.teacher => 'Teacher',
      _ => 'Student',
    };

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        contentPadding: const EdgeInsets.all(24),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF10B981),
                  size: 38,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '$roleName Registered!',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Account for $fullName has been created and instantly activated.',
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
                      'CREDENTIALS TO PROVIDE USER',
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
                        const Text(
                          'Username: ',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Expanded(
                          child: SelectableText(
                            username,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF059669),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text(
                          'Password: ',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Expanded(
                          child: SelectableText(
                            password,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF0F172A),
                            ),
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
                      label: const Text('Copy Info'),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(
                            text:
                                'Role: $roleName\nFull Name: $fullName\nUsername: $username\nPassword: $password',
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
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(80, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: const Text('Register Another'),
                  ),
                ],
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

    final roleColor = _selectedRole == AppRoles.teacher
        ? const Color(0xFF10B981)
        : _selectedRole == AppRoles.admin
            ? const Color(0xFF0F172A)
            : const Color(0xFF6366F1);

    return DashboardShell(
      title: 'Register New User',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Banner with School Architecture Image
          Container(
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 130,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/images/school_building.jpeg',
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: const Color(0xFF10B981).withValues(alpha: 0.1),
                          child: const Icon(
                            Icons.school_rounded,
                            size: 48,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              (isDark ? const Color(0xFF1E293B) : Colors.white)
                                  .withValues(alpha: 0.95),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: roleColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          _selectedRole == AppRoles.admin
                              ? Icons.admin_panel_settings_rounded
                              : _selectedRole == AppRoles.teacher
                                  ? Icons.co_present_rounded
                                  : Icons.school_rounded,
                          color: roleColor,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Institutional Account Creation',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Create and immediately activate accounts for students, faculty, or system administrators.',
                              style: TextStyle(
                                fontSize: 12,
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
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Error Notification if any
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Color(0xFFEF4444), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFF991B1B),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Form Card
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                width: 1.2,
              ),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Role Selector
                  const Text(
                    '1. Select Institutional Role',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final opt in const [
                        (
                          role: AppRoles.student,
                          label: 'Student',
                          icon: Icons.school_outlined,
                        ),
                        (
                          role: AppRoles.teacher,
                          label: 'Teacher',
                          icon: Icons.co_present_outlined,
                        ),
                        (
                          role: AppRoles.admin,
                          label: 'Admin',
                          icon: Icons.shield_outlined,
                        ),
                      ])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              avatar: Icon(opt.icon, size: 16),
                              label: Text(opt.label,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 13)),
                              selected: _selectedRole == opt.role,
                              onSelected: (selected) {
                                if (selected) _onRoleChanged(opt.role);
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // User Identity Details
                  const Text(
                    '2. User Identity & Institutional Credentials',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _fullNameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name (First and Last Name)',
                      hintText: 'e.g. Lamesa Ahamed',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    textCapitalization: TextCapitalization.words,
                    onChanged: _onFullNameChanged,
                    validator: (value) =>
                        value == null || value.trim().split(RegExp(r'\s+')).length < 2
                            ? 'Enter at least first and last name'
                            : null,
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: 'Institutional Username',
                      helperText:
                          'Ends in @${_selectedRole == AppRoles.teacher ? 'Teacher' : _selectedRole == AppRoles.admin ? 'Admin' : 'Student'}.edu (Deduplicated automatically)',
                      prefixIcon: const Icon(Icons.alternate_email_rounded),
                    ),
                    validator: (value) {
                      if (value == null || !isRoleUsername(value, _selectedRole)) {
                        return 'Enter a valid institutional username for this role';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Sign-in Email Address',
                      hintText: 'user@school.edu',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) => value == null ||
                            !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())
                        ? 'Enter a valid email address'
                        : null,
                  ),
                  const SizedBox(height: 14),

                  // Dynamic Password Formula Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.auto_awesome_rounded,
                                size: 16, color: Color(0xFF10B981)),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Initial Password Generation',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (_passwordController.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 16),
                                tooltip: 'Copy password',
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: _passwordController.text),
                                  );
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
                          _passwordController.text.isNotEmpty
                              ? 'Active Password: ${_passwordController.text}'
                              : 'Formula: <NamePart>1@${roleLetter(_selectedRole)}.edu',
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
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Initial Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword ? 'Show' : 'Hide',
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    obscureText: _obscurePassword,
                    validator: (value) =>
                        value == null || value.length < 8
                            ? 'Password must have at least 8 characters'
                            : null,
                  ),
                  const SizedBox(height: 20),

                  // School & Section Allocations (for student and teacher)
                  if (_selectedRole != AppRoles.admin) ...[
                    const Text(
                      '3. Academic Assignment',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),

                    if (_schools.isNotEmpty)
                      DropdownButtonFormField<String>(
                        key: ValueKey('admin_reg_school_$_selectedSchoolId'),
                        initialValue: _selectedSchoolId,
                        decoration: const InputDecoration(
                          labelText: 'School Campus',
                          prefixIcon: Icon(Icons.location_city_rounded),
                        ),
                        items: [
                          for (final s in _schools)
                            DropdownMenuItem(
                              value: s['id'] as String,
                              child: Text(s['name'] as String? ?? 'School'),
                            ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedSchoolId = val);
                            _loadSectionsForSchool(val);
                          }
                        },
                      ),
                    const SizedBox(height: 14),

                    if (_selectedRole == AppRoles.student ||
                        _selectedRole == AppRoles.teacher) ...[
                      if (_loadingSections)
                        const LinearProgressIndicator()
                      else if (_sections.isNotEmpty)
                        DropdownButtonFormField<String>(
                          key: ValueKey('admin_reg_section_$_selectedSectionId'),
                          initialValue: _selectedSectionId,
                          decoration: InputDecoration(
                            labelText: _selectedRole == AppRoles.student
                                ? 'Enrolled Grade & Section'
                                : 'Assigned Department / Section',
                            prefixIcon: const Icon(Icons.meeting_room_outlined),
                          ),
                          items: [
                            for (final sec in _sections)
                              DropdownMenuItem(
                                value: sec['id'] as String,
                                child: Text(
                                  '${(sec['school_grades'] as Map<String, dynamic>?)?['name'] ?? 'Grade'} · Section ${sec['name']}',
                                ),
                              ),
                          ],
                          onChanged: (val) =>
                              setState(() => _selectedSectionId = val),
                          validator: (val) => val == null
                              ? 'Choose a grade and classroom section'
                              : null,
                        ),
                      const SizedBox(height: 14),
                    ],

                    if (_selectedRole == AppRoles.teacher) ...[
                      TextFormField(
                        controller: _subjectController,
                        decoration: const InputDecoration(
                          labelText: 'Teacher Subject / Specialty',
                          hintText: 'e.g. Mathematics, Physics, Biology',
                          prefixIcon: Icon(Icons.menu_book_outlined),
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Enter primary subject'
                                : null,
                      ),
                      const SizedBox(height: 14),
                    ],
                  ],

                  const SizedBox(height: 10),

                  // Instant Activation Info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.verified_user_rounded,
                            color: Color(0xFF10B981), size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Immediate Activation: Accounts registered by Administrators are pre-approved and can sign in instantly.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF065F46),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Submit Button
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.person_add_rounded, size: 20),
                    label: Text(
                      _isLoading ? 'Registering...' : 'Register & Activate User',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    onPressed: _isLoading ? null : _registerUser,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
