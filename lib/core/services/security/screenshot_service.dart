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
  bool _isScreenRecording = false;

  bool get isProtected => _isProtected;
  bool get isScreenRecording => _isScreenRecording;

  /// Enable native capture prevention for the current mobile platform.
  Future<void> enableProtection({
    required void Function(String detectedAt) onScreenshotDetected,
    void Function(bool isRecording)? onRecordingChanged,
  }) async {
    if (_isProtected) return;

    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }

    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        // Enforces FLAG_SECURE on the Android window (renders all screenshots and recordings pitch black)
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
          onScreenshotDetected('Screenshot captured on iOS');
        });
        _recordingSub = _screenGuard.onScreenRecordingCaptured.listen((event) {
          final isRec = event['isRecording'] == true;
          _isScreenRecording = isRec;
          onRecordingChanged?.call(isRec);
          if (isRec) {
            onScreenshotDetected('Screen recording active on iOS');
          }
        });
      }
    } catch (e) {
      debugPrint('Screen protection init note: $e');
    }

    _isProtected = true;
  }

  /// Disable protection when the app's protected surface is torn down.
  Future<void> disableProtection() async {
    if (!_isProtected) return;
    try {
      await _ssSub?.cancel();
      await _recordingSub?.cancel();
      if (defaultTargetPlatform == TargetPlatform.android) {
        await SsPreventer.preventOff();
        await SsPreventer.setDetectionEnabled(false);
      } else {
        await _screenGuard.unregister();
      }
    } catch (e) {
      debugPrint('Screen protection disable note: $e');
    }
    _isProtected = false;
    _isScreenRecording = false;
  }
}
