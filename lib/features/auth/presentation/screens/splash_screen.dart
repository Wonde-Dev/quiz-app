import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/services/onboarding_service.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _pulseController;

  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // 1. Entrance animation (scale, fade, slide)
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.75, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.85, curve: Curves.easeOutBack),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.2, 0.95, curve: Curves.easeOutCubic),
      ),
    );

    // 2. Continuous ambient pulse animation for the emerald glow halo
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.96, end: 1.08).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    _entranceController.forward();
    _handleRouting();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// Always displays the splash animation, then routes conditionally:
  /// - If user is logged in -> their role's dashboard.
  /// - If user is not logged in:
  ///     - If first launch (has not completed onboarding) -> /onboarding
  ///     - If returning user (already completed onboarding) -> /login
  Future<void> _handleRouting() async {
    await Future.delayed(const Duration(milliseconds: 2300));
    if (!mounted) return;

    final authState = ref.read(authStateProvider);
    final user = authState.user;

    // Check onboarding completion status from persistent storage
    final hasCompletedOnboarding =
        await OnboardingService.hasCompletedOnboarding();
    if (!mounted) return;

    // If active logged-in session exists
    if (user != null && !authState.isPendingApproval && !authState.isRejected) {
      if (authState.needsPasswordChange) {
        context.go('/change-password');
        return;
      }

      switch (user.role) {
        case AppRoles.admin:
          context.go('/admin/dashboard');
          return;
        case AppRoles.teacher:
          context.go('/teacher/dashboard');
          return;
        case AppRoles.student:
          context.go('/student/dashboard');
          return;
        default:
          break;
      }
    }

    // Unauthenticated user:
    // First time ever: show onboarding.
    // Every subsequent app open: skip straight to login!
    if (!hasCompletedOnboarding) {
      context.go('/onboarding');
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Premium Emerald & Pure White Palette
    const emeraldPrimary = Color(0xFF10B981);
    const emeraldDark = Color(0xFF047857);
    const emeraldMint = Color(0xFFECFDF5);
    const slateDark = Color(0xFF064E3B);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1E17) : Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Ambient Background White-Green Gradient
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [
                          const Color(0xFF0A1E17),
                          const Color(0xFF0F172A),
                          const Color(0xFF061A14),
                        ]
                      : [
                          const Color(0xFFF0FDF4),
                          Colors.white,
                          const Color(0xFFF7FEE7).withValues(alpha: 0.6),
                        ],
                ),
              ),
            ),
          ),

          // 2. Subtle decorative image backdrop (home.jpeg) with delicate low opacity
          Positioned.fill(
            child: Opacity(
              opacity: isDark ? 0.08 : 0.04,
              child: Image.asset(
                'assets/images/home.jpeg',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),

          // 3. Ambient Emerald Glow Orbs
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: emeraldPrimary.withValues(alpha: isDark ? 0.12 : 0.15),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -80,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: emeraldDark.withValues(alpha: isDark ? 0.10 : 0.12),
              ),
            ),
          ),

          // 4. Central Content with Animations
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Animated Breathing Halo & Circular Emblem
                        AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _pulseAnimation.value,
                              child: child,
                            );
                          },
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Pulsing outer aura ring
                              Container(
                                width: 156,
                                height: 156,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: emeraldPrimary.withValues(alpha: 0.25),
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: emeraldPrimary.withValues(alpha: 0.22),
                                      blurRadius: 40,
                                      spreadRadius: 8,
                                    ),
                                  ],
                                ),
                              ),

                              // Inner Emblem Container
                              Container(
                                width: 132,
                                height: 132,
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isDark ? const Color(0xFF132A22) : Colors.white,
                                  border: Border.all(
                                    color: emeraldPrimary,
                                    width: 2.8,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: emeraldPrimary.withValues(alpha: 0.35),
                                      blurRadius: 28,
                                      offset: const Offset(0, 10),
                                    ),
                                    BoxShadow(
                                      color: isDark
                                          ? Colors.black.withValues(alpha: 0.5)
                                          : const Color(0xFF0F172A).withValues(alpha: 0.08),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child: Image.asset(
                                    'assets/images/logo.png',
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Icon(
                                      Icons.school_rounded,
                                      size: 64,
                                      color: emeraldPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // System Category Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? emeraldPrimary.withValues(alpha: 0.15)
                                : emeraldMint,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: emeraldPrimary.withValues(alpha: 0.4),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: emeraldPrimary.withValues(alpha: 0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.auto_awesome_rounded,
                                size: 15,
                                color: emeraldPrimary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'CIRO HIGH SCHOOLS ACADEMY',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.6,
                                  color: isDark ? const Color(0xFF6EE7B7) : emeraldDark,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),

                        // Main Title with White & Emerald Green Contrast
                        RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                              fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                            ),
                            children: [
                              TextSpan(
                                text: 'Quiz',
                                style: TextStyle(
                                  color: isDark ? Colors.white : slateDark,
                                ),
                              ),
                              const TextSpan(
                                text: 'App',
                                style: TextStyle(
                                  color: emeraldPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 10),

                        // App Tagline
                        Text(
                          'Next-Gen Academic Assessment & Resource Hub',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: isDark ? const Color(0xFFD1FAE5) : emeraldDark,
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Comprehensive App Description
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Text(
                            'A unified platform connecting students and teachers. Take anti-cheat proctored quizzes, download grade-level worksheets, and track real-time academic progress.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF475569),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Feature Highlights Pills
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            _buildFeaturePill(
                              icon: Icons.shield_outlined,
                              label: 'Anti-Cheat Shield',
                              isDark: isDark,
                            ),
                            _buildFeaturePill(
                              icon: Icons.description_outlined,
                              label: 'Grade 9–12 PDFs',
                              isDark: isDark,
                            ),
                            _buildFeaturePill(
                              icon: Icons.insights_rounded,
                              label: 'Instant Scoring',
                              isDark: isDark,
                            ),
                          ],
                        ),

                        const SizedBox(height: 44),

                        // Modern Loading Pill with Emerald Bar
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF132A22) : Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: emeraldPrimary.withValues(alpha: 0.25),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: emeraldPrimary.withValues(alpha: 0.12),
                                blurRadius: 18,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(emeraldPrimary),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Entering Campus Environment...',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? const Color(0xFFD1FAE5)
                                      : const Color(0xFF065F46),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturePill({
    required IconData icon,
    required String label,
    required bool isDark,
  }) {
    const emeraldPrimary = Color(0xFF10B981);
    const emeraldMint = Color(0xFFECFDF5);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132A22) : emeraldMint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: emeraldPrimary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: emeraldPrimary),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF047857),
            ),
          ),
        ],
      ),
    );
  }
}
