import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/router/role_guard.dart';
import 'package:quiz_app/shared/models/user.dart';

void main() {
  AppUser userWithRole(String role) => AppUser(
    id: 'user-id',
    username: 'user',
    email: 'user@example.com',
    role: role,
    createdAt: DateTime.utc(2026),
  );

  group('RoleGuard', () {
    test('sends students away from administrator routes', () {
      final redirect = RoleGuard.redirect(
        user: userWithRole(AppRoles.student),
        location: '/admin/dashboard',
        allowedRoles: {AppRoles.admin},
      );

      expect(redirect, '/student/dashboard');
    });

    test('sends teachers away from student routes', () {
      final redirect = RoleGuard.redirect(
        user: userWithRole(AppRoles.teacher),
        location: '/student/dashboard',
        allowedRoles: {AppRoles.student},
      );

      expect(redirect, '/teacher/dashboard');
    });

    test('allows administrators through any role guard', () {
      final redirect = RoleGuard.redirect(
        user: userWithRole(AppRoles.admin),
        location: '/student/dashboard',
        allowedRoles: {AppRoles.student},
      );

      expect(redirect, isNull);
    });
  });
}
