import 'package:flutter/material.dart';
import 'package:quiz_app/core/services/security/app_lifecycle_service.dart';

/// Wraps a quiz screen with lifecycle monitoring. Capture protection is global.
class SecureScreenWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback? onAutoSubmit;
  final void Function(String)? onScreenshotLog;

  const SecureScreenWrapper({
    super.key,
    required this.child,
    this.onAutoSubmit,
    this.onScreenshotLog,
  });

  @override
  State<SecureScreenWrapper> createState() => _SecureScreenWrapperState();
}

class _SecureScreenWrapperState extends State<SecureScreenWrapper> {
  final _lifecycleService = AppLifecycleService();
  int _warnings = 0;

  @override
  void initState() {
    super.initState();
    _lifecycleService.startMonitoring(
      onWarning: () => setState(() => _warnings++),
      onAutoSubmit: () => widget.onAutoSubmit?.call(),
    );
  }

  @override
  void dispose() {
    _lifecycleService.stopMonitoring();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_warnings > 0) {
      return AlertDialog(
        title: const Text('Warning'),
        content: Text(
          'You left the quiz screen. Warning $_warnings of 2.\n'
          'This activity has been logged and reported to your teacher.',
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() => _warnings = 0),
            child: const Text('Return to Quiz'),
          ),
        ],
      );
    }
    return widget.child;
  }
}
