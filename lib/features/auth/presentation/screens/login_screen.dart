import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/theme/theme_mode_provider.dart';
import 'package:quiz_app/core/utils/role_username.dart';
import 'package:quiz_app/core/utils/validators.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/shared/widgets/animated_press_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({this.registrationPage = false, this.role, super.key});

  final bool registrationPage;
  final String? role;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _subjectController = TextEditingController();
  final _phoneController = TextEditingController();
  String _selectedGender = 'Male';
  final List<String> _genders = const ['Male', 'Female', 'Other'];

  final _imagePicker = ImagePicker();
  XFile? _pickedAvatarFile;
  Uint8List? _pickedAvatarBytes;

  final _otpController = TextEditingController();
  bool _useOtpLogin = false;
  bool _otpSent = false;
  String _targetOtpEmail = '';
  bool _isSendingOtp = false;

  late Future<List<Map<String, dynamic>>> _schoolsFuture;
  Future<List<Map<String, dynamic>>> _sectionsFuture = Future.value([]);

  String? _selectedSchoolId;
  String? _selectedSectionId;
  String? _selectedSectionGradeName;
  String? _selectedTeacherClassName;

  bool _schoolsReady = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  late bool _isRegistering;
  String _requestedRole = 'student';

  @override
  void initState() {
    super.initState();
    _isRegistering = widget.registrationPage;
    _requestedRole = widget.role == 'teacher' ? 'teacher' : 'student';
    _schoolsFuture = _isRegistering ? _loadSchools() : Future.value([]);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _subjectController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _switchMode(bool registering) {
    if (_isRegistering == registering) return;
    setState(() {
      _isRegistering = registering;
      if (_isRegistering && !_schoolsReady) {
        _schoolsFuture = _loadSchools();
      }
    });
    ref.read(authStateProvider.notifier).clearMessages();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(authStateProvider.notifier);

    if (_isRegistering) {
      var username = _usernameController.text.trim();
      if (!isRoleUsername(username, _requestedRole)) {
        notifier.setMessage(
          error:
              'Use the suggested username ending in @${_requestedRole == 'teacher' ? 'Teacher' : 'Students'}.edu.',
        );
        return;
      }
      var emailToUse = _emailController.text.trim().isNotEmpty
          ? _emailController.text.trim().toLowerCase()
          : username.toLowerCase();

      // Proactively check for duplicate email or username in database
      try {
        final checkRes = await Supabase.instance.client.rpc(
          'check_user_exists',
          params: {'p_email': emailToUse, 'p_username': username},
        );
        if (checkRes is Map) {
          final bool emailTaken = checkRes['email_taken'] == true;
          final bool usernameTaken = checkRes['username_taken'] == true;

          if (usernameTaken) {
            // Retrieve all matching usernames to automatically advance to the next number
            final namePart = username.split('@').first;
            final existingList = <String>[username];
            try {
              final rpcMatches = await Supabase.instance.client.rpc(
                'get_matching_usernames',
                params: {'p_prefix': namePart},
              );
              if (rpcMatches is List) {
                existingList.addAll(
                  rpcMatches
                      .map((r) => (r is Map ? r['username'] : r) as String? ?? '')
                      .where((u) => u.isNotEmpty),
                );
              }
            } catch (_) {}

            final nextUname = nextRoleUsername(
              fullName: _nameController.text.trim(),
              role: _requestedRole,
              existingUsernames: existingList,
            );

            if (nextUname.isNotEmpty && nextUname != username) {
              username = nextUname;
              emailToUse = nextUname.toLowerCase();
              _usernameController.text = username;
              _emailController.text = emailToUse;
              _syncDefaultPassword(username);
              notifier.setMessage(
                error:
                    'Username was already taken. Automatically updated to your next unique identifier: $username. Please verify and tap Register.',
              );
              return;
            }
          }

          if (emailTaken) {
            notifier.setMessage(
              error:
                  'An account with email "$emailToUse" is already registered. Please sign in or use a different email address.',
            );
            return;
          }
        }
      } catch (checkErr) {
        debugPrint('check_user_exists note: $checkErr');
      }

      await notifier.register(
        fullName: _nameController.text.trim(),
        username: username,
        email: emailToUse,
        password: _passwordController.text,
        requestedRole: _requestedRole,
        schoolId: _selectedSchoolId,
        sectionId: _requestedRole == 'student' ? _selectedSectionId : null,
        requestedGrade: _selectedSectionGradeName,
        requestedClass: _requestedRole == 'teacher'
            ? _selectedTeacherClassName
            : null,
        requestedSubject: _requestedRole == 'teacher'
            ? _subjectController.text.trim()
            : null,
        phoneNumber: _phoneController.text.trim(),
        gender: _selectedGender,
      );
      if (_pickedAvatarFile != null) {
        try {
          await ref.read(authStateProvider.notifier).saveAvatar(_pickedAvatarFile!);
        } catch (e) {
          debugPrint('Profile photo registration upload: $e');
        }
      }
    } else {
      if (_useOtpLogin) {
        if (!_otpSent) {
          await _sendLoginOtp();
        } else {
          await _verifyLoginOtp();
        }
      } else {
        await notifier.signIn(
          emailOrUsername: _usernameController.text.trim(),
          password: _passwordController.text,
          expectedRole: roleFromUsername(_usernameController.text.trim()),
        );
      }
    }
  }

  Future<void> _sendLoginOtp() async {
    final input = _usernameController.text.trim();
    if (input.isEmpty) {
      ref.read(authStateProvider.notifier).setMessage(
        error: 'Enter your email, username, or phone number to receive an OTP code.',
      );
      return;
    }
    setState(() => _isSendingOtp = true);
    final email = await ref.read(authStateProvider.notifier).sendLoginOtp(input);
    if (mounted) {
      setState(() {
        _isSendingOtp = false;
        if (email != null) {
          _otpSent = true;
          _targetOtpEmail = email;
        }
      });
    }
  }

  Future<void> _verifyLoginOtp() async {
    final token = _otpController.text.trim();
    if (token.isEmpty || token.length < 6) {
      ref.read(authStateProvider.notifier).setMessage(
        error: 'Enter the 6-digit verification code sent to your email.',
      );
      return;
    }
    await ref.read(authStateProvider.notifier).verifyLoginOtp(
      email: _targetOtpEmail.isNotEmpty ? _targetOtpEmail : _usernameController.text.trim(),
      token: token,
      expectedRole: roleFromUsername(_usernameController.text.trim()),
    );
  }

  Future<void> _pickAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Profile Picture',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take Photo with Camera'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              if (_pickedAvatarFile != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'Remove Photo',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _pickedAvatarFile = null;
                      _pickedAvatarBytes = null;
                    });
                  },
                ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    try {
      final image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (mounted) {
        setState(() {
          _pickedAvatarFile = image;
          _pickedAvatarBytes = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not access image: $e')),
        );
      }
    }
  }

  Future<void> _sendReset() async {
    final emailController = TextEditingController(text: _usernameController.text.trim());
    final otpCodeController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool codeSent = false;
    bool isWorking = false;
    String targetEmail = '';
    String? dialogError;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.lock_reset_rounded, color: Color(0xFF10B981)),
              ),
              const SizedBox(width: 12),
              const Text('Reset Password'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!codeSent) ...[
                  const Text(
                    'Enter your registered email, username, or phone number. A 6-digit OTP code will be sent to your email to verify and reset your password:',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: emailController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Email, Username, or Phone',
                      hintText: 'e.g. user@gmail.com, YonasD, or 0911234567',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.mark_email_read_outlined, size: 18, color: Color(0xFF10B981)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '6-digit code sent to $targetEmail. Check your inbox and spam folder.',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: otpCodeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: '6-Digit OTP Code',
                      hintText: '123456',
                      prefixIcon: Icon(Icons.pin_outlined),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New Password',
                      hintText: 'At least 8 characters',
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm New Password',
                      prefixIcon: Icon(Icons.lock_reset_rounded),
                    ),
                  ),
                ],
                if (dialogError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    dialogError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isWorking ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            if (!codeSent)
              FilledButton(
                onPressed: isWorking
                    ? null
                    : () async {
                        final input = emailController.text.trim();
                        if (input.isEmpty) {
                          setDialogState(() => dialogError = 'Please enter your email or username.');
                          return;
                        }
                        setDialogState(() {
                          isWorking = true;
                          dialogError = null;
                        });
                        try {
                          final email = await ref
                              .read(authStateProvider.notifier)
                              .sendPasswordReset(input);
                          if (email != null) {
                            setDialogState(() {
                              codeSent = true;
                              targetEmail = email;
                              isWorking = false;
                            });
                          } else {
                            setDialogState(() {
                              isWorking = false;
                              dialogError = 'Could not send reset code. Please check your username/email.';
                            });
                          }
                        } catch (e) {
                          setDialogState(() {
                            isWorking = false;
                            dialogError = e.toString();
                          });
                        }
                      },
                child: isWorking
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Send 6-Digit Code'),
              )
            else
              FilledButton(
                onPressed: isWorking
                    ? null
                    : () async {
                        final token = otpCodeController.text.trim();
                        final newPw = newPasswordController.text;
                        final confirmPw = confirmPasswordController.text;

                        if (token.length < 6) {
                          setDialogState(() => dialogError = 'Enter the complete 6-digit OTP code.');
                          return;
                        }
                        if (newPw.length < 8) {
                          setDialogState(() => dialogError = 'New password must be at least 8 characters.');
                          return;
                        }
                        if (newPw != confirmPw) {
                          setDialogState(() => dialogError = 'Passwords do not match.');
                          return;
                        }

                        setDialogState(() {
                          isWorking = true;
                          dialogError = null;
                        });

                        final success = await ref
                            .read(authStateProvider.notifier)
                            .verifyPasswordResetOtp(
                              email: targetEmail,
                              token: token,
                              newPassword: newPw,
                            );

                        if (success) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Password successfully changed! Please sign in with your new password.'),
                                backgroundColor: Color(0xFF10B981),
                              ),
                            );
                          }
                        } else {
                          setDialogState(() {
                            isWorking = false;
                            dialogError = 'Invalid code or reset failed. Please check the code.';
                          });
                        }
                      },
                child: isWorking
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Verify & Update Password'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: widget.registrationPage
            ? IconButton(
                tooltip: 'Back to sign in',
                onPressed: () {
                  ref.read(authStateProvider.notifier).clearMessages();
                  context.go('/login');
                },
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : null,
        actions: [
          IconButton(
            tooltip: isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme',
            onPressed: () {
              final newMode = isDark ? ThemeMode.light : ThemeMode.dark;
              ref.read(themeModeProvider.notifier).setMode(newMode);
            },
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    width: 1.2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // App Brand Header
                        Center(
                          child: Column(
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                      blurRadius: 18,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child: Image.asset(
                                    'assets/images/logo.png',
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Icon(
                                      Icons.school_rounded,
                                      size: 36,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'CIRO SCHOOLS QUIZ',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                  color: isDark
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFF059669),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isRegistering ? 'Create your account' : 'Welcome back',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isRegistering
                                    ? 'Join your school community to test and learn'
                                    : 'Enter your credentials to access your portal',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF64748B),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Mode Switcher Tabs (Sign In / Register)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF0F172A)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _TabPill(
                                  label: 'Sign in',
                                  icon: Icons.login_rounded,
                                  selected: !_isRegistering,
                                  onTap: () => _switchMode(false),
                                  isDark: isDark,
                                ),
                              ),
                              Expanded(
                                child: _TabPill(
                                  label: 'Register',
                                  icon: Icons.person_add_rounded,
                                  selected: _isRegistering,
                                  onTap: () => _switchMode(true),
                                  isDark: isDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Registration fields
                        if (_isRegistering) ...[
                          Center(
                            child: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                InkWell(
                                  onTap: _pickAvatar,
                                  borderRadius: BorderRadius.circular(44),
                                  child: CircleAvatar(
                                    radius: 40,
                                    backgroundColor: isDark
                                        ? const Color(0xFF1E293B)
                                        : const Color(0xFFF1F5F9),
                                    backgroundImage: _pickedAvatarBytes != null
                                        ? MemoryImage(_pickedAvatarBytes!)
                                        : null,
                                    child: _pickedAvatarBytes == null
                                        ? Icon(
                                            Icons.person_outline_rounded,
                                            size: 42,
                                            color: isDark
                                                ? const Color(0xFF94A3B8)
                                                : const Color(0xFF64748B),
                                          )
                                        : null,
                                  ),
                                ),
                                Material(
                                  color: theme.colorScheme.primary,
                                  shape: const CircleBorder(),
                                  elevation: 2,
                                  child: InkWell(
                                    onTap: _pickAvatar,
                                    customBorder: const CircleBorder(),
                                    child: const Padding(
                                      padding: EdgeInsets.all(6),
                                      child: Icon(
                                        Icons.camera_alt_rounded,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Center(
                            child: TextButton.icon(
                              onPressed: _pickAvatar,
                              icon: const Icon(Icons.add_a_photo_outlined, size: 15),
                              label: Text(
                                _pickedAvatarBytes == null
                                    ? 'Take or Choose Profile Photo'
                                    : 'Change Profile Photo',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          const Text(
                            'Choose account type',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              for (final option in const [
                                (role: 'student', label: 'Student', icon: Icons.school_outlined),
                                (role: 'teacher', label: 'Teacher', icon: Icons.co_present_outlined),
                              ])
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: ChoiceChip(
                                      avatar: Icon(option.icon, size: 16),
                                      label: Text(option.label),
                                      selected: _requestedRole == option.role,
                                      onSelected: (selected) {
                                        if (!selected) return;
                                        setState(() => _requestedRole = option.role);
                                        _updateGeneratedUsername();
                                        ref.read(authStateProvider.notifier).clearMessages();
                                      },
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _nameController,
                            onChanged: (_) => _updateGeneratedUsername(),
                            textCapitalization: TextCapitalization.words,
                            autofillHints: const [AutofillHints.name],
                            decoration: const InputDecoration(
                              labelText: 'Full name',
                              hintText: 'First and last name',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                            validator: (value) {
                              if (!_isRegistering) return null;
                              if (value == null ||
                                  value.trim().split(RegExp(r'\s+')).length < 2) {
                                return 'Enter your first and last name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Username or email field
                        TextFormField(
                          controller: _usernameController,
                          autofillHints: _isRegistering
                              ? const [AutofillHints.newUsername]
                              : const [AutofillHints.username],
                          decoration: InputDecoration(
                            labelText: _isRegistering ? 'Suggested username' : 'Email, Username, or Phone',
                            hintText: _isRegistering
                                ? 'Name@${_requestedRole == 'teacher' ? 'Teacher' : 'Student'}.edu'
                                : 'e.g. user@gmail.com, WondeAdmin, or phone',
                            helperText: _isRegistering
                                ? 'Institutional format: Name@${_requestedRole == 'teacher' ? 'Teacher' : 'Student'}.edu'
                                : null,
                            prefixIcon: const Icon(Icons.alternate_email_rounded),
                          ),
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            if (_isRegistering) {
                              if (value == null || !isRoleUsername(value.trim(), _requestedRole)) {
                                final suffix = _requestedRole == 'teacher' ? 'Teacher' : 'Student';
                                return 'Use a username ending in @$suffix.edu';
                              }
                              return null;
                            }
                            return Validators.username(value);
                          },
                        ),
                        const SizedBox(height: 14),

                        if (_isRegistering) ...[
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'Email address',
                              hintText: 'name@school.edu',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                            validator: (value) =>
                                _isRegistering ? Validators.email(value) : null,
                          ),
                          const SizedBox(height: 14),

                          // Phone Number
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            autofillHints: const [AutofillHints.telephoneNumber],
                            decoration: const InputDecoration(
                              labelText: 'Phone number',
                              hintText: '+251 91 123 4567 or 0911234567',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                            validator: (value) =>
                                _isRegistering ? Validators.phone(value) : null,
                          ),
                          const SizedBox(height: 14),

                          // Gender Selection Dropdown
                          DropdownButtonFormField<String>(
                            initialValue: _selectedGender,
                            decoration: const InputDecoration(
                              labelText: 'Gender',
                              prefixIcon: Icon(Icons.person_pin_circle_outlined),
                            ),
                            items: _genders.map((g) {
                              return DropdownMenuItem(
                                value: g,
                                child: Text(g),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedGender = val);
                            },
                          ),
                          const SizedBox(height: 14),

                          _schoolSelector(),
                          const SizedBox(height: 14),

                          _sectionSelector(),
                          const SizedBox(height: 14),

                          if (_requestedRole == 'teacher') ...[
                            TextFormField(
                              controller: _subjectController,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Main subject you teach',
                                hintText: 'e.g. Mathematics, Physics',
                                prefixIcon: Icon(Icons.menu_book_outlined),
                              ),
                              validator: (value) => _isRegistering &&
                                      _requestedRole == 'teacher' &&
                                      (value == null || value.trim().isEmpty)
                                  ? 'Enter your subject'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                          ],

                          // Default Password Helper Card
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
                                    const Icon(
                                      Icons.auto_awesome_rounded,
                                      size: 16,
                                      color: Color(0xFF10B981),
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'Default Password Pattern',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    if (_usernameController.text.isNotEmpty)
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        icon: const Icon(Icons.copy_rounded, size: 13),
                                        label: const Text(
                                          'Use & Copy',
                                          style: TextStyle(fontSize: 11),
                                        ),
                                        onPressed: () {
                                          final pw = defaultRolePassword(
                                            usernameOrFullName: _usernameController.text,
                                            role: _requestedRole,
                                          );
                                          setState(() {
                                            _passwordController.text = pw;
                                            _confirmController.text = pw;
                                          });
                                          Clipboard.setData(ClipboardData(text: pw));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Password applied & copied: $pw'),
                                              duration: const Duration(seconds: 2),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _usernameController.text.isNotEmpty
                                      ? defaultRolePassword(
                                          usernameOrFullName: _usernameController.text,
                                          role: _requestedRole,
                                        )
                                      : 'Formula: Name1@${roleLetter(_requestedRole)}.edu',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Password or OTP login mode
                        if (!_isRegistering && _useOtpLogin) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF10B981).withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.mark_email_unread_outlined, color: Color(0xFF10B981), size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _otpSent
                                        ? '6-digit OTP code sent to $_targetOtpEmail. Enter it below:'
                                        : 'Enter your email or username above, then tap below to receive a 6-digit login OTP code in your email.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF065F46),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_otpSent) ...[
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _otpController,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              decoration: const InputDecoration(
                                labelText: '6-Digit OTP Code',
                                hintText: '123456',
                                prefixIcon: Icon(Icons.pin_outlined),
                                counterText: '',
                              ),
                              validator: (v) {
                                if (_useOtpLogin && _otpSent && (v == null || v.trim().length < 6)) {
                                  return 'Enter the complete 6-digit OTP code';
                                }
                                return null;
                              },
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _useOtpLogin = false;
                                    _otpSent = false;
                                  });
                                },
                                icon: const Icon(Icons.lock_outline_rounded, size: 16),
                                label: const Text('Use password instead'),
                              ),
                              if (_otpSent)
                                TextButton.icon(
                                  onPressed: _isSendingOtp ? null : _sendLoginOtp,
                                  icon: const Icon(Icons.refresh_rounded, size: 16),
                                  label: const Text('Resend Code'),
                                ),
                            ],
                          ),
                        ] else ...[
                          // Standard Password field
                          TextFormField(
                            controller: _passwordController,
                            autofillHints: _isRegistering
                                ? const [AutofillHints.newPassword]
                                : const [AutofillHints.password],
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            obscureText: _obscurePassword,
                            validator: (value) {
                              if (_useOtpLogin) return null;
                              if (!_isRegistering) {
                                return Validators.password(value);
                              }
                              if (value == null || value.length < 8) {
                                return 'Use at least 8 characters';
                              }
                              return null;
                            },
                          ),
                          if (!_isRegistering) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                TextButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _useOtpLogin = true;
                                      _otpSent = false;
                                    });
                                  },
                                  icon: const Icon(Icons.mark_email_read_outlined, size: 16),
                                  label: const Text('Sign in with Email OTP'),
                                ),
                                TextButton(
                                  onPressed: _sendReset,
                                  child: const Text('Forgot password?'),
                                ),
                              ],
                            ),
                          ],
                        ],

                        if (_isRegistering) ...[
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _confirmController,
                            obscureText: _obscureConfirmation,
                            decoration: InputDecoration(
                              labelText: 'Confirm password',
                              prefixIcon: const Icon(Icons.lock_reset_rounded),
                              suffixIcon: IconButton(
                                tooltip: _obscureConfirmation ? 'Show password' : 'Hide password',
                                onPressed: () => setState(
                                  () => _obscureConfirmation = !_obscureConfirmation,
                                ),
                                icon: Icon(
                                  _obscureConfirmation
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (_isRegistering && value != _passwordController.text) {
                                return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF10B981).withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.verified_user_outlined,
                                  size: 18,
                                  color: Color(0xFF10B981),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _requestedRole == 'teacher'
                                        ? 'Faculty Notice: Your teacher account will be reviewed and approved by the School Administrator or Director before you can sign in.'
                                        : 'Student Notice: Your account will wait for approval from your class Attendance Teacher${_selectedTeacherClassName != null ? ' ($_selectedTeacherClassName)' : ''} or School Administrator before you can sign in.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: isDark
                                          ? const Color(0xFFA7F3D0)
                                          : const Color(0xFF065F46),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        if (authState.error != null) ...[
                          const SizedBox(height: 14),
                          _MessageBanner(message: authState.error!, isError: true),
                        ],
                        if (authState.successMessage != null) ...[
                          const SizedBox(height: 14),
                          _MessageBanner(message: authState.successMessage!),
                        ],
                        if (_isRegistering && authState.successMessage != null) ...[
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => _switchMode(false),
                            child: const Text('Go to sign in'),
                          ),
                        ],
                        const SizedBox(height: 20),

                        // Primary Submit Button
                        AnimatedPressButton(
                          onTap: authState.isLoading ||
                                  (_isRegistering && authState.successMessage != null) ||
                                  (_isRegistering && (!_schoolsReady || _selectedSectionId == null))
                              ? null
                              : _submit,
                          child: Container(
                            height: 50,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF10B981), Color(0xFF059669)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: authState.isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        _isRegistering
                                            ? Icons.person_add_alt_1_rounded
                                            : (_useOtpLogin
                                                ? (_otpSent
                                                    ? Icons.verified_rounded
                                                    : Icons.send_rounded)
                                                : Icons.login_rounded),
                                        size: 18,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _isRegistering
                                            ? 'Create account'
                                            : (_useOtpLogin
                                                ? (_otpSent
                                                    ? 'Verify Code & Sign In'
                                                    : 'Send Login OTP Code')
                                                : 'Sign in'),
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Switcher button at bottom
                        Center(
                          child: TextButton(
                            onPressed: () => _switchMode(!_isRegistering),
                            child: Text(
                              _isRegistering
                                  ? 'Already have an account? Sign in'
                                  : "Don't have an account? Create an account",
                              style: TextStyle(
                                color: isDark
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFF059669),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        Center(
                          child: TextButton.icon(
                            onPressed: () => context.go('/onboarding'),
                            icon: const Icon(Icons.explore_rounded, size: 16),
                            label: const Text(
                              'Explore App Tour & Features',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _schoolSelector() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _schoolsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Could not load schools: ${snapshot.error}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _schoolsReady = false;
                  _schoolsFuture = _loadSchools();
                }),
                child: const Text('Try again'),
              ),
            ],
          );
        }
        if (!snapshot.hasData) {
          return const LinearProgressIndicator();
        }
        final schools = snapshot.data!;
        if (schools.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('No schools are available for registration yet.'),
              TextButton(
                onPressed: () => setState(() {
                  _schoolsReady = false;
                  _schoolsFuture = _loadSchools();
                }),
                child: const Text('Try again'),
              ),
            ],
          );
        }
        return DropdownButtonFormField<String>(
          key: ValueKey('login_school_$_selectedSchoolId'),
          initialValue: _selectedSchoolId,
          decoration: const InputDecoration(
            labelText: 'Your school',
            prefixIcon: Icon(Icons.school_outlined),
          ),
          items: [
            for (final school in schools)
              DropdownMenuItem<String>(
                value: school['id'] as String,
                child: Text(school['name'] as String? ?? 'School'),
              ),
          ],
          onChanged: (schoolId) {
            setState(() {
              _selectedSchoolId = schoolId;
              _selectedSectionId = null;
              _selectedSectionGradeName = null;
              _selectedTeacherClassName = null;
              _sectionsFuture = schoolId == null
                  ? Future.value([])
                  : _loadSections(schoolId);
            });
          },
          validator: (schoolId) =>
              schoolId == null ? 'Choose your school' : null,
        );
      },
    );
  }

  Widget _sectionSelector() {
    if (_selectedSchoolId == null) {
      return const Text('Choose a school to select your grade and section.');
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _sectionsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Could not load grade sections: ${snapshot.error}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: () => setState(
                  () => _sectionsFuture = _loadSections(_selectedSchoolId!),
                ),
                child: const Text('Try loading sections again'),
              ),
            ],
          );
        }
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final sections = snapshot.data!;
        if (sections.isEmpty) {
          return const Text(
            'No grade sections are available. Ask your school administrator to set them up.',
          );
        }
        return DropdownButtonFormField<String>(
          key: ValueKey('login_section_${_selectedSchoolId}_$_selectedSectionId'),
          initialValue: _selectedSectionId,
          decoration: const InputDecoration(
            labelText: 'Grade and class or section',
            prefixIcon: Icon(Icons.class_outlined),
          ),
          items: [
            for (final section in sections)
              DropdownMenuItem<String>(
                value: section['id'] as String,
                child: Text(
                  '${(section['school_grades'] as Map<String, dynamic>)['name']} · ${section['name']}',
                ),
              ),
          ],
          onChanged: (sectionId) {
            final section = sections
                .where((item) => item['id'] == sectionId)
                .firstOrNull;
            final schoolGrade =
                section?['school_grades'] as Map<String, dynamic>?;
            setState(() {
              _selectedSectionId = sectionId;
              _selectedSectionGradeName = schoolGrade?['name'] as String?;
              _selectedTeacherClassName = section?['name'] as String?;
            });
          },
          validator: (sectionId) =>
              sectionId == null ? 'Choose your grade and section' : null,
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadSections(String schoolId) async {
    final rows = await ref
        .read(authStateProvider.notifier)
        .loadSections(schoolId);
    return rows;
  }

  Future<List<Map<String, dynamic>>> _loadSchools() async {
    try {
      final schools = await ref.read(authStateProvider.notifier).loadSchools();
      if (mounted) {
        setState(() {
          _schoolsReady = schools.isNotEmpty;
          if (schools.isNotEmpty && _selectedSchoolId == null) {
            _selectedSchoolId = schools.first['id'] as String;
            _sectionsFuture = _loadSections(_selectedSchoolId!);
          }
        });
      }
      return schools;
    } catch (_) {
      if (mounted) setState(() => _schoolsReady = false);
      rethrow;
    }
  }

  Future<void> _updateGeneratedUsername() async {
    final base = roleUsername(
      _nameController.text,
      _requestedRole,
    );
    if (base.isEmpty) {
      _usernameController.text = '';
      return;
    }
    _usernameController.text = base;
    if (_emailController.text.isEmpty ||
        _emailController.text.contains('@teacher.edu') ||
        _emailController.text.contains('@student.edu') ||
        _emailController.text.contains('@students.edu')) {
      _emailController.text = base.toLowerCase();
    }
    _syncDefaultPassword(base);

    // Query existing accounts in database to resolve overlapping usernames
    try {
      final namePart = base.split('@').first;
      List<String> existing = [];
      try {
        final rpcMatches = await Supabase.instance.client.rpc(
          'get_matching_usernames',
          params: {'p_prefix': namePart},
        );
        if (rpcMatches is List) {
          existing = rpcMatches
              .map((r) => (r is Map ? r['username'] : r) as String? ?? '')
              .where((u) => u.isNotEmpty)
              .toList();
        }
      } catch (_) {
        try {
          final rows = await Supabase.instance.client
              .from('users')
              .select('username')
              .ilike('username', '$namePart%');
          existing = (rows as List)
              .map((r) => r['username'] as String? ?? '')
              .where((u) => u.isNotEmpty)
              .toList();
        } catch (_) {}
      }

      final resolved = nextRoleUsername(
        fullName: _nameController.text,
        role: _requestedRole,
        existingUsernames: existing,
      );
      if (mounted && _nameController.text.trim().isNotEmpty) {
        _usernameController.text = resolved;
        if (_emailController.text.isEmpty ||
            _emailController.text.contains('@teacher.edu') ||
            _emailController.text.contains('@student.edu') ||
            _emailController.text.contains('@students.edu')) {
          _emailController.text = resolved.toLowerCase();
        }
        _syncDefaultPassword(resolved);
      }
    } catch (_) {
      // Keep base if network query fails
    }
  }

  void _syncDefaultPassword(String uname) {
    if (_isRegistering && uname.isNotEmpty) {
      final currentPw = _passwordController.text;
      final shouldUpdatePw = currentPw.isEmpty ||
          currentPw.endsWith('@S.edu') ||
          currentPw.endsWith('@T.edu') ||
          currentPw.endsWith('@A.edu');
      if (shouldUpdatePw) {
        final defaultPw = defaultRolePassword(
          usernameOrFullName: uname,
          role: _requestedRole,
        );
        _passwordController.text = defaultPw;
        _confirmController.text = defaultPw;
      }
    }
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.isDark,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? const Color(0xFF1E293B) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected
                    ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                    : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 13,
                  color: selected
                      ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                      : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = isError ? colors.errorContainer : colors.primaryContainer;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: isError ? colors.onErrorContainer : colors.onPrimaryContainer,
          fontSize: 13,
        ),
      ),
    );
  }
}
