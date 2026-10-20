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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = Curves.easeInOut.transform(_controller.value);
        return Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.lerp(
                Alignment.topLeft,
                Alignment.bottomLeft,
                progress * 0.35,
              )!,
              end: Alignment.lerp(
                Alignment.bottomRight,
                Alignment.topRight,
                progress * 0.35,
              )!,
              colors: const [
                Color(0xFF12345A),
                Color(0xFF16558A),
                Color(0xFF087E8B),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF12345A).withValues(alpha: 0.16),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -28 + (progress * 14),
                top: -76,
                child: _BannerGlow(
                  size: 190,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              Positioned(
                right: 78 - (progress * 14),
                bottom: -100,
                child: _BannerGlow(
                  size: 190,
                  color: const Color(0xFF78E2DF).withValues(alpha: 0.14),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'HIGH SCHOOL\nQUIZ APP',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              height: 1.02,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            widget.subtitle,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.84),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Transform.translate(
                      offset: Offset(0, (progress - 0.5) * 10),
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(21),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: const Icon(
                          Icons.auto_stories_rounded,
                          color: Color(0xFFB9F2EA),
                          size: 34,
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
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}
