import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/utils/role_username.dart';
import 'package:quiz_app/shared/models/user.dart';

void main() {
  group('Canonical Username Generation & CamelCase Numbering Rules', () {
    test('First instance of a name receives camelCase username with NO number', () {
      final adminUser = roleUsername('Wonde Admin', 'admin');
      expect(adminUser, equals('WondeAdmin@Admin.edu'));

      final directorUser = roleUsername('Sultan Adinan', 'subadmin');
      expect(directorUser, equals('SultanAdinan@Director.edu'));

      final studentUser = roleUsername('John Doe', 'student');
      expect(studentUser, equals('JohnDoe@Student.edu'));

      final teacherUser = roleUsername('Yonas Desta', 'teacher');
      expect(teacherUser, equals('YonasDesta@Teacher.edu'));
    });

    test('nextRoleUsername assigns no number for first user, and sequential numbers for duplicate names', () {
      final existing = <String>{};

      // 1st instance: No number
      final first = nextRoleUsername(
        fullName: 'Wonde Admin',
        role: 'admin',
        existingUsernames: existing,
      );
      expect(first, equals('WondeAdmin@Admin.edu'));
      existing.add(first);

      // 2nd instance with same name: receives 1
      final second = nextRoleUsername(
        fullName: 'Wonde Admin',
        role: 'admin',
        existingUsernames: existing,
      );
      expect(second, equals('WondeAdmin1@Admin.edu'));
      existing.add(second);

      // 3rd instance: receives 2
      final third = nextRoleUsername(
        fullName: 'Wonde Admin',
        role: 'admin',
        existingUsernames: existing,
      );
      expect(third, equals('WondeAdmin2@Admin.edu'));
    });

    test('defaultRolePassword generates correct role letter and order', () {
      // Admin password formula: <NamePart>1@A.edu
      final adminPw = defaultRolePassword(usernameOrFullName: 'WondeAdmin@Admin.edu');
      expect(adminPw, equals('WondeAdmin1@A.edu'));

      // Director password formula: <NamePart>1@D.edu
      final dirPw = defaultRolePassword(usernameOrFullName: 'SultanAdinan@Director.edu');
      expect(dirPw, equals('SultanAdinan1@D.edu'));

      // Student password formula: <NamePart>1@S.edu
      final studentPw = defaultRolePassword(usernameOrFullName: 'JohnDoe@Student.edu');
      expect(studentPw, equals('JohnDoe1@S.edu'));

      // Teacher password formula: <NamePart>1@T.edu
      final teacherPw = defaultRolePassword(usernameOrFullName: 'YonasD@Teacher.edu');
      expect(teacherPw, equals('YonasD1@T.edu'));
    });

    test('roleFromUsername parses canonical and numbered usernames correctly', () {
      expect(roleFromUsername('WondeAdmin@Admin.edu'), equals('admin'));
      expect(roleFromUsername('WondeAdmin1@Admin.edu'), equals('admin'));
      expect(roleFromUsername('SultanAdinan@Director.edu'), equals('subadmin'));
      expect(roleFromUsername('SultanAdinan1@Director.edu'), equals('subadmin'));
      expect(roleFromUsername('JohnDoe@Student.edu'), equals('student'));
      expect(roleFromUsername('JohnDoe2@Student.edu'), equals('student'));
      expect(roleFromUsername('YonasDesta@Teacher.edu'), equals('teacher'));
    });
  });

  group('Executive Administration Notification Rules', () {
    test('Super Admin and Director cannot be muted by default notification settings', () {
      final adminUser = AppUser(
        id: 'admin-1',
        email: 'wondedev369@gmail.com',
        username: 'WondeAdmin@Admin.edu',
        role: AppRoles.admin,
        isSuperAdmin: true,
        allowAdminNotifications: true,
        allowDirectorNotifications: true,
        createdAt: DateTime.now(),
      );

      final directorUser = AppUser(
        id: 'dir-1',
        email: 'wondetech404@gmail.com',
        username: 'SultanAdinan@Director.edu',
        role: AppRoles.subadmin,
        allowAdminNotifications: true,
        allowDirectorNotifications: true,
        createdAt: DateTime.now(),
      );

      expect(adminUser.role, equals(AppRoles.admin));
      expect(AppRoles.isDirector(directorUser.role), isTrue);
      expect(adminUser.allowAdminNotifications, isTrue);
      expect(directorUser.allowDirectorNotifications, isTrue);
    });
  });

  group('Attendance Teacher Scoping and Permissions', () {
    test('Attendance teacher identifies designated class and homeroom privileges', () {
      final attendanceTeacher = AppUser(
        id: 'teacher-att-1',
        email: 'teacher@ciro.edu',
        username: 'TeacherOne@Teacher.edu',
        role: AppRoles.teacher,
        isAttendanceTeacher: true,
        attendanceGrade: 'Grade 9',
        attendanceClass: '9A',
        createdAt: DateTime.now(),
      );

      expect(attendanceTeacher.isAttendanceTeacher, isTrue);
      expect(attendanceTeacher.attendanceClass, equals('9A'));
      expect(attendanceTeacher.attendanceGrade, equals('Grade 9'));

      final regularTeacher = AppUser(
        id: 'teacher-reg-1',
        email: 'teacher2@ciro.edu',
        username: 'TeacherTwo@Teacher.edu',
        role: AppRoles.teacher,
        isAttendanceTeacher: false,
        createdAt: DateTime.now(),
      );

      expect(regularTeacher.isAttendanceTeacher, isFalse);
      expect(regularTeacher.attendanceClass, isNull);
    });
  });
}
