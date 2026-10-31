import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/utils/role_username.dart';
import 'package:quiz_app/core/utils/supabase_error_message.dart';
import 'package:quiz_app/core/utils/validators.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/shared/widgets/animated_press_button.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class AdminRegisterUserScreen extends ConsumerStatefulWidget {
  const AdminRegisterUserScreen({super.key});

  @override
  ConsumerState<AdminRegisterUserScreen> createState() =>
      _AdminRegisterUserScreenState();
}

class _AdminRegisterUserScreenState
    extends ConsumerState<AdminRegisterUserScreen> {
  static const String _ciroSchoolId = '00000000-0000-4000-8000-000000000001';
  static const String _schoolName = 'Ciro High School';

  final _formKey = GlobalKey<FormState>();

  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _subjectController = TextEditingController();
  final _phoneController = TextEditingController();
  String _selectedGender = 'Male';
  final List<String> _genders = const ['Male', 'Female', 'Other'];

  String _selectedRole = AppRoles.student;
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  List<Map<String, dynamic>> _sections = [];
  String? _selectedSectionId;

  // Grade & Class state for Teachers & Students
  String _selectedGrade = 'Grade 9';
  String _selectedClass = '9A';
  bool _isAttendanceTeacher = false;

  final List<String> _grades = const ['Grade 9', 'Grade 10', 'Grade 11', 'Grade 12'];

  List<String> _getClassesForGrade(String grade) {
    final gradeNum = grade.replaceAll(RegExp(r'[^0-9]'), '');
    return [
      '${gradeNum}A',
      '${gradeNum}B',
      '${gradeNum}C',
      '${gradeNum}D',
      '${gradeNum}E',
    ];
  }

  List<String> _existingUsernames = [];
  List<String> _existingEmails = [];
  int _activeDirectorCount = 0;
  String? _activeDirectorName;
  bool _emailManuallyEdited = false;

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
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final client = Supabase.instance.client;
    final currentUser = ref.read(authStateProvider).user;
    final isDirector = AppRoles.isDirector(currentUser?.role);

    try {
      var usersQuery = client.from('users').select('username, email');
      if (isDirector) {
        usersQuery = usersQuery.neq('role', 'admin');
      }

      final results = await Future.wait<dynamic>([
        client.from('sections').select('id, name, grade, school_id').eq('school_id', _ciroSchoolId),
        usersQuery,
        client.from('users').select('id, username, full_name').inFilter('role', ['subadmin', 'director']).neq('is_active', false),
      ]);

      if (!mounted) return;

      final sectionRows = results[0] as List;
      final userRows = results[1] as List;
      final directorRows = results[2] as List;

      final activeDirectorCount = directorRows.length;
      final activeDirectorName = directorRows.isNotEmpty
          ? (directorRows.first['full_name'] as String? ?? directorRows.first['username'] as String?)
          : null;

      setState(() {
        _sections = List<Map<String, dynamic>>.from(sectionRows);
        _resolveMatchingSectionId();
        _activeDirectorCount = activeDirectorCount;
        _activeDirectorName = activeDirectorName;

        if (isDirector) {
          _selectedRole = AppRoles.teacher;
        } else if (currentUser?.isAttendanceTeacher == true) {
          _selectedRole = AppRoles.student;
          if (currentUser?.attendanceGrade != null && currentUser!.attendanceGrade!.isNotEmpty) {
            _selectedGrade = currentUser.attendanceGrade!;
          }
          if (currentUser?.attendanceClass != null && currentUser!.attendanceClass!.isNotEmpty) {
            _selectedClass = currentUser.attendanceClass!;
          }
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
    } catch (e) {
      debugPrint('Error loading initial registration data: $e');
    }
  }

  void _resolveMatchingSectionId() {
    if (_sections.isEmpty) {
      _selectedSectionId = null;
      return;
    }

    final letterOnly = _selectedClass.replaceAll(RegExp(r'^[0-9]+'), '');
    Map<String, dynamic>? match;
    for (final s in _sections) {
      final sGrade = s['grade']?.toString() ?? '';
      final sName = s['name']?.toString() ?? '';
      final gradeMatch = sGrade.toLowerCase() == _selectedGrade.toLowerCase() ||
          sGrade.toLowerCase().contains(_selectedGrade.toLowerCase());
      final classMatch = sName.toLowerCase() == _selectedClass.toLowerCase() ||
          sName.toLowerCase() == letterOnly.toLowerCase() ||
          '$sGrade $sName'.toLowerCase() == _selectedClass.toLowerCase();
      if (gradeMatch && classMatch) {
        match = s;
        break;
      }
    }

    _selectedSectionId = match?['id'] as String? ?? _sections.first['id'] as String;
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
        if (!_emailManuallyEdited || _emailController.text.trim().isEmpty) {
          _emailController.text = generated.toLowerCase();
        }
        _passwordController.text = defaultRolePassword(
          usernameOrFullName: generated,
          role: _selectedRole,
        );
        setState(() {});
      });
    }
  }

  void _onRoleChanged(String newRole) {
    setState(() {
      _selectedRole = newRole;
      if (newRole != AppRoles.teacher) {
        _isAttendanceTeacher = false;
      }
    });

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
          if (!_emailManuallyEdited || _emailController.text.trim().isEmpty) {
            _emailController.text = generated.toLowerCase();
          }
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
    final currentUser = ref.read(authStateProvider).user;
    if (AppRoles.isDirector(currentUser?.role) && _selectedRole != AppRoles.teacher) {
      setState(() {
        _errorMessage = 'School Directors are authorized to register faculty teachers only.';
      });
      return;
    }

    if (_selectedRole == AppRoles.subadmin && _activeDirectorCount >= 1) {
      setState(() {
        _errorMessage =
            'Ciro High School already has an appointed School Director (${_activeDirectorName ?? "1 active"}). Only one director is permitted at a time. To change the director, manage or deactivate the existing director from User Rosters first.';
      });
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final fullName = _fullNameController.text.trim();
    var username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final subject = _subjectController.text.trim();
    final phone = _phoneController.text.trim();

    _resolveMatchingSectionId();

    try {
      // 1. Pre-flight credential availability check
      try {
        final checkRes = await Supabase.instance.client.rpc(
          'check_user_credentials_available',
          params: {'p_email': email, 'p_username': username},
        );
        if (checkRes is Map) {
          if (checkRes['email_available'] == false) {
            setState(() {
              _isLoading = false;
              _errorMessage =
                  'The email address "$email" is already registered to another account. Please provide a different email address.';
            });
            return;
          }
          if (checkRes['username_available'] == false) {
            final suggested = checkRes['suggested_username'] as String?;
            if (suggested != null && suggested.isNotEmpty) {
              username = suggested;
              _usernameController.text = suggested;
            } else {
              setState(() {
                _isLoading = false;
                _errorMessage =
                    'The username "$username" is already in use. Please choose a different username.';
              });
              return;
            }
          }
        }
      } catch (checkErr) {
        debugPrint('Pre-flight check note: $checkErr');
      }

      // 2. Call dedicated, authoritative admin_create_user RPC
      final rpcRes = await Supabase.instance.client.rpc(
        'admin_create_user',
        params: {
          'p_email': email,
          'p_password': password,
          'p_full_name': fullName,
          'p_role': _selectedRole,
          'p_username': username,
          'p_school_id': _ciroSchoolId,
          'p_section_id': _selectedRole == AppRoles.subadmin ? null : _selectedSectionId,
          'p_subject': _selectedRole == AppRoles.teacher && subject.isNotEmpty ? subject : null,
          'p_phone_number': phone.isNotEmpty ? phone : null,
          'p_gender': _selectedGender,
          'p_grade': _selectedRole == AppRoles.subadmin ? null : _selectedGrade,
          'p_class': _selectedRole == AppRoles.subadmin ? null : _selectedClass,
          'p_is_attendance_teacher': _selectedRole == AppRoles.teacher && _isAttendanceTeacher,
          'p_attendance_grade': _selectedRole == AppRoles.teacher && _isAttendanceTeacher ? _selectedGrade : null,
          'p_attendance_class': _selectedRole == AppRoles.teacher && _isAttendanceTeacher ? _selectedClass : null,
        },
      );

      if (rpcRes is Map) {
        if (rpcRes['success'] != true) {
          final errCode = rpcRes['error']?.toString();
          final errMsg = rpcRes['message']?.toString() ?? 'Registration failed';
          if (errCode == 'username_taken') {
            final nextUname = nextRoleUsername(
              fullName: fullName,
              role: _selectedRole,
              existingUsernames: [..._existingUsernames, username],
            );
            if (nextUname.isNotEmpty) {
              _usernameController.text = nextUname;
              _existingUsernames.add(username);
            }
          }
          setState(() {
            _isLoading = false;
            _errorMessage = errMsg;
          });
          return;
        }
      }

      if (!mounted) return;

      _existingUsernames.add(username);
      _existingEmails.add(email.toLowerCase());

      await _showSuccessDialog(
        fullName: fullName,
        username: username,
        password: password,
        role: _selectedRole,
        assignedGrade: _selectedRole == AppRoles.subadmin ? null : _selectedGrade,
        assignedClass: _selectedRole == AppRoles.subadmin ? null : _selectedClass,
        isAttendanceTeacher: _selectedRole == AppRoles.teacher && _isAttendanceTeacher,
      );

      // Reset form
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _fullNameController.clear();
        _usernameController.clear();
        _emailController.clear();
        _passwordController.clear();
        _subjectController.clear();
        _phoneController.clear();
        _emailManuallyEdited = false;
        setState(() {
          _isAttendanceTeacher = false;
          _selectedGender = 'Male';
        });
      });
      _loadInitialData();
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
    String? assignedGrade,
    String? assignedClass,
    bool isAttendanceTeacher = false,
  }) async {
    final roleName = switch (role) {
      AppRoles.subadmin => 'School Director',
      AppRoles.teacher => isAttendanceTeacher
          ? 'Attendance Teacher ($assignedClass)'
          : 'Faculty Teacher',
      AppRoles.student => 'Student ($assignedClass)',
      _ => 'Administrator',
    };

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;

        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
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
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Account for $fullName has been created and immediately activated for $_schoolName.',
                  style: TextStyle(
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CREDENTIALS TO PROVIDE USER',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            'Username: ',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
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
                          Text(
                            'Password: ',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          Expanded(
                            child: SelectableText(
                              password,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (assignedGrade != null && assignedClass != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              'Class Assignment: ',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              isAttendanceTeacher
                                  ? 'Attendance Master for Class $assignedClass ($assignedGrade)'
                                  : 'Class $assignedClass ($assignedGrade)',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                      ],
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
                          foregroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
                          side: BorderSide(
                            color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                          ),
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
                                  'Institution: $_schoolName\nRole: $roleName\nFull Name: $fullName\nUsername: $username\nPassword: $password${assignedClass != null ? "\nClass: $assignedClass ($assignedGrade)" : ""}',
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
                        backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFF0F172A),
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
                if (role == AppRoles.teacher) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF10B981),
                        side: const BorderSide(color: Color(0xFF10B981)),
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.co_present_rounded, size: 16),
                      label: const Text('Assign Additional Grades & Sections'),
                      onPressed: () {
                        Navigator.pop(dialogCtx);
                        context.push('/admin/assignments');
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentUser = ref.watch(authStateProvider).user;
    final isDirector = AppRoles.isDirector(currentUser?.role);

    final roleColor = switch (_selectedRole) {
      AppRoles.teacher => const Color(0xFF10B981),
      AppRoles.subadmin => const Color(0xFF6366F1),
      AppRoles.admin => const Color(0xFF0F172A),
      _ => const Color(0xFF3B82F6),
    };

    return DashboardShell(
      title: isDirector
          ? 'Register Faculty Teacher'
          : (currentUser?.isAttendanceTeacher == true
              ? 'Register Class Student'
              : 'Register New User'),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Institutional Banner (Ciro High School)
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
                  height: 120,
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
                          switch (_selectedRole) {
                            AppRoles.subadmin => Icons.admin_panel_settings_outlined,
                            AppRoles.admin => Icons.shield_rounded,
                            AppRoles.teacher => Icons.co_present_rounded,
                            _ => Icons.school_rounded,
                          },
                          color: roleColor,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Ciro High School',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'OFFICIAL CAMPUS',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF047857),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isDirector
                                  ? 'Register and assign Faculty Teachers to designated grades, sections, and subjects.'
                                  : (currentUser?.isAttendanceTeacher == true
                                      ? 'Register and assign students to Class ${currentUser?.attendanceClass ?? "9A"}.'
                                      : 'Register and activate School Directors, Faculty Teachers (with Grade & Section), or Students.'),
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

          // Error Notification
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
                  // 1. Role Selector
                  const Text(
                    '1. Select Institutional Role',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Builder(
                    builder: (context) {
                      final currentUser = ref.watch(authStateProvider).user;
                      final isDirector = AppRoles.isDirector(currentUser?.role);
                      final isAttendanceTeacher = currentUser?.isAttendanceTeacher == true;

                      if (isDirector) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF10B981).withValues(alpha: 0.3),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.co_present_rounded,
                                    color: Color(0xFF047857), size: 22),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Designated Role: Faculty Teacher',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                        color: Color(0xFF047857),
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'School Director is authorized to register Faculty Teachers only.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF065F46),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.2),
                                  foregroundColor: const Color(0xFF047857),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  minimumSize: const Size(0, 36),
                                ),
                                icon: const Icon(Icons.manage_accounts_rounded, size: 16),
                                label: const Text(
                                  'Manage',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                onPressed: () => context.push('/admin/teachers'),
                              ),
                            ],
                          ),
                        );
                      }

                      if (isAttendanceTeacher) {
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              avatar: const Icon(Icons.school_outlined, size: 16),
                              label: Text('Student (${currentUser?.attendanceClass ?? "Assigned Class"})',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              selected: true,
                              onSelected: (_) => _onRoleChanged(AppRoles.student),
                            ),
                          ],
                        );
                      }

                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            avatar: const Icon(Icons.school_outlined, size: 16),
                            label: const Text('Student',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            selected: _selectedRole == AppRoles.student,
                            onSelected: (selected) {
                              if (selected) _onRoleChanged(AppRoles.student);
                            },
                          ),
                          ChoiceChip(
                            avatar: const Icon(Icons.co_present_outlined, size: 16),
                            label: const Text('Faculty Teacher',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            selected: _selectedRole == AppRoles.teacher,
                            onSelected: (selected) {
                              if (selected) _onRoleChanged(AppRoles.teacher);
                            },
                          ),
                          if (currentUser?.isSuperAdmin == true || currentUser?.role == AppRoles.admin)
                            ChoiceChip(
                              avatar: const Icon(Icons.manage_accounts_rounded, size: 16),
                              label: Text(
                                _activeDirectorCount >= 1
                                    ? 'School Director (1 Appointed)'
                                    : 'School Director',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              selected: _selectedRole == AppRoles.subadmin,
                              onSelected: (selected) {
                                if (selected) _onRoleChanged(AppRoles.subadmin);
                              },
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // School Director role informative banner
                  if (_selectedRole == AppRoles.subadmin) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _activeDirectorCount >= 1
                            ? const Color(0xFFFFFBEB)
                            : const Color(0xFF6366F1).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _activeDirectorCount >= 1
                              ? const Color(0xFFFDE68A)
                              : const Color(0xFF6366F1).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _activeDirectorCount >= 1
                                ? Icons.warning_amber_rounded
                                : Icons.manage_accounts_rounded,
                            color: _activeDirectorCount >= 1
                                ? const Color(0xFFD97706)
                                : const Color(0xFF6366F1),
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _activeDirectorCount >= 1
                                      ? 'Director Limit Reached (Maximum 1 Director)'
                                      : 'Ciro High School Director',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: _activeDirectorCount >= 1
                                        ? const Color(0xFF92400E)
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _activeDirectorCount >= 1
                                      ? 'Ciro High School already has an appointed School Director (${_activeDirectorName ?? "1 active"}). Only one director is permitted at a time. To replace the director, manage or deactivate the existing director from User Rosters first.'
                                      : 'School Directors oversee Ciro High School faculty teachers, grade enrollment totals, and post announcements. No grade or section is required for this administrative role.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _activeDirectorCount >= 1
                                        ? const Color(0xFFB45309)
                                        : const Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // 2. User Identity Details
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
                          'Ends in @${_selectedRole == AppRoles.teacher ? 'Teacher' : AppRoles.isAdmin(_selectedRole) ? 'Admin' : 'Student'}.edu (Deduplicated automatically)',
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
                    onChanged: (val) {
                      _emailManuallyEdited = val.trim().isNotEmpty;
                    },
                    validator: (value) => value == null ||
                            !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())
                        ? 'Enter a valid email address'
                        : null,
                  ),
                  const SizedBox(height: 14),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _phoneController,
                          decoration: const InputDecoration(
                            labelText: 'Phone Number',
                            hintText: '+251 91 123 4567',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                          keyboardType: TextInputType.phone,
                          validator: Validators.phone,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedGender,
                          decoration: const InputDecoration(
                            labelText: 'Gender',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                          items: _genders
                              .map(
                                (g) => DropdownMenuItem(
                                  value: g,
                                  child: Text(g),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedGender = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Dynamic Password Card
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

                  // 3. Campus & Academic Allocations
                  const Text(
                    '3. Campus & Academic Assignment',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),

                  // Fixed Ciro High School Badge (No multi-school dropdowns!)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.domain_rounded, color: Color(0xFF047857), size: 24),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Institution Campus',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF047857),
                                ),
                              ),
                              Text(
                                'Ciro High School',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF047857),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 20),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Attendance Teacher fixed homeroom indicator
                  if (ref.watch(authStateProvider).user?.isAttendanceTeacher == true) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.how_to_reg_rounded, color: Color(0xFF047857), size: 24),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Homeroom Target: Class $_selectedClass ($_selectedGrade)',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                      color: Color(0xFF065F46)),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'As the appointed Attendance Teacher, student registrations created here are registered directly for your homeroom class.',
                                  style: TextStyle(fontSize: 12, color: Color(0xFF047857)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ] else if (_selectedRole != AppRoles.subadmin) ...[
                    // Grade Dropdown for Teachers and Students
                    DropdownButtonFormField<String>(
                      initialValue: _selectedGrade,
                      decoration: const InputDecoration(
                        labelText: 'Assigned Grade Level',
                        prefixIcon: Icon(Icons.grade_rounded),
                      ),
                      items: [
                        for (final g in _grades)
                          DropdownMenuItem(
                            value: g,
                            child: Text(g),
                          ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedGrade = val;
                            final classes = _getClassesForGrade(val);
                            if (!classes.contains(_selectedClass)) {
                              _selectedClass = classes.first;
                            }
                            _resolveMatchingSectionId();
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 14),

                    // Class / Section Dropdown (e.g. 9A, 9B, 9C)
                    DropdownButtonFormField<String>(
                      key: ValueKey('ciro_class_${_selectedGrade}_$_selectedClass'),
                      initialValue: _selectedClass,
                      decoration: InputDecoration(
                        labelText: _selectedRole == AppRoles.teacher
                            ? 'Assigned Teaching Class (e.g. 9A, 9B)'
                            : 'Student Class (e.g. 9A, 9B)',
                        prefixIcon: const Icon(Icons.meeting_room_outlined),
                      ),
                      items: [
                        for (final c in _getClassesForGrade(_selectedGrade))
                          DropdownMenuItem(
                            value: c,
                            child: Text('Class $c'),
                          ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedClass = val;
                            _resolveMatchingSectionId();
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 14),

                    // TEACHER SPECIFIC: Subject & Attendance Designation
                    if (_selectedRole == AppRoles.teacher) ...[
                      TextFormField(
                        controller: _subjectController,
                        decoration: const InputDecoration(
                          labelText: 'Teacher Subject / Specialty',
                          hintText: 'e.g. Mathematics, Physics, English, Chemistry',
                          prefixIcon: Icon(Icons.menu_book_outlined),
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Enter primary subject'
                                : null,
                      ),
                      const SizedBox(height: 18),

                      // ATTENDANCE TEACHER HOMEROOM MASTER TOGGLE
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _isAttendanceTeacher
                              ? const Color(0xFF10B981).withValues(alpha: 0.1)
                              : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _isAttendanceTeacher
                                ? const Color(0xFF10B981)
                                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                            width: _isAttendanceTeacher ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Row(
                                children: [
                                  Icon(Icons.how_to_reg_rounded,
                                      color: Color(0xFF10B981), size: 22),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Designate as Attendance Teacher',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Appoint this faculty member as the official Attendance Master for Class $_selectedClass ($_selectedGrade). They can register students and review pending registrations for this homeroom class.',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              value: _isAttendanceTeacher,
                              onChanged: (val) =>
                                  setState(() => _isAttendanceTeacher = val),
                            ),
                            if (_isAttendanceTeacher) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.star_rounded,
                                        color: Color(0xFF059669), size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Official Attendance Teacher for Class $_selectedClass ($_selectedGrade)',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF047857),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ],

                  const SizedBox(height: 10),

                  // Immediate Activation Info
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
                            'Immediate Activation: Accounts registered by Administrators or Attendance Teachers are pre-approved and can sign in instantly.',
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
                  AnimatedPressButton(
                    onTap: _isLoading ? null : _registerUser,
                    child: Container(
                      height: 52,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: _isLoading ? const Color(0xFF334155) : const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.person_add_rounded, size: 20, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  'Register & Activate User',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                    ),
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
