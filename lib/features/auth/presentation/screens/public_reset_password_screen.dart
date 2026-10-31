import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/services/auth_service.dart';
import 'package:quiz_app/core/utils/validators.dart';
import 'package:quiz_app/shared/widgets/animated_press_button.dart';

class PublicResetPasswordScreen extends ConsumerStatefulWidget {
  const PublicResetPasswordScreen({super.key});

  @override
  ConsumerState<PublicResetPasswordScreen> createState() =>
      _PublicResetPasswordScreenState();
}

class _PublicResetPasswordScreenState
    extends ConsumerState<PublicResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isSendingOtp = false;
  bool _isResetting = false;
  bool _otpSent = false;
  String _targetEmail = '';
  String? _errorMessage;
  String? _successMessage;

  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  void _checkExistingSession() {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      // User arrived from a recovery link with active recovery token
      final userEmail = session.user.email ?? '';
      if (userEmail.isNotEmpty) {
        setState(() {
          _otpSent = true;
          _targetEmail = userEmail;
        });
      }
    }
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final input = _identifierController.text.trim();
    if (input.isEmpty) {
      setState(() => _errorMessage = 'Please enter your username, email, or phone number.');
      return;
    }

    setState(() {
      _isSendingOtp = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final email = await AuthService().sendPasswordReset(input);
      if (mounted) {
        setState(() {
          _isSendingOtp = false;
          _otpSent = true;
          _targetEmail = email;
          _successMessage = 'A 6-digit verification code has been dispatched to $email. Please check your inbox!';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSendingOtp = false;
          _errorMessage = 'Could not send verification code: $e';
        });
      }
    }
  }

  Future<void> _submitReset() async {
    if (!_formKey.currentState!.validate()) return;

    final token = _otpController.text.trim();
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (newPassword != confirmPassword) {
      setState(() => _errorMessage = 'Passwords do not match.');
      return;
    }

    setState(() {
      _isResetting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null && token.isEmpty) {
        // Direct password change for web recovery link session
        await AuthService().updatePassword(newPassword);
      } else {
        if (token.length < 6) {
          setState(() {
            _isResetting = false;
            _errorMessage = 'Please enter the complete 6-digit OTP code.';
          });
          return;
        }
        await AuthService().verifyRecoveryOtpAndSetPassword(
          email: _targetEmail.isNotEmpty ? _targetEmail : _identifierController.text.trim(),
          token: token,
          newPassword: newPassword,
        );
      }

      if (mounted) {
        setState(() {
          _isResetting = false;
          _successMessage = 'Password updated successfully! Any previous account lockout has been cleared.';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password updated successfully! Please sign in.'),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );

        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) context.go('/login');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isResetting = false;
          _errorMessage = 'Password reset failed: $e. Please verify your OTP code.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Password Reset Portal'),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header & Icon
                      Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.lock_reset_rounded,
                            color: Color(0xFF10B981),
                            size: 34,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Ciro High School Account Recovery',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _otpSent
                            ? 'Enter the 6-digit OTP code sent to your registered email and specify your new password.'
                            : 'Enter your institutional username or email to receive a secure 6-digit password reset code.',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),

                      // Success Banner
                      if (_successMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF10B981), size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _successMessage!,
                                  style: const TextStyle(color: Color(0xFF047857), fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Error Banner
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Input 1: Identifier
                      if (!_otpSent) ...[
                        TextFormField(
                          controller: _identifierController,
                          decoration: const InputDecoration(
                            labelText: 'Institutional Email or Username',
                            hintText: 'e.g. SultanAdinan@Admin.edu or wondetech404@gmail.com',
                            prefixIcon: Icon(Icons.account_circle_outlined),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Enter your email or username' : null,
                        ),
                        const SizedBox(height: 20),
                        AnimatedPressButton(
                          onTap: _isSendingOtp ? null : _sendOtp,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _isSendingOtp ? null : _sendOtp,
                            icon: _isSendingOtp
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.send_rounded, size: 18),
                            label: Text(_isSendingOtp ? 'Sending OTP...' : 'Send 6-Digit Reset Code'),
                          ),
                        ),
                      ] else ...[
                        // Step 2: OTP code & New Password
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF10B981).withValues(alpha: 0.5),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'ENTER 6-DIGIT CODE SENT TO $_targetEmail',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _otpController,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 10,
                                ),
                                decoration: const InputDecoration(
                                  hintText: '••••••',
                                  counterText: '',
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  prefixIcon: Icon(Icons.pin_outlined, color: Color(0xFF10B981)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        TextFormField(
                          controller: _newPasswordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'New Password',
                            hintText: 'At least 8 characters',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: Validators.password,
                        ),
                        const SizedBox(height: 14),

                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirm,
                          decoration: InputDecoration(
                            labelText: 'Confirm New Password',
                            prefixIcon: const Icon(Icons.lock_reset_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                            ),
                          ),
                          validator: (v) => v == null || v.isEmpty ? 'Confirm your password' : null,
                        ),
                        const SizedBox(height: 20),

                        AnimatedPressButton(
                          onTap: _isResetting ? null : _submitReset,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _isResetting ? null : _submitReset,
                            icon: _isResetting
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.check_circle_outline_rounded, size: 18),
                            label: Text(_isResetting ? 'Updating Password...' : 'Save Password & Unlock Account'),
                          ),
                        ),
                        const SizedBox(height: 8),

                        Center(
                          child: TextButton.icon(
                            onPressed: _isSendingOtp ? null : _sendOtp,
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Resend Code'),
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),
                      Center(
                        child: TextButton.icon(
                          onPressed: () => context.go('/login'),
                          icon: const Icon(Icons.arrow_back_rounded, size: 16),
                          label: const Text('Back to Login'),
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
    );
  }
}
