import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/core/services/onboarding_service.dart';
import 'package:quiz_app/core/theme/theme_mode_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<({
    String badge,
    String title,
    String description,
    List<String> highlights,
    String image,
    IconData icon,
  })> _slides = const [
    (
      badge: 'DIGITAL CAMPUS',
      title: 'All-in-One High School Examination Hub',
      description:
          'Welcome to QuizApp! The official academic testing platform connecting students, teachers, and administrators. Seamlessly create, distribute, and complete exams with instant scoring and centralized school management.',
      highlights: ['Dynamic Quizzes', 'Centralized Portal', 'Official Curriculum'],
      image: 'assets/images/home.jpeg',
      icon: Icons.school_rounded,
    ),
    (
      badge: 'EXAM INTEGRITY',
      title: 'State-of-the-Art Anti-Cheat Protection',
      description:
          'Study hard and earn what you truly deserve. Our robust security system actively shields exams with screenshot prevention, clipboard locking, and background app-switch monitoring for total academic fairness.',
      highlights: ['Screenshot Shield', 'Clipboard Guard', 'Live Integrity Tracking'],
      image: 'assets/images/exam_prep.jpeg',
      icon: Icons.security_rounded,
    ),
    (
      badge: 'CURATED LEARNING',
      title: 'Grade & Section Tailored Worksheets',
      description:
          'Access learning materials tailored for your exact classes. Teachers upload authentic model exams, revision guides, and practice worksheets categorized directly by Grades 9 through 12 and Section A through F.',
      highlights: ['PDF Downloads', 'Grades 9–12 Filter', 'Section Archives'],
      image: 'assets/images/classroom.jpeg',
      icon: Icons.menu_book_rounded,
    ),
    (
      badge: 'ACADEMIC GROWTH',
      title: 'Instant Evaluation & Performance Insights',
      description:
          'No more waiting days for quiz results. Submit your answers to receive instant question-by-question grading, complete review explanations, subject mastery trends, and actionable insights to accelerate your GPA.',
      highlights: ['Instant Scoring', 'Detailed Solutions', 'Growth Analytics'],
      image: 'assets/images/diploma.jpeg',
      icon: Icons.workspace_premium_rounded,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Mark onboarding as completed so returning users skip directly to login.
  Future<void> _completeAndNavigate() async {
    await OnboardingService.markOnboardingCompleted();
    if (mounted) {
      context.go('/login');
    }
  }

  void _onNext() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _completeAndNavigate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height && size.width > 760;

    // Premium Emerald & Pure White Color System
    const emeraldPrimary = Color(0xFF10B981);
    const emeraldDark = Color(0xFF047857);
    const emeraldMint = Color(0xFFECFDF5);
    const slateDark = Color(0xFF064E3B);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1E17) : Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            // Logo emblem
            Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? const Color(0xFF132A22) : Colors.white,
                border: Border.all(color: emeraldPrimary, width: 1.8),
                boxShadow: [
                  BoxShadow(
                    color: emeraldPrimary.withValues(alpha: 0.25),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.school_rounded,
                    color: emeraldPrimary,
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  fontFamily: theme.textTheme.bodyMedium?.fontFamily,
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
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isDark ? emeraldPrimary.withValues(alpha: 0.15) : emeraldMint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: emeraldPrimary.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                'Academy',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isDark ? const Color(0xFF6EE7B7) : emeraldDark,
                ),
              ),
            ),
          ],
        ),
        actions: [
          // Theme Switcher Button
          IconButton(
            tooltip: isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme',
            onPressed: () {
              final newMode = isDark ? ThemeMode.light : ThemeMode.dark;
              ref.read(themeModeProvider.notifier).setMode(newMode);
            },
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              size: 20,
              color: isDark ? const Color(0xFFFDE047) : emeraldDark,
            ),
          ),
          const SizedBox(width: 4),

          // Skip Button (Marks completed & goes to login)
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? const Color(0xFFA7F3D0) : emeraldDark,
                side: BorderSide(
                  color: emeraldPrimary.withValues(alpha: 0.4),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: _completeAndNavigate,
              child: const Text(
                'Skip',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: isLandscape
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 5,
                                child: _buildIllustrationCard(
                                  imagePath: slide.image,
                                  badge: slide.badge,
                                  icon: slide.icon,
                                  isDark: isDark,
                                ),
                              ),
                              const SizedBox(width: 36),
                              Expanded(
                                flex: 5,
                                child: _buildSlideContent(
                                  slide: slide,
                                  isDark: isDark,
                                  theme: theme,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 5,
                                child: _buildIllustrationCard(
                                  imagePath: slide.image,
                                  badge: slide.badge,
                                  icon: slide.icon,
                                  isDark: isDark,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Expanded(
                                flex: 5,
                                child: _buildSlideContent(
                                  slide: slide,
                                  isDark: isDark,
                                  theme: theme,
                                ),
                              ),
                            ],
                          ),
                  );
                },
              ),
            ),

            // Bottom Navigation Controls
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0A1E17) : Colors.white,
                border: Border(
                  top: BorderSide(
                    color: emeraldPrimary.withValues(alpha: 0.12),
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Animated Page Pill Indicators
                  Row(
                    children: List.generate(
                      _slides.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 320),
                        margin: const EdgeInsets.only(right: 6),
                        width: _currentPage == index ? 32 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? emeraldPrimary
                              : (isDark
                                  ? const Color(0xFF1E3A30)
                                  : const Color(0xFFD1FAE5)),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: _currentPage == index
                              ? [
                                  BoxShadow(
                                    color: emeraldPrimary.withValues(alpha: 0.4),
                                    blurRadius: 6,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),

                  // Back button (shown on slides > 0)
                  if (_currentPage > 0) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? Colors.white : slateDark,
                        side: BorderSide(
                          color: emeraldPrimary.withValues(alpha: 0.35),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text('Back'),
                    ),
                    const SizedBox(width: 12),
                  ],

                  // Next / Get Started Button with Vibrant Emerald Gradient
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF10B981), Color(0xFF059669)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: emeraldPrimary.withValues(alpha: 0.38),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 13,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _onNext,
                      icon: Icon(
                        _currentPage == _slides.length - 1
                            ? Icons.check_circle_rounded
                            : Icons.arrow_forward_rounded,
                        size: 20,
                      ),
                      label: Text(
                        _currentPage == _slides.length - 1
                            ? 'Get Started'
                            : 'Continue',
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIllustrationCard({
    required String imagePath,
    required String badge,
    required IconData icon,
    required bool isDark,
  }) {
    const emeraldPrimary = Color(0xFF10B981);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: emeraldPrimary.withValues(alpha: 0.35),
          width: 2.2,
        ),
        boxShadow: [
          BoxShadow(
            color: emeraldPrimary.withValues(alpha: 0.22),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.4)
                : const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Image with clean fit
            Image.asset(
              imagePath,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: isDark ? const Color(0xFF132A22) : const Color(0xFFECFDF5),
                child: Icon(icon, size: 72, color: emeraldPrimary),
              ),
            ),

            // Top gradient overlay for contrast
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 70,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.4),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Bottom gradient overlay with subtle emerald touch
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 90,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      isDark
                          ? const Color(0xFF0A1E17).withValues(alpha: 0.85)
                          : const Color(0xFF064E3B).withValues(alpha: 0.75),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Badge floating on top
            Positioned(
              top: 14,
              left: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: emeraldPrimary.withValues(alpha: 0.6),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 15, color: const Color(0xFF047857)),
                    const SizedBox(width: 6),
                    Text(
                      badge,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Color(0xFF047857),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlideContent({
    required ({
      String badge,
      String title,
      String description,
      List<String> highlights,
      String image,
      IconData icon,
    }) slide,
    required bool isDark,
    required ThemeData theme,
  }) {
    const emeraldPrimary = Color(0xFF10B981);
    const emeraldDark = Color(0xFF047857);
    const emeraldMint = Color(0xFFECFDF5);
    const slateDark = Color(0xFF064E3B);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Category tag
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: isDark ? emeraldPrimary.withValues(alpha: 0.15) : emeraldMint,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: emeraldPrimary.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  slide.icon,
                  size: 13,
                  color: isDark ? const Color(0xFF6EE7B7) : emeraldDark,
                ),
                const SizedBox(width: 6),
                Text(
                  slide.badge,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: isDark ? const Color(0xFF6EE7B7) : emeraldDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Slide Title
          Text(
            slide.title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              height: 1.25,
              color: isDark ? Colors.white : slateDark,
            ),
          ),
          const SizedBox(height: 12),

          // Detailed App Description
          Text(
            slide.description,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.55,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 18),

          // Highlights Chips with Emerald Checkmark
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: slide.highlights.map((highlight) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF132A22) : emeraldMint,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: emeraldPrimary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: emeraldPrimary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      highlight,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFFA7F3D0)
                            : const Color(0xFF047857),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
