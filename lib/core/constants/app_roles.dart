// core/constants/app_roles.dart
class AppRoles {
  static const admin = 'admin'; // Super Administrator
  static const subadmin = 'subadmin'; // Sub-Admin / School Director
  static const teacher = 'teacher';
  static const student = 'student';

  /// Whether the given role has administrative privileges
  static bool isAdmin(String? role) => role == admin || role == subadmin;

  /// Whether the given role is teacher
  static bool isTeacher(String? role) => role == teacher;

  /// Whether the given role is student
  static bool isStudent(String? role) => role == student;
}
