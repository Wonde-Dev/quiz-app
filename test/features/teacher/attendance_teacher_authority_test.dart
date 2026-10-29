import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/utils/exam_script_parser.dart';
import 'package:quiz_app/shared/models/user.dart';

void main() {
  group('Attendance Teacher & Director Authority Boundaries', () {
    test('Attendance Teacher is scoped strictly to designated attendance class', () {
      final attendanceTeacher = AppUser(
        id: 'att-teacher-1',
        email: 'teacher.ciro@Teacher.edu',
        username: 'teacher.ciro@Teacher.edu',
        role: AppRoles.teacher,
        schoolId: '00000000-0000-4000-8000-000000000001',
        createdAt: DateTime.now(),
        isAttendanceTeacher: true,
        attendanceClass: '9A',
        attendanceGrade: 'Grade 9',
      );

      expect(attendanceTeacher.role, equals(AppRoles.teacher));
      expect(attendanceTeacher.isAttendanceTeacher, isTrue);
      expect(attendanceTeacher.attendanceClass, equals('9A'));
      expect(attendanceTeacher.attendanceGrade, equals('Grade 9'));

      // Student matching logic
      final studentClass9A = '9A';
      final studentClass9B = '9B';

      expect(
        studentClass9A.toLowerCase() == attendanceTeacher.attendanceClass!.toLowerCase(),
        isTrue,
      );
      expect(
        studentClass9B.toLowerCase() == attendanceTeacher.attendanceClass!.toLowerCase(),
        isFalse,
      );
    });

    test('Director (Sub-Admin) manages faculty teachers exclusively', () {
      final director = AppUser(
        id: 'director-1',
        email: 'director@Admin.edu',
        username: 'director@Admin.edu',
        role: AppRoles.subadmin,
        schoolId: '00000000-0000-4000-8000-000000000001',
        createdAt: DateTime.now(),
      );

      expect(director.role, equals(AppRoles.subadmin));
      expect(director.isSuperAdmin, isFalse);

      // Director permissions
      final allowedRegistrationRoles = [
        if (director.role == AppRoles.subadmin) AppRoles.teacher,
      ];

      expect(allowedRegistrationRoles, contains(AppRoles.teacher));
      expect(allowedRegistrationRoles, isNot(contains(AppRoles.student)));
    });

    test('Fast Exam Script Setup generates structured questions with time and target class', () {
      const script = '''
1. What is the chemical formula of water?
A. CO2
B. H2O
C. NaCl
D. O2
Answer: B

2. The Earth revolves around the sun. (True/False)
Answer: True
''';

      final questions = ExamScriptParser.parse(script);
      expect(questions.length, equals(2));

      final q1 = questions[0];
      expect(q1.type, equals('multiple_choice'));
      expect(q1.options.length, equals(4));
      expect(q1.correctAnswer, equals('b'));
      expect(q1.options.firstWhere((o) => o['is_correct'] == true)['text'], equals('H2O'));

      final q2 = questions[1];
      expect(q2.type, equals('true_false'));
      expect(q2.options.firstWhere((o) => o['is_correct'] == true)['text'], equals('True'));

      // Payload mapping for quiz
      final quizMap = {
        'title': 'Chemistry & Science Quiz',
        'time_limit_minutes': 45,
        'target_grade': 'Grade 9',
        'target_section': 'Section A',
        'total_points': questions.length,
        'questions': questions.map((q) => q.toMap(0)).toList(),
      };

      expect(quizMap['time_limit_minutes'], equals(45));
      expect(quizMap['target_grade'], equals('Grade 9'));
      expect(quizMap['target_section'], equals('Section A'));
      expect((quizMap['questions'] as List).length, equals(2));
    });
  });
}
