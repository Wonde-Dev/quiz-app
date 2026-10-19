// core/router/role_guard.dart
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/shared/models/user.dart';

class RoleGuard {
  static String? redirect({
    required AppUser? user,
    required String location,
    required Set<String> allowedRoles,
  }) {
    if (user == null) return '/login';
    if (user.isAdmin) return null;
    if (!allowedRoles.contains(user.role)) {
      // Send each role to its own dashboard
      switch (user.role) {
        case AppRoles.admin:
          return '/admin/dashboard';
        case AppRoles.teacher:
          return '/teacher/dashboard';
        case AppRoles.student:
          return '/student/dashboard';
        default:
          return '/login';
      }
    }
    return null; // allow navigation
  }
}
