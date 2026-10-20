import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quiz_app/core/router/app_router.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/shared/models/user.dart';

void main() {
  test(
    'keeps the router instance stable when authentication state changes',
    () {
      final container = ProviderContainer(
        overrides: [authStateProvider.overrideWith(_TestAuthNotifier.new)],
      );
      addTearDown(container.dispose);

      final router = container.read(routerProvider);
      final notifier =
          container.read(authStateProvider.notifier) as _TestAuthNotifier;
      notifier.setTestState(
        AuthState(
          user: AppUser(
            id: 'student-id',
            username: 'AlexStudent@Student.edu',
            email: 'alex@example.edu',
            role: 'student',
            createdAt: DateTime.utc(2026),
          ),
        ),
      );

      expect(container.read(routerProvider), same(router));
    },
  );
}

class _TestAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState();

  void setTestState(AuthState value) => state = value;
}
