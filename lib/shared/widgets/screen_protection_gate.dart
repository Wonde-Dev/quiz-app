import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quiz_app/core/services/security/screenshot_service.dart';

class ScreenProtectionGate extends StatefulWidget {
  const ScreenProtectionGate({required this.child, super.key});

  final Widget child;

  @override
  State<ScreenProtectionGate> createState() => _ScreenProtectionGateState();
}

class _ScreenProtectionGateState extends State<ScreenProtectionGate> {
  final _service = ScreenshotService();
  late Future<void> _protection;

  @override
  void initState() {
    super.initState();
    _protection = _enableProtection();
  }

  Future<void> _enableProtection() => _service.enableProtection(
    onScreenshotDetected: (event) {
      debugPrint('Screen capture blocked or detected: $event');
    },
  );

  @override
  void dispose() {
    unawaited(_service.disableProtection());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _protection,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Screen protection could not be enabled. '
                    'The app is unavailable to protect your account and quiz data.\n\n'
                    '${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }
        return widget.child;
      },
    );
  }
}
