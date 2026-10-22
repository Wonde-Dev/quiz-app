import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quiz_app/core/services/security/app_lifecycle_service.dart';
import 'package:quiz_app/core/services/security/screenshot_service.dart';

/// Wraps a quiz screen with active screen capture and lifecycle protection.
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
  final _screenshotService = ScreenshotService();
  int _lifecycleWarnings = 0;
  int _screenshotWarnings = 0;
  bool _isScreenRecordingActive = false;

  @override
  void initState() {
    super.initState();
    _lifecycleService.startMonitoring(
      onWarning: () => setState(() => _lifecycleWarnings++),
      onAutoSubmit: () => widget.onAutoSubmit?.call(),
    );
    unawaited(_enableScreenProtection());
  }

  Future<void> _enableScreenProtection() async {
    await _screenshotService.enableProtection(
      onScreenshotDetected: (event) {
        if (!mounted) return;
        setState(() => _screenshotWarnings++);
        widget.onScreenshotLog?.call(event);
      },
      onRecordingChanged: (isRecording) {
        if (!mounted) return;
        setState(() => _isScreenRecordingActive = isRecording);
      },
    );
  }

  @override
  void dispose() {
    _lifecycleService.stopMonitoring();
    unawaited(_screenshotService.disableProtection());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. If screen recording is actively detected, block view with impenetrable privacy shield
    if (_isScreenRecordingActive) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.videocam_off_rounded,
                    size: 72,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Screen Recording Detected',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Screen recording is strictly prohibited during exams to protect examination integrity.\n\n'
                    'Please stop your screen recording software or control center recording to resume your test.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      setState(() {
                        _isScreenRecordingActive =
                            _screenshotService.isScreenRecording;
                      });
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('I Stopped Recording'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 2. Lifecycle backgrounding warning dialog
    if (_lifecycleWarnings > 0) {
      return AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, size: 40, color: Colors.amber),
        title: const Text('Security Alert'),
        content: Text(
          'You left the quiz application. Warning $_lifecycleWarnings of 2.\n\n'
          'Navigating away from the quiz is logged and shared with your instructor.',
        ),
        actions: [
          FilledButton(
            onPressed: () => setState(() => _lifecycleWarnings = 0),
            child: const Text('Return to Quiz'),
          ),
        ],
      );
    }

    // 3. Screenshot warning dialog
    if (_screenshotWarnings > 0) {
      return AlertDialog(
        icon: const Icon(Icons.no_photography_rounded, size: 40, color: Colors.red),
        title: const Text('Screenshots Prohibited'),
        content: Text(
          'A screenshot capture attempt was detected and blocked. (Incident $_screenshotWarnings)\n\n'
          'Taking screenshots during an examination is forbidden. This incident has been recorded on your exam log.',
        ),
        actions: [
          FilledButton(
            onPressed: () => setState(() => _screenshotWarnings = 0),
            child: const Text('Acknowledge and Continue'),
          ),
        ],
      );
    }

    return widget.child;
  }
}
