import 'package:flutter/material.dart';

class DashboardWelcomeBanner extends StatefulWidget {
  const DashboardWelcomeBanner({
    required this.subtitle,
    this.title = 'High School Quiz App',
    this.badgeText = 'ACADEMIC PORTAL',
    this.action,
    super.key,
  });

  final String title;
  final String subtitle;
  final String badgeText;
  final Widget? action;

  @override
  State<DashboardWelcomeBanner> createState() => _DashboardWelcomeBannerState();
}

class _DashboardWelcomeBannerState extends State<DashboardWelcomeBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = Curves.easeInOut.transform(_controller.value);
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF334155)
                  : const Color(0xFF10B981).withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10B981).withValues(alpha: 0.18),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.4)
                    : const Color(0xFF0F172A).withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // 1. Home Illustration Backdrop
              Positioned.fill(
                child: Image.asset(
                  'assets/images/home.jpeg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFF064E3B),
                  ),
                ),
              ),

              // 2. High-Contrast Gradient Tint Overlay
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              const Color(0xF2064E3B),
                              const Color(0xF50F172A),
                              const Color(0xF0022C22),
                            ]
                          : [
                              const Color(0xEE064E3B),
                              const Color(0xE80F172A),
                              const Color(0xDB047857),
                            ],
                    ),
                  ),
                ),
              ),

              // 3. Subtle Animated Ambient Glow Orbs
              Positioned(
                right: -20 + (progress * 24),
                top: -50,
                child: _BannerGlow(
                  size: 220,
                  color: const Color(0x3010B981),
                ),
              ),
              Positioned(
                left: 40 - (progress * 20),
                bottom: -80,
                child: _BannerGlow(
                  size: 200,
                  color: const Color(0x2538BDF8),
                ),
              ),

              // 4. Banner Content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Academic Portal Pill Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF34D399),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0xFF34D399),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  widget.badgeText,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.0,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Heading
                          Text(
                            widget.title,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                              height: 1.15,
                              shadows: const [
                                Shadow(
                                  color: Color(0x80000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Subtitle
                          Text(
                            widget.subtitle,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFFE2E8F0),
                              fontWeight: FontWeight.w400,
                              height: 1.4,
                              shadows: const [
                                Shadow(
                                  color: Color(0x60000000),
                                  blurRadius: 6,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),

                          if (widget.action != null) ...[
                            const SizedBox(height: 14),
                            widget.action!,
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Branded School Emblem Container
                    Transform.translate(
                      offset: Offset(0, (progress - 0.5) * 8),
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: const Color(0xFF10B981).withValues(alpha: 0.4),
                            width: 2.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.35),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                            const BoxShadow(
                              color: Color(0x20000000),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.school_rounded,
                              color: Color(0xFF10B981),
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BannerGlow extends StatelessWidget {
  const _BannerGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}
