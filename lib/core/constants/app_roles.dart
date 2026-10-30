// core/constants/app_roles.dart
class AppRoles {
  static const admin = 'admin'; // Super Administrator
  static const director = 'subadmin'; // School Director
  static const subadmin = 'subadmin'; // Deprecated alias for backwards compatibility
  static const teacher = 'teacher';
  static const student = 'student';

  /// Whether the given role is Super Admin
  static bool isSuperAdmin(String? role) => role == admin;

  /// Whether the given role is School Director
  static bool isDirector(String? role) => role == director || role == 'director';

  /// Whether the given role has administrative privileges (Admin or Director)
  static bool isAdmin(String? role) => role == admin || isDirector(role);

  /// Whether the given role is teacher
  static bool isTeacher(String? role) => role == teacher;

  /// Whether the given role is student
  static bool isStudent(String? role) => role == student;
}
