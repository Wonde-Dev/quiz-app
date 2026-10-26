import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage onboarding persistence so new users see onboarding
/// once on their initial launch, while returning users proceed directly.
class OnboardingService {
  static const String _onboardingKey = 'quiz_app_onboarding_completed_v1';

  /// Check whether the user has already completed or dismissed onboarding.
  static Future<bool> hasCompletedOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_onboardingKey) ?? false;
    } catch (e) {
      debugPrint('OnboardingService.hasCompletedOnboarding error: $e');
      return false;
    }
  }

  /// Mark onboarding as completed.
  static Future<void> markOnboardingCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onboardingKey, true);
    } catch (e) {
      debugPrint('OnboardingService.markOnboardingCompleted error: $e');
    }
  }

  /// Reset onboarding status (useful for testing or replay tour).
  static Future<void> resetOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_onboardingKey);
    } catch (e) {
      debugPrint('OnboardingService.resetOnboarding error: $e');
    }
  }
}

