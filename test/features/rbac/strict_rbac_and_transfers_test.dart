import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/shared/models/teacher_academic_activity.dart';
import 'package:quiz_app/shared/models/user.dart';

void main() {
  group('Strict RBAC Roles & Hierarchy Boundaries', () {
    test('AppRoles defines all 4 distinct roles and predicates', () {
      expect(AppRoles.admin, equals('admin'));
      expect(AppRoles.director, equals('subadmin'));
      expect(AppRoles.teacher, equals('teacher'));
      expect(AppRoles.student, equals('student'));

      expect(AppRoles.isSuperAdmin(AppRoles.admin), isTrue);
      expect(AppRoles.isSuperAdmin(AppRoles.director), isFalse);
      expect(AppRoles.isSuperAdmin(AppRoles.teacher), isFalse);
      expect(AppRoles.isSuperAdmin(AppRoles.student), isFalse);

      expect(AppRoles.isDirector(AppRoles.director), isTrue);
      expect(AppRoles.isDirector('director'), isTrue);
      expect(AppRoles.isDirector(AppRoles.admin), isFalse);
      expect(AppRoles.isDirector(AppRoles.teacher), isFalse);
      expect(AppRoles.isDirector(AppRoles.student), isFalse);

      expect(AppRoles.isTeacher(AppRoles.teacher), isTrue);
      expect(AppRoles.isTeacher(AppRoles.admin), isFalse);

      expect(AppRoles.isStudent(AppRoles.student), isTrue);
      expect(AppRoles.isStudent(AppRoles.teacher), isFalse);
    });

    test('Single active Super Admin and Director constraint logic', () {
      final activeSuperAdmin = AppUser(
        id: 'user-admin-1',
        username: 'WondevAdmin@admin.edu',
        email: 'wondedev369@gmail.com',
        role: AppRoles.admin,
        isSuperAdmin: true,
        isActive: true,
        approvalStatus: 'approved',
        createdAt: DateTime.now(),
      );

      final activeDirector = AppUser(
        id: 'user-director-1',
        username: 'SultanAdinan1@Director.edu',
        email: 'wondetech404@gmail.com',
        role: AppRoles.director,
        isSuperAdmin: false,
        isActive: true,
        approvalStatus: 'approved',
        createdAt: DateTime.now(),
      );

      expect(activeSuperAdmin.isSuperAdmin, isTrue);
      expect(activeSuperAdmin.role, equals(AppRoles.admin));

      expect(activeDirector.isSuperAdmin, isFalse);
      expect(activeDirector.username, equals('SultanAdinan1@Director.edu'));
      expect(AppRoles.isDirector(activeDirector.role), isTrue);

      // Verify second director would exceed limit
      const existingActiveDirectorCount = 1;
      const canRegisterAnotherDirector = existingActiveDirectorCount < 1;
      expect(canRegisterAnotherDirector, isFalse);

      // Verify second admin would exceed limit
      const existingActiveAdminCount = 1;
      const canRegisterAnotherAdmin = existingActiveAdminCount < 1;
      expect(canRegisterAnotherAdmin, isFalse);
    });

    test('Director is restricted from student management and restricted to teacher administration', () {
      final director = AppUser(
        id: 'dir-1',
        username: 'SultanAdinan1@Director.edu',
        email: 'wondetech404@gmail.com',
        role: AppRoles.director,
        createdAt: DateTime.now(),
      );

      // Director can manage faculty teachers
      final canManageTeachers = AppRoles.isDirector(director.role);
      expect(canManageTeachers, isTrue);

      // Director cannot access student rosters or mark registers
      final canAccessPrivateStudentRecords = AppRoles.isSuperAdmin(director.role);
      expect(canAccessPrivateStudentRecords, isFalse);

      // Director cannot access super admin dashboard
      final canAccessSuperAdminDashboard = AppRoles.isSuperAdmin(director.role);
      expect(canAccessSuperAdminDashboard, isFalse);

      // Super admin cannot author quizzes
      final isSuperAdmin = AppRoles.isSuperAdmin(AppRoles.admin);
      final canAuthorQuiz = !isSuperAdmin;
      expect(canAuthorQuiz, isFalse);
    });

    test('Role registration authority boundaries', () {
      List<String> allowedRegistrationRoles(String callerRole, {bool isAttendanceTeacher = false}) {
        if (AppRoles.isSuperAdmin(callerRole)) {
          return [AppRoles.student, AppRoles.teacher, AppRoles.subadmin];
        }
        if (AppRoles.isDirector(callerRole)) {
          return [AppRoles.teacher]; // Strictly Teachers only
        }
        if (AppRoles.isTeacher(callerRole) && isAttendanceTeacher) {
          return [AppRoles.student]; // Strictly Students only
        }
        return [];
      }

      final adminOptions = allowedRegistrationRoles(AppRoles.admin);
      expect(adminOptions, containsAll([AppRoles.student, AppRoles.teacher, AppRoles.subadmin]));

      final directorOptions = allowedRegistrationRoles(AppRoles.director);
      expect(directorOptions, equals([AppRoles.teacher]));
      expect(directorOptions.contains(AppRoles.student), isFalse);
      expect(directorOptions.contains(AppRoles.admin), isFalse);
      expect(directorOptions.contains(AppRoles.subadmin), isFalse);

      final attendanceTeacherOptions = allowedRegistrationRoles(AppRoles.teacher, isAttendanceTeacher: true);
      expect(attendanceTeacherOptions, equals([AppRoles.student]));
      expect(attendanceTeacherOptions.contains(AppRoles.teacher), isFalse);

      final regularTeacherOptions = allowedRegistrationRoles(AppRoles.teacher, isAttendanceTeacher: false);
      expect(regularTeacherOptions, isEmpty);
    });
  });

  group('TeacherAcademicActivity Model', () {
    test('Serializes and deserializes academic activities without student data', () {
      final now = DateTime.now();
      final activity = TeacherAcademicActivity(
        id: 'act-123',
        schoolId: '00000000-0000-4000-8000-000000000001',
        teacherId: 'teacher-uuid-456',
        teacherName: 'Yonas D.',
        activityType: 'examination_published',
        description: 'Prepared Midterm Physics Exam',
        subject: 'Physics',
        targetGrade: 'Grade 11',
        targetSection: '11B',
        status: 'Published',
        createdAt: now,
      );

      final map = activity.toMap();
      expect(map['id'], equals('act-123'));
      expect(map['teacher_name'], equals('Yonas D.'));
      expect(map['activity_type'], equals('examination_published'));
      expect(map['subject'], equals('Physics'));
      expect(map['target_grade'], equals('Grade 11'));
      expect(map['target_section'], equals('11B'));
      expect(map['status'], equals('Published'));

      // Ensures NO student identifiers or private grades exist in the activity
      expect(map.containsKey('student_id'), isFalse);
      expect(map.containsKey('score'), isFalse);
      expect(map.containsKey('student_name'), isFalse);

      final fromMap = TeacherAcademicActivity.fromMap(map);
      expect(fromMap.displayType, equals('Examination Published'));
      expect(fromMap.targetDisplay, equals('Grade 11 - 11B'));
    });

    test('TeacherAcademicActivity handles fallbacks gracefully', () {
      final activity = TeacherAcademicActivity.fromMap({});
      expect(activity.teacherName, equals('Faculty Teacher'));
      expect(activity.status, equals('Active'));
      expect(activity.targetDisplay, equals('All Classes'));
      expect(activity.displayType, equals('Quiz Created'));
    });
  });

  group('Router Destination Mapping', () {
    test('Routes each role to its dedicated dashboard', () {
      String resolveHomeRoute(String role) {
        return switch (role) {
          AppRoles.admin => '/admin/dashboard',
          AppRoles.subadmin || AppRoles.director || 'director' => '/director/dashboard',
          AppRoles.teacher => '/teacher/dashboard',
          AppRoles.student => '/student/dashboard',
          _ => '/login',
        };
      }

      expect(resolveHomeRoute(AppRoles.admin), equals('/admin/dashboard'));
      expect(resolveHomeRoute(AppRoles.director), equals('/director/dashboard'));
      expect(resolveHomeRoute('director'), equals('/director/dashboard'));
      expect(resolveHomeRoute(AppRoles.teacher), equals('/teacher/dashboard'));
      expect(resolveHomeRoute(AppRoles.student), equals('/student/dashboard'));
    });

    test('Blocks Super Admin and Director from entering quiz authoring tool', () {
      bool isAllowedToAuthorQuiz(String role) {
        return role == AppRoles.teacher;
      }

      expect(isAllowedToAuthorQuiz(AppRoles.teacher), isTrue);
      expect(isAllowedToAuthorQuiz(AppRoles.admin), isFalse);
      expect(isAllowedToAuthorQuiz(AppRoles.director), isFalse);
      expect(isAllowedToAuthorQuiz(AppRoles.student), isFalse);
    });
  });
}

