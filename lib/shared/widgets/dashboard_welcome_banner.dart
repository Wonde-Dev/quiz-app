import 'package:flutter/material.dart';

class DashboardWelcomeBanner extends StatefulWidget {
  const DashboardWelcomeBanner({required this.subtitle, super.key});

  final String subtitle;

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
                color: isDark
                    ? Colors.black.withValues(alpha: 0.3)
                    : const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Animated subtle pastel ambient orbs
              Positioned(
                right: -20 + (progress * 18),
                top: -50,
                child: _BannerGlow(
                  size: 210,
                  color: isDark
                      ? const Color(0x2038BDF8)
                      : const Color(0x1F6366F1),
                ),
              ),
              Positioned(
                left: 40 - (progress * 20),
                bottom: -80,
                child: _BannerGlow(
                  size: 200,
                  color: isDark
                      ? const Color(0x2034D399)
                      : const Color(0x1E10B981),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF475569)
                                    : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'ACADEMIC PORTAL',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'High School Quiz App',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.subtitle,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Transform.translate(
                      offset: Offset(0, (progress - 0.5) * 8),
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF0F172A)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF475569)
                                : const Color(0xFFE2E8F0),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.school_rounded,
                              color: Color(0xFF10B981),
                              size: 30,
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
