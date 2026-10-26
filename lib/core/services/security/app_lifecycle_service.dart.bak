import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_fgbg/flutter_fgbg.dart';

/// Monitors app foreground/background transitions to detect cheating.
class AppLifecycleService {
  StreamSubscription? _fgbgSub;
  int _backgroundCount = 0;
  static const maxWarnings = 2;

  /// Start monitoring. Fires [onWarning] then [onAutoSubmit] on each exit.
  void startMonitoring({
    required VoidCallback onWarning,
    required VoidCallback onAutoSubmit,
  }) {
    _backgroundCount = 0;
    _fgbgSub = FGBGEvents.stream.listen((event) {
      if (event == FGBGType.background) {
        _backgroundCount++;
        if (_backgroundCount > maxWarnings) {
          onAutoSubmit();
        } else {
          onWarning();
        }
      }
    });
  }

  void stopMonitoring() {
    _fgbgSub?.cancel();
    _fgbgSub = null;
  }
}