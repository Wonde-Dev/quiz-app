import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/utils/role_username.dart';
import 'package:quiz_app/shared/models/user.dart';

void main() {
  group('Director Credentials & Formulas', () {
    test('roleFromUsername accurately classifies both @Director.edu and director role aliases', () {
      expect(roleFromUsername('SultanAdinan1@Director.edu'), equals('subadmin'));
      expect(roleFromUsername('SultanAdinan@Director.edu'), equals('subadmin'));
      expect(isRoleUsername('SultanAdinan1@Director.edu', 'subadmin'), isTrue);
      expect(isRoleUsername('SultanAdinan@Director.edu', 'director'), isTrue);
    });

    test('defaultRolePassword generates correct formulas for both @D.edu and @A.edu director variations', () {
      // Director format with @Director.edu yields @D.edu
      final dirPw = defaultRolePassword(usernameOrFullName: 'SultanAdinan1@Director.edu');
      expect(dirPw, equals('SultanAdinan1@D.edu'));

      // Directorate format with @Admin.edu yields @A.edu
      final adminPw = defaultRolePassword(usernameOrFullName: 'SultanAdinan@Admin.edu');
      expect(adminPw, equals('SultanAdinan1@A.edu'));

      // Both role letters are mapped correctly
      expect(roleLetter('director'), equals('D'));
      expect(roleLetter('subadmin'), equals('D'));
      expect(roleLetter('SultanAdinan@Director.edu'), equals('D'));
      expect(roleLetter('SultanAdinan@Admin.edu'), equals('A'));
    });
  });

  group('Brute Force Account Lockout (3 Failed Attempts Limit)', () {
    test('AppUser model serializes and tracks failedLoginAttempts, isLocked, and lockedAt', () {
      final now = DateTime.now();
      final user = AppUser(
        id: 'user-lock-test',
        username: 'TestStudent1@Student.edu',
        email: 'test@ciroschools.local',
        role: AppRoles.student,
        createdAt: now,
        failedLoginAttempts: 3,
        isLocked: true,
        lockedAt: now,
      );

      expect(user.failedLoginAttempts, equals(3));
      expect(user.isLocked, isTrue);
      expect(user.lockedAt, equals(now));

      final map = user.toMap();
      expect(map['failed_login_attempts'], equals(3));
      expect(map['is_locked'], isTrue);
      expect(map['locked_at'], equals(now.toIso8601String()));

      final fromMap = AppUser.fromMap(map);
      expect(fromMap.failedLoginAttempts, equals(3));
      expect(fromMap.isLocked, isTrue);
      expect(fromMap.lockedAt, isNotNull);
    });

    test('copyWith updates lock status and attempt counts accurately', () {
      final user = AppUser(
        id: 'user-1',
        username: 'Student1@Student.edu',
        email: 'stud1@gmail.com',
        role: AppRoles.student,
        createdAt: DateTime.now(),
        failedLoginAttempts: 2,
        isLocked: false,
      );

      // Simulating 3rd failed attempt -> locked
      final lockedUser = user.copyWith(
        failedLoginAttempts: 3,
        isLocked: true,
        lockedAt: DateTime.now(),
      );
      expect(lockedUser.failedLoginAttempts, equals(3));
      expect(lockedUser.isLocked, isTrue);

      // Simulating admin / OTP unlock
      final unlockedUser = lockedUser.copyWith(
        failedLoginAttempts: 0,
        isLocked: false,
        lockedAt: null,
      );
      expect(unlockedUser.failedLoginAttempts, equals(0));
      expect(unlockedUser.isLocked, isFalse);
    });
  });

  group('Grade & Section Scoping', () {
    test('Teacher assigned to specific grades and sections only matches students in those classes', () {
      final teacherAssignedGrades = {'grade 10', 'grade 11'};
      final teacherAssignedSections = {'section a', 'section b'};

      final students = [
        {
          'id': 's1',
          'full_name': 'Abebe Bikila',
          'assigned_grade': 'Grade 10',
          'assigned_class': 'Section A',
          'is_active': true,
        },
        {
          'id': 's2',
          'full_name': 'Derartu Tulu',
          'assigned_grade': 'Grade 10',
          'assigned_class': 'Section B',
          'is_active': true,
        },
        {
          'id': 's3',
          'full_name': 'Kenenisa Bekele',
          'assigned_grade': 'Grade 9', // Different grade
          'assigned_class': 'Section A',
          'is_active': true,
        },
        {
          'id': 's4',
          'full_name': 'Tirunesh Dibaba',
          'assigned_grade': 'Grade 10',
          'assigned_class': 'Section C', // Different section
          'is_active': true,
        },
      ];

      final filtered = students.where((s) {
        final g = (s['assigned_grade'] as String).toLowerCase();
        final c = (s['assigned_class'] as String).toLowerCase();
        return teacherAssignedGrades.contains(g) && teacherAssignedSections.contains(c);
      }).toList();

      expect(filtered.length, equals(2));
      expect(filtered.map((s) => s['id']).toList(), equals(['s1', 's2']));
    });

    test('Student enrolled in Grade 10 Section B strictly filters matching quizzes only', () {
      final studentGrade = 'grade 10';
      final studentSection = 'section b';

      final quizzes = [
        {
          'id': 'q1',
          'title': 'Grade 10 Sec B Algebra Test',
          'target_grade': 'Grade 10',
          'target_section': 'Section B',
        },
        {
          'id': 'q2',
          'title': 'Grade 10 General Physics',
          'target_grade': 'Grade 10',
          'target_section': null,
        },
        {
          'id': 'q3',
          'title': 'Grade 9 Geometry',
          'target_grade': 'Grade 9',
          'target_section': 'Section A',
        },
        {
          'id': 'q4',
          'title': 'Grade 10 Sec A Chemistry',
          'target_grade': 'Grade 10',
          'target_section': 'Section A',
        },
      ];

      final accessible = quizzes.where((q) {
        final qG = (q['target_grade'] as String?)?.toLowerCase();
        final qS = (q['target_section'] as String?)?.toLowerCase();

        if (qG != null && qG != studentGrade) return false;
        if (qS != null && qS != studentSection) return false;
        return true;
      }).toList();

      expect(accessible.length, equals(2));
      expect(accessible.map((q) => q['id']).toList(), equals(['q1', 'q2']));
    });
  });
}
