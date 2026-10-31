import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/services/auth_service.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/shared/widgets/animated_press_button.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class AccountStatusScreen extends ConsumerStatefulWidget {
  const AccountStatusScreen({super.key});

  @override
  ConsumerState<AccountStatusScreen> createState() => _AccountStatusScreenState();
}

class _AccountStatusScreenState extends ConsumerState<AccountStatusScreen>
    with SingleTickerProviderStateMixin {
  bool _isChecking = false;
  bool _isSendingOtp = false;
  late final AnimationController _pulseController;
  RealtimeChannel? _userRealtimeChannel;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _setupRealtime();
  }

  void _setupRealtime() {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    try {
      _userRealtimeChannel = Supabase.instance.client
          .channel('public:user_status_${user.id}')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'users',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: user.id,
            ),
            callback: (payload) {
              if (mounted) {
                _checkStatus(silent: true);
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Realtime channel notice: $e');
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    if (_userRealtimeChannel != null) {
      Supabase.instance.client.removeChannel(_userRealtimeChannel!);
    }
    super.dispose();
  }

  Future<void> _checkStatus({bool silent = false}) async {
    final currentUser = ref.read(authStateProvider).user;
    if (currentUser == null) return;

    if (!silent) setState(() => _isChecking = true);

    try {
      final updatedUser = await AuthService().getAppUser(currentUser.id);
      if (updatedUser != null && mounted) {
        ref.read(authStateProvider.notifier).setUser(updatedUser);

        if (!updatedUser.isPendingApproval && !updatedUser.isRejected && updatedUser.isActive) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Account Approved! Welcome to Ciro High School, ${updatedUser.fullName ?? updatedUser.username}!',
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
            ),
          );

          // Route to active role dashboard
          final targetRoute = switch (updatedUser.role) {
            AppRoles.admin => '/admin/dashboard',
            AppRoles.subadmin || AppRoles.director || 'director' => '/director/dashboard',
            AppRoles.teacher => '/teacher/dashboard',
            _ => '/student/dashboard',
          };
          context.go(targetRoute);
          return;
        } else if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                updatedUser.isRejected
                    ? 'Your application was declined. Please contact your school administrator.'
                    : 'Application is still under review by school administration.',
              ),
              backgroundColor: updatedUser.isRejected ? Colors.red.shade700 : const Color(0xFFD97706),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not refresh status: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (!silent && mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  Future<void> _resendVerificationOtp() async {
    final user = ref.read(authStateProvider).user;
    final targetEmail = user?.email;
    if (targetEmail == null || targetEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No email address registered for this account.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSendingOtp = true);

    try {
      await AuthService().sendLoginOtp(targetEmail);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification OTP code dispatched to $targetEmail. Please check your inbox!'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not send OTP: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingOtp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = ref.watch(authStateProvider).user;

    final isPending = user?.isPendingApproval ?? true;
    final isRejected = user?.isRejected ?? false;
    final isDeactivated = !(user?.isActive ?? true);

    final requestedRole = user?.requestedRole ?? user?.role ?? 'student';
    final roleTitle = switch (requestedRole) {
      'teacher' => 'Faculty Teacher',
      'subadmin' || 'director' => 'School Director',
      'admin' => 'Administrator',
      _ => 'Student',
    };

    final reviewerTitle = switch (requestedRole) {
      'teacher' => 'School Director / Main Administrator',
      'subadmin' || 'director' => 'Super Administrator',
      'admin' => 'Super Administrator',
      _ => 'Designated Attendance Teacher (${user?.attendanceClass ?? user?.assignedClass ?? "Homeroom"})',
    };

    final statusColor = isPending
        ? const Color(0xFFF59E0B)
        : (isRejected || isDeactivated ? const Color(0xFFEF4444) : const Color(0xFF10B981));

    return DashboardShell(
      title: 'Institutional Status',
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.12),
                    blurRadius: 32,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Institutional Branding Pill
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.school_rounded, color: Color(0xFF10B981), size: 16),
                          SizedBox(width: 8),
                          Text(
                            'Ciro High School · Registration Portal',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF047857),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Pulsing Status Icon
                  Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (isPending)
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, _) {
                              return Container(
                                width: 80 + (_pulseController.value * 12),
                                height: 80 + (_pulseController.value * 12),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: statusColor.withValues(
                                    alpha: 0.18 - (_pulseController.value * 0.1),
                                  ),
                                ),
                              );
                            },
                          ),
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(color: statusColor.withValues(alpha: 0.4), width: 2),
                          ),
                          child: Icon(
                            isPending
                                ? Icons.hourglass_top_rounded
                                : (isRejected || isDeactivated
                                    ? Icons.cancel_outlined
                                    : Icons.check_circle_rounded),
                            size: 36,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Title and Subtitle
                  Text(
                    isPending
                        ? 'Waiting for Official Approval'
                        : (isRejected
                            ? 'Application Declined'
                            : (isDeactivated ? 'Account Deactivated' : 'Account Active')),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isPending
                        ? 'Your registration for $roleTitle at Ciro High School has been securely submitted and is awaiting administrator verification.'
                        : (isRejected
                            ? 'Your application for $roleTitle privileges was not approved. Please contact your school administrator for assistance.'
                            : 'This account is currently deactivated. Please reach out to school administration to restore access.'),
                    style: TextStyle(
                      fontSize: 13.5,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      height: 1.45,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Details Card
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildDetailRow(
                          icon: Icons.person_outline_rounded,
                          label: 'Full Name',
                          value: user?.fullName?.isNotEmpty == true ? user!.fullName! : 'Pending',
                          isDark: isDark,
                        ),
                        const Divider(height: 18),
                        _buildDetailRow(
                          icon: Icons.badge_outlined,
                          label: 'Username',
                          value: user?.username ?? 'Assigned on approval',
                          isDark: isDark,
                        ),
                        const Divider(height: 18),
                        _buildDetailRow(
                          icon: Icons.assignment_ind_outlined,
                          label: 'Role Requested',
                          value: roleTitle,
                          isDark: isDark,
                          highlightColor: statusColor,
                        ),
                        if (user?.assignedClass != null || user?.attendanceClass != null) ...[
                          const Divider(height: 18),
                          _buildDetailRow(
                            icon: Icons.meeting_room_outlined,
                            label: 'Assigned Class',
                            value: user?.assignedClass ?? user?.attendanceClass ?? '',
                            isDark: isDark,
                          ),
                        ],
                        const Divider(height: 18),
                        _buildDetailRow(
                          icon: Icons.verified_user_outlined,
                          label: 'Reviewing Authority',
                          value: reviewerTitle,
                          isDark: isDark,
                        ),
                        if (user != null && user.email.isNotEmpty) ...[
                          const Divider(height: 18),
                          _buildDetailRow(
                            icon: Icons.alternate_email_rounded,
                            label: 'Notification Email',
                            value: user.email,
                            isDark: isDark,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Email Notification & OTP Advisory
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.mark_email_read_outlined, color: Color(0xFF2563EB), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Email & OTP Notice: Once approved, you will receive an official notification and login verification OTP directly to your email address.',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Responsive Action Buttons
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      // 1. Check Approval Status
                      AnimatedPressButton(
                        onTap: _isChecking ? null : () => _checkStatus(),
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _isChecking ? null : () => _checkStatus(),
                          icon: _isChecking
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(_isChecking ? 'Checking...' : 'Check Approval Status'),
                        ),
                      ),

                      // 2. Resend Verification OTP
                      if (isPending && user != null && user.email.isNotEmpty)
                        AnimatedPressButton(
                          onTap: _isSendingOtp ? null : _resendVerificationOtp,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
                              side: BorderSide(
                                color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _isSendingOtp ? null : _resendVerificationOtp,
                            icon: _isSendingOtp
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.send_rounded, size: 16),
                            label: Text(_isSendingOtp ? 'Sending OTP...' : 'Resend Verification OTP'),
                          ),
                        ),

                      // 3. Sign Out
                      AnimatedPressButton(
                        onTap: () => ref.read(authStateProvider.notifier).signOut(),
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF64748B),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                          onPressed: () => ref.read(authStateProvider.notifier).signOut(),
                          icon: const Icon(Icons.logout_rounded, size: 18),
                          label: const Text('Sign out'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
    Color? highlightColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF64748B)),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: highlightColor ?? (isDark ? Colors.white : const Color(0xFF0F172A)),
          ),
        ),
      ],
    );
  }
}
