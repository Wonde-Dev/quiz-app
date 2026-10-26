import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quiz_app/core/services/onboarding_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OnboardingService', () {
    test('initially returns false when onboarding has never been completed',
        () async {
      SharedPreferences.setMockInitialValues({});
      final completed = await OnboardingService.hasCompletedOnboarding();
      expect(completed, isFalse);
    });

    test('marks onboarding completed and persists true', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await OnboardingService.hasCompletedOnboarding(), isFalse);

      await OnboardingService.markOnboardingCompleted();
      expect(await OnboardingService.hasCompletedOnboarding(), isTrue);
    });

    test('resetOnboarding clears the completed state', () async {
      SharedPreferences.setMockInitialValues({
        'quiz_app_onboarding_completed_v1': true,
      });
      expect(await OnboardingService.hasCompletedOnboarding(), isTrue);

      await OnboardingService.resetOnboarding();
      expect(await OnboardingService.hasCompletedOnboarding(), isFalse);
    });
  });
}

