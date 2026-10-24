import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.75, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.9, curve: Curves.easeOutBack),
      ),
    );

    _animController.forward();
    _navigateToNext();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _navigateToNext() async {
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;

    final authState = ref.read(authStateProvider);
    final user = authState.user;

    if (user == null || authState.isPendingApproval || authState.isRejected) {
      if (mounted) context.go('/login');
      return;
    }

    if (authState.needsPasswordChange) {
      if (mounted) context.go('/change-password');
      return;
    }

    if (mounted) {
      switch (user.role) {
        case AppRoles.admin:
          context.go('/admin/dashboard');
          break;
        case AppRoles.teacher:
          context.go('/teacher/dashboard');
          break;
        case AppRoles.student:
          context.go('/student/dashboard');
          break;
        default:
          context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Branded Logo Container
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.22),
                        blurRadius: 36,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.school_rounded,
                        size: 72,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Title
                Text(
                  'CIRO SCHOOLS QUIZ',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.5,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),

                // Subtitle
                Text(
                  'High School Knowledge & Assessment Portal',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 48),

                // Green Accent Progress Spinner
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
