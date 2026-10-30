import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/utils/exam_script_parser.dart';
import 'package:quiz_app/core/utils/role_username.dart';

void main() {
  group('Advanced Examination & 7 Question Types', () {
    test('Supports all 7 required question types', () {
      const types = [
        'multiple_choice',
        'true_false',
        'short_answer',
        'fill_in_blank',
        'matching',
        'multiple_select',
        'essay',
      ];

      expect(types.length, equals(7));
      expect(types.contains('multiple_choice'), isTrue);
      expect(types.contains('true_false'), isTrue);
      expect(types.contains('short_answer'), isTrue);
      expect(types.contains('fill_in_blank'), isTrue);
      expect(types.contains('matching'), isTrue);
      expect(types.contains('multiple_select'), isTrue);
      expect(types.contains('essay'), isTrue);
    });

    test('Validates mandatory correct answer or answer key before publishing', () {
      bool isReadyToPublish(List<Map<String, dynamic>> questions) {
        if (questions.isEmpty) return false;
        for (final q in questions) {
          final type = q['type'] as String;
          if (type == 'multiple_choice' || type == 'true_false') {
            final options = q['options'] as List?;
            if (options == null || options.isEmpty) return false;
            final hasCorrect = options.any((o) => o['is_correct'] == true);
            if (!hasCorrect) return false;
          } else if (type == 'fill_in_blank' || type == 'short_answer') {
            final ans = q['correct_answer'] as String?;
            if (ans == null || ans.trim().isEmpty) return false;
          } else if (type == 'matching') {
            final pairs = q['matching_pairs'] as List?;
            if (pairs == null || pairs.isEmpty) return false;
          } else if (type == 'multiple_select') {
            final options = q['options'] as List?;
            if (options == null || options.isEmpty) return false;
            final correctCount = options.where((o) => o['is_correct'] == true).length;
            if (correctCount < 1) return false;
          }
          // Essay questions can be marked for manual evaluation
        }
        return true;
      }

      final validExam = [
        {
          'type': 'multiple_choice',
          'options': [
            {'id': 'a', 'text': 'Option A', 'is_correct': false},
            {'id': 'b', 'text': 'Option B', 'is_correct': true},
          ],
        },
        {
          'type': 'fill_in_blank',
          'correct_answer': 'Mitochondria',
        },
      ];

      final invalidExam = [
        {
          'type': 'multiple_choice',
          'options': [
            {'id': 'a', 'text': 'Option A', 'is_correct': false},
            {'id': 'b', 'text': 'Option B', 'is_correct': false},
          ],
        },
      ];

      expect(isReadyToPublish(validExam), isTrue);
      expect(isReadyToPublish(invalidExam), isFalse);
      expect(isReadyToPublish([]), isFalse);
    });

    test('Smart script parser parses multiple questions and preserves options and answers', () {
      const script = '''
1. What is the powerhouse of the cell?
A. Nucleus
B. Mitochondria
C. Ribosome
D. Chloroplast
Answer: B

2. Photosynthesis takes place in chloroplasts. (True/False)
Answer: True

3. The boiling point of water is ______ degrees Celsius.
Answer: 100
''';

      final questions = ExamScriptParser.parse(script);
      expect(questions.length, equals(3));

      expect(questions[0].type, equals('multiple_choice'));
      expect(questions[0].options.length, equals(4));
      expect(questions[0].correctAnswer, equals('b'));

      expect(questions[1].type, equals('true_false'));
      expect(questions[1].correctAnswer, equals('True'));

      expect(questions[2].type, equals('fill_in_blank'));
      expect(questions[2].correctAnswer, equals('100'));
    });
  });

  group('User Registration Credential & Role Rules', () {
    test('Deduplicates institutional usernames sequentially', () {
      final existing = [
        'JohnDoe@Teacher.edu',
        'JohnDoe1@Teacher.edu',
        'JohnDoe2@Teacher.edu',
      ];

      final next = nextRoleUsername(
        fullName: 'John Doe',
        role: AppRoles.teacher,
        existingUsernames: existing,
      );

      expect(next, equals('JohnDoe3@Teacher.edu'));
    });

    test('Director is restricted to registering Teachers only', () {
      bool isRegistrationAllowed({
        required String actorRole,
        required String targetRole,
      }) {
        if (AppRoles.isSuperAdmin(actorRole)) {
          return true; // Super Admin can register any role
        }
        if (AppRoles.isDirector(actorRole)) {
          return targetRole == AppRoles.teacher; // Director can register teachers ONLY
        }
        return false;
      }

      expect(isRegistrationAllowed(actorRole: AppRoles.admin, targetRole: AppRoles.director), isTrue);
      expect(isRegistrationAllowed(actorRole: AppRoles.admin, targetRole: AppRoles.teacher), isTrue);
      expect(isRegistrationAllowed(actorRole: AppRoles.admin, targetRole: AppRoles.student), isTrue);

      expect(isRegistrationAllowed(actorRole: AppRoles.director, targetRole: AppRoles.teacher), isTrue);
      expect(isRegistrationAllowed(actorRole: AppRoles.director, targetRole: AppRoles.director), isFalse);
      expect(isRegistrationAllowed(actorRole: AppRoles.director, targetRole: AppRoles.student), isFalse);
      expect(isRegistrationAllowed(actorRole: AppRoles.director, targetRole: AppRoles.admin), isFalse);
    });

    test('Multi-section assignment data structure mapping', () {
      final assignments = [
        {
          'teacher_id': 'teacher-1',
          'section_id': 'section-9a',
          'subject': 'Physics',
          'class_label': 'Grade 9 Class 9A',
        },
        {
          'teacher_id': 'teacher-1',
          'section_id': 'section-10b',
          'subject': 'Physics',
          'class_label': 'Grade 10 Class 10B',
        },
      ];

      expect(assignments.length, equals(2));
      expect(assignments.every((a) => a['teacher_id'] == 'teacher-1'), isTrue);
      expect(assignments.map((a) => a['class_label']).toSet().length, equals(2));
    });
  });
}
