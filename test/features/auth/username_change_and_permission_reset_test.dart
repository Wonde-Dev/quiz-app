import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/utils/role_username.dart';
import 'package:quiz_app/shared/models/course_resource.dart';
import 'package:quiz_app/shared/models/school_announcement.dart';

void main() {
  group('Username Prefix Extraction & Institutional Suffix Formatting', () {
    test('role suffixes are correctly generated for each user role', () {
      expect(roleSuffix(AppRoles.admin), equals('@Admin.edu'));
      expect(roleSuffix(AppRoles.director), equals('@Director.edu'));
      expect(roleSuffix(AppRoles.subadmin), equals('@Director.edu'));
      expect(roleSuffix(AppRoles.teacher), equals('@Teacher.edu'));
      expect(roleSuffix(AppRoles.student), equals('@Student.edu'));
    });

    test('clean username prefix formatting strips suffix cleanly', () {
      expect(cleanUsernamePrefix('SultanAdinan@Admin.edu'), equals('SultanAdinan'));
      expect(cleanUsernamePrefix('sultanadinan'), equals('sultanadinan'));
      expect(cleanUsernamePrefix('  AbebeKebede@Teacher.edu  '), equals('AbebeKebede'));
      expect(cleanUsernamePrefix('wonde-dev@student.edu'), equals('wonde-dev'));
    });

    test('recombining prefix with role suffix yields canonical institutional username', () {
      final prefix = cleanUsernamePrefix('WondeNew');
      final formatted = '$prefix${roleSuffix(AppRoles.teacher)}';
      expect(formatted, equals('WondeNew@Teacher.edu'));
    });

    test('username lookup query matches prefix before @', () {
      const storedUsername = 'SultanAdinan@Director.edu';
      final parts = storedUsername.split('@');
      final prefix = parts[0].toLowerCase();
      expect(prefix, equals('sultanadinan'));

      // Users typing prefix alone or full username will match
      expect('sultanadinan'.toLowerCase(), equals(prefix));
      expect('SultanAdinan'.toLowerCase(), equals(prefix));
    });
  });

  group('Role-Based Password Reset Matrix Authorization', () {
    // Simulating the RPC rules implemented in 20261101020000_teacher_scoping_username_updates_and_permissions.sql
    bool isAuthorizedToResetPassword({
      required String callerRole,
      required bool callerIsAttendance,
      required String targetRole,
    }) {
      if (callerRole == AppRoles.admin) {
        return true; // Super Admin resets all roles
      }
      if (AppRoles.isDirector(callerRole)) {
        // Director resets teachers ONLY
        return targetRole == AppRoles.teacher;
      }
      if (callerRole == AppRoles.teacher) {
        // Attendance teacher resets students ONLY
        return callerIsAttendance && targetRole == AppRoles.student;
      }
      return false;
    }

    test('Super Admin has authorization to reset all roles', () {
      expect(
        isAuthorizedToResetPassword(
          callerRole: AppRoles.admin,
          callerIsAttendance: false,
          targetRole: AppRoles.admin,
        ),
        isTrue,
      );
      expect(
        isAuthorizedToResetPassword(
          callerRole: AppRoles.admin,
          callerIsAttendance: false,
          targetRole: AppRoles.director,
        ),
        isTrue,
      );
      expect(
        isAuthorizedToResetPassword(
          callerRole: AppRoles.admin,
          callerIsAttendance: false,
          targetRole: AppRoles.teacher,
        ),
        isTrue,
      );
      expect(
        isAuthorizedToResetPassword(
          callerRole: AppRoles.admin,
          callerIsAttendance: false,
          targetRole: AppRoles.student,
        ),
        isTrue,
      );
    });

    test('Director has authorization to reset Teachers ONLY', () {
      expect(
        isAuthorizedToResetPassword(
          callerRole: AppRoles.director,
          callerIsAttendance: false,
          targetRole: AppRoles.teacher,
        ),
        isTrue,
      );
      expect(
        isAuthorizedToResetPassword(
          callerRole: AppRoles.director,
          callerIsAttendance: false,
          targetRole: AppRoles.student,
        ),
        isFalse,
      );
      expect(
        isAuthorizedToResetPassword(
          callerRole: AppRoles.director,
          callerIsAttendance: false,
          targetRole: AppRoles.admin,
        ),
        isFalse,
      );
      expect(
        isAuthorizedToResetPassword(
          callerRole: AppRoles.director,
          callerIsAttendance: false,
          targetRole: AppRoles.director,
        ),
        isFalse,
      );
    });

    test('Attendance Teacher has authorization to reset Students ONLY', () {
      expect(
        isAuthorizedToResetPassword(
          callerRole: AppRoles.teacher,
          callerIsAttendance: true,
          targetRole: AppRoles.student,
        ),
        isTrue,
      );
      expect(
        isAuthorizedToResetPassword(
          callerRole: AppRoles.teacher,
          callerIsAttendance: true,
          targetRole: AppRoles.teacher,
        ),
        isFalse,
      );
      expect(
        isAuthorizedToResetPassword(
          callerRole: AppRoles.teacher,
          callerIsAttendance: true,
          targetRole: AppRoles.director,
        ),
        isFalse,
      );
    });

    test('Non-Attendance Teacher is strictly forbidden from resetting any account', () {
      expect(
        isAuthorizedToResetPassword(
          callerRole: AppRoles.teacher,
          callerIsAttendance: false,
          targetRole: AppRoles.student,
        ),
        isFalse,
      );
      expect(
        isAuthorizedToResetPassword(
          callerRole: AppRoles.teacher,
          callerIsAttendance: false,
          targetRole: AppRoles.teacher,
        ),
        isFalse,
      );
    });
  });

  group('Teacher Multi-Grade & Multi-Section Scoping', () {
    List<Map<String, dynamic>> filterStudentsForTeacher({
      required List<Map<String, dynamic>> allStudents,
      required String? assignedGrade,
      required String? attendanceGrade,
      required String? assignedClass,
      required String? attendanceClass,
      required List<Map<String, dynamic>> teacherCourses,
    }) {
      final assignedGradesSet = <String>{};
      final assignedSectionsSet = <String>{};

      void addParts(Set<String> set, String? raw) {
        if (raw == null) return;
        for (final p in raw.split(RegExp(r'[,;]'))) {
          final trimmed = p.trim().toLowerCase();
          if (trimmed.isNotEmpty) set.add(trimmed);
        }
      }

      addParts(assignedGradesSet, assignedGrade);
      addParts(assignedGradesSet, attendanceGrade);
      addParts(assignedSectionsSet, assignedClass);
      addParts(assignedSectionsSet, attendanceClass);

      for (final tc in teacherCourses) {
        final sec = tc['sections'] as Map<String, dynamic>?;
        if (sec != null) {
          final g = sec['grade']?.toString().trim().toLowerCase();
          final n = sec['name']?.toString().trim().toLowerCase();
          if (g != null && g.isNotEmpty) assignedGradesSet.add(g);
          if (n != null && n.isNotEmpty) assignedSectionsSet.add(n);
        }
      }

      if (assignedGradesSet.isEmpty && assignedSectionsSet.isEmpty) {
        return []; // Unassigned teacher sees 0 students
      }

      return allStudents.where((s) {
        if (s['is_active'] == false) return false;
        final sGrade = (s['assigned_grade'] ?? s['requested_grade'] ?? '').toString().trim().toLowerCase();
        final sClass = (s['assigned_class'] ?? s['requested_class'] ?? '').toString().trim().toLowerCase();

        final gradeMatch = assignedGradesSet.isEmpty ||
            assignedGradesSet.any((ag) => sGrade == ag || sGrade.contains(ag) || ag.contains(sGrade));
        final sectionMatch = assignedSectionsSet.isEmpty ||
            assignedSectionsSet.any((asect) => sClass == asect || sClass.contains(asect) || asect.contains(sClass));

        return gradeMatch && sectionMatch;
      }).toList();
    }

    final sampleSchoolStudents = [
      {'id': '1', 'full_name': 'Ali 9A', 'assigned_grade': 'Grade 9', 'assigned_class': 'Section A', 'is_active': true},
      {'id': '2', 'full_name': 'Sara 9B', 'assigned_grade': 'Grade 9', 'assigned_class': 'Section B', 'is_active': true},
      {'id': '3', 'full_name': 'Omar 10A', 'assigned_grade': 'Grade 10', 'assigned_class': 'Section A', 'is_active': true},
      {'id': '4', 'full_name': 'Hana 10B', 'assigned_grade': 'Grade 10', 'assigned_class': 'Section B', 'is_active': true},
      {'id': '5', 'full_name': 'Zack 11A', 'assigned_grade': 'Grade 11', 'assigned_class': 'Section A', 'is_active': true},
      {'id': '6', 'full_name': 'Maya 12B', 'assigned_grade': 'Grade 12', 'assigned_class': 'Section B', 'is_active': true},
    ];

    test('Teacher assigned to multiple grades (9 and 10) sees only those grades and sections', () {
      final scoped = filterStudentsForTeacher(
        allStudents: sampleSchoolStudents,
        assignedGrade: 'Grade 9, Grade 10',
        attendanceGrade: null,
        assignedClass: 'Section A',
        attendanceClass: null,
        teacherCourses: [],
      );

      expect(scoped.length, equals(2));
      expect(scoped.map((s) => s['id']).toList(), containsAll(['1', '3']));
      expect(scoped.map((s) => s['id']).toList(), isNot(contains('5'))); // Grade 11 excluded
    });

    test('Teacher with multiple course allocations across grades and sections is properly scoped', () {
      final scoped = filterStudentsForTeacher(
        allStudents: sampleSchoolStudents,
        assignedGrade: null,
        attendanceGrade: null,
        assignedClass: null,
        attendanceClass: null,
        teacherCourses: [
          {
            'sections': {'grade': 'Grade 9', 'name': 'Section B'}
          },
          {
            'sections': {'grade': 'Grade 10', 'name': 'Section B'}
          },
        ],
      );

      expect(scoped.length, equals(2));
      expect(scoped.map((s) => s['id']).toList(), containsAll(['2', '4']));
      expect(scoped.map((s) => s['id']).toList(), isNot(contains('1'))); // Section A excluded
    });

    test('Teacher with zero assignments sees empty list rather than leaking entire school', () {
      final scoped = filterStudentsForTeacher(
        allStudents: sampleSchoolStudents,
        assignedGrade: null,
        attendanceGrade: null,
        assignedClass: null,
        attendanceClass: null,
        teacherCourses: [],
      );

      expect(scoped, isEmpty);
    });
  });

  group('Notification Preferences and Sender Attribution', () {
    final now = DateTime.now();
    final sampleAnnouncements = [
      SchoolAnnouncement(
        id: 'ann-1',
        schoolId: '00000000-0000-4000-8000-000000000001',
        authorId: 'admin-id',
        authorName: 'Wonde-Dev',
        authorRole: 'admin',
        title: 'Emergency Drill',
        content: 'Campus drill scheduled for tomorrow morning.',
        targetAudience: 'all',
        isPinned: true,
        createdAt: now,
      ),
      SchoolAnnouncement(
        id: 'ann-2',
        schoolId: '00000000-0000-4000-8000-000000000001',
        authorId: 'dir-id',
        authorName: 'Sultan Adinan',
        authorRole: 'director',
        title: 'Faculty Schedule Meeting',
        content: 'Directorate staff review at 2 PM.',
        targetAudience: 'teachers',
        isPinned: false,
        createdAt: now,
      ),
    ];

    test('Notification suppression respects user preference toggles', () {
      List<SchoolAnnouncement> filterAnnouncements({
        required bool allowAdmin,
        required bool allowDirector,
        required String userRole,
      }) {
        return sampleAnnouncements.where((ann) {
          final r = ann.authorRole.toLowerCase();
          if (r.contains('admin') && !allowAdmin) return false;
          if ((r.contains('director') || r.contains('subadmin')) && !allowDirector) return false;
          final target = ann.targetAudience.toLowerCase();
          if (target != 'all' && !target.contains(userRole)) return false;
          return true;
        }).toList();
      }

      // Both allowed
      final all = filterAnnouncements(allowAdmin: true, allowDirector: true, userRole: 'teacher');
      expect(all.length, equals(2));

      // Admin muted
      final noAdmin = filterAnnouncements(allowAdmin: false, allowDirector: true, userRole: 'teacher');
      expect(noAdmin.length, equals(1));
      expect(noAdmin.first.id, equals('ann-2'));

      // Director muted
      final noDirector = filterAnnouncements(allowAdmin: true, allowDirector: false, userRole: 'teacher');
      expect(noDirector.length, equals(1));
      expect(noDirector.first.id, equals('ann-1'));

      // Both muted
      final none = filterAnnouncements(allowAdmin: false, allowDirector: false, userRole: 'teacher');
      expect(none, isEmpty);
    });

    test('Sender attribution correctly identifies author role and name', () {
      final ann = sampleAnnouncements.first;
      final isAdmin = ann.authorRole.toLowerCase().contains('admin');
      final label = isAdmin ? 'Super Admin' : 'School Directorate';
      final attribution = 'From: $label (${ann.authorName})';
      expect(attribution, equals('From: Super Admin (Wonde-Dev)'));
    });
  });

  group('Worksheet, PDF & Video Publishing with Custom Thumbnails', () {
    test('CourseResource model preserves custom thumbnail URL', () {
      final resource = CourseResource.fromMap({
        'id': 'res-101',
        'title': 'Grade 10 Physics Worksheet',
        'description': 'Worksheet on kinematics and energy conservation',
        'file_name': 'physics_kinematics_worksheet.pdf',
        'file_url': 'https://storage.supabase.co/materials/physics.pdf',
        'file_type': 'worksheet',
        'thumbnail_url': 'https://storage.supabase.co/materials/physics_thumb.png',
        'created_at': DateTime.now().toIso8601String(),
      });

      expect(resource.title, equals('Grade 10 Physics Worksheet'));
      expect(resource.fileType, equals('worksheet'));
      expect(resource.isPdf, isTrue);
      expect(resource.effectiveThumbnail, equals('https://storage.supabase.co/materials/physics_thumb.png'));
    });

    test('YouTube video resource auto-resolves thumbnail fallback if not explicitly provided', () {
      final resource = CourseResource.fromMap({
        'id': 'res-102',
        'title': 'Calculus Derivatives Video Lesson',
        'description': 'Intro to product and quotient rules',
        'video_url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'file_url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'file_type': 'video',
        'created_at': DateTime.now().toIso8601String(),
      });

      expect(resource.isVideo, isTrue);
      expect(
        resource.effectiveThumbnail,
        equals('https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg'),
      );
    });
  });
}
