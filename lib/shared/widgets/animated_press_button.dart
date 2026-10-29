import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A widget that adds a smooth, tactile spring bounce animation when pressed.
/// Perfect for buttons, cards, action icons, and interactive elements.
class AnimatedPressButton extends StatefulWidget {
  const AnimatedPressButton({
    required this.child,
    this.onTap,
    this.scaleDown = 0.95,
    this.duration = const Duration(milliseconds: 100),
    this.reverseDuration = const Duration(milliseconds: 140),
    this.enableHaptic = true,
    this.cursor = SystemMouseCursors.click,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;
  final Duration duration;
  final Duration reverseDuration;
  final bool enableHaptic;
  final MouseCursor cursor;

  @override
  State<AnimatedPressButton> createState() => _AnimatedPressButtonState();
}

class _AnimatedPressButtonState extends State<AnimatedPressButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      reverseDuration: widget.reverseDuration,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.scaleDown,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
        reverseCurve: Curves.easeOutBack,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onTap == null) return;
    if (widget.enableHaptic) {
      HapticFeedback.selectionClick();
    }
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.onTap == null) return;
    _controller.reverse();
    widget.onTap!();
  }

  void _onTapCancel() {
    if (widget.onTap == null) return;
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null ? widget.cursor : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: widget.child,
        ),
      ),
    );
  }
}

/// An animated primary action button with built-in bounce physics, gradient,
/// loading spinner, and icon support.
class AppAnimatedButton extends StatefulWidget {
  const AppAnimatedButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.backgroundColor,
    this.foregroundColor,
    this.gradient,
    this.height = 52,
    this.width,
    this.borderRadius = 16,
    this.elevation = 4,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool isLoading;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Gradient? gradient;
  final double height;
  final double? width;
  final double borderRadius;
  final double elevation;

  @override
  State<AppAnimatedButton> createState() => _AppAnimatedButtonState();
}

class _AppAnimatedButtonState extends State<AppAnimatedButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 140),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(
        parent: _pressController,
        curve: Curves.easeInOut,
        reverseCurve: Curves.easeOutBack,
      ),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = widget.onPressed != null && !widget.isLoading;
    final primaryColor = widget.backgroundColor ?? theme.colorScheme.primary;
    final textColor = widget.foregroundColor ?? Colors.white;

    final defaultGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        primaryColor,
        primaryColor.withValues(alpha: 0.85),
      ],
    );

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: enabled
            ? (_) {
                HapticFeedback.lightImpact();
                _pressController.forward();
              }
            : null,
        onTapUp: enabled
            ? (_) {
                _pressController.reverse();
                widget.onPressed?.call();
              }
            : null,
        onTapCancel: enabled ? () => _pressController.reverse() : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            gradient: enabled ? (widget.gradient ?? defaultGradient) : null,
            color: enabled ? null : theme.disabledColor.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: enabled && widget.elevation > 0
                ? [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.28),
                      blurRadius: widget.elevation * 2.5,
                      offset: Offset(0, widget.elevation),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: widget.isLoading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(textColor),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.icon != null) ...[
                      widget.icon!,
                      const SizedBox(width: 8),
                    ],
                    Text(
                      widget.label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: enabled
                            ? textColor
                            : theme.colorScheme.onSurface.withValues(alpha: 0.38),
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
