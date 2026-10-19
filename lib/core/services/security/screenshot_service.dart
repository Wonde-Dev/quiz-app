import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenguard/flutter_screenguard.dart';
import 'package:ss_preventer/ss_preventer.dart';

/// Enables/disables screenshot prevention and detection.
class ScreenshotService {
  StreamSubscription? _ssSub;
  StreamSubscription? _recordingSub;
  final FlutterScreenguard _screenGuard = FlutterScreenguard();
  bool _isProtected = false;

  /// Enable native capture prevention for the current mobile platform.
  Future<void> enableProtection({
    required void Function(String detectedAt) onScreenshotDetected,
  }) async {
    if (_isProtected) return;

    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      await SsPreventer.preventOn();
      await SsPreventer.setDetectionEnabled(true);
      _ssSub = SsPreventer.screenshotStream.listen((event) {
        onScreenshotDetected('Screenshot detected at ${event.detectedAt}');
      });
    } else {
      await _screenGuard.initSettings(
        enableCapture: true,
        enableRecord: true,
        enableContentMultitask: false,
        displayOverlay: true,
        trackingLog: true,
      );
      await _screenGuard.register(color: Colors.black);
      _ssSub = _screenGuard.onScreenshotCaptured.listen((_) {
        onScreenshotDetected('Screenshot detected');
      });
      _recordingSub = _screenGuard.onScreenRecordingCaptured.listen((event) {
        if (event['isRecording'] == true) {
          onScreenshotDetected('Screen recording detected');
        }
      });
    }

    _isProtected = true;
  }

  /// Disable protection when the app's protected surface is torn down.
  Future<void> disableProtection() async {
    if (!_isProtected) return;
    await _ssSub?.cancel();
    await _recordingSub?.cancel();
    if (defaultTargetPlatform == TargetPlatform.android) {
      await SsPreventer.preventOff();
      await SsPreventer.setDetectionEnabled(false);
    } else {
      await _screenGuard.unregister();
    }
    _isProtected = false;
  }
}
