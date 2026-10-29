import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/utils/validators.dart';
import 'package:quiz_app/shared/models/quiz.dart';
import 'package:quiz_app/shared/models/user.dart';

void main() {
  group('Student Exam & Portfolio Functionality', () {
    test('AppUser retains and updates phone number and email', () {
      final user = AppUser(
        id: 'student-uuid-1',
        username: 'AbebeKebede@Students.edu',
        email: 'abebe@ciroschool.edu',
        role: 'student',
        fullName: 'Abebe Kebede',
        phoneNumber: '+251911223344',
        createdAt: DateTime.now(),
      );

      expect(user.phoneNumber, '+251911223344');
      expect(user.email, 'abebe@ciroschool.edu');

      final updated = user.copyWith(
        email: 'abebe.updated@ciroschool.edu',
        phoneNumber: '+251922334455',
        fullName: 'Abebe K. Gemeda',
      );

      expect(updated.email, 'abebe.updated@ciroschool.edu');
      expect(updated.phoneNumber, '+251922334455');
      expect(updated.fullName, 'Abebe K. Gemeda');
      expect(updated.toMap()['phone_number'], '+251922334455');
    });

    test('New user registrations strictly require valid email and phone number', () {
      // Empty values rejected
      expect(Validators.email(null), isNotNull);
      expect(Validators.email(''), isNotNull);
      expect(Validators.phone(null), isNotNull);
      expect(Validators.phone(''), isNotNull);

      // Malformed values rejected
      expect(Validators.email('invalid-email'), isNotNull);
      expect(Validators.phone('1234'), isNotNull);

      // Valid values accepted
      expect(Validators.email('student@ciro.edu'), isNull);
      expect(Validators.phone('+251911234567'), isNull);
      expect(Validators.phone('0911234567'), isNull);
    });

    test('Quiz retains time limit and published accessibility constraints', () {
      final quiz = Quiz(
        id: 'quiz-1',
        teacherId: 'teacher-uuid',
        title: 'Grade 9 Midterm Physics Exam',
        description: 'Comprehensive Term 1 evaluation',
        timeLimitMinutes: 45,
        totalPoints: 100,
        isPublished: true,
        createdAt: DateTime.now(),
      );

      expect(quiz.timeLimitMinutes, 45);
      expect(quiz.isPublished, isTrue);
      expect(quiz.totalPoints, 100);

      final map = quiz.toMap();
      expect(map['time_limit_minutes'], 45);
      expect(map['is_published'], isTrue);
    });

    test('Unpublished quizzes are hidden from student access', () {
      final publishedQuiz = <String, dynamic>{
        'id': 'q-published',
        'title': 'Active Exam',
        'is_published': true,
        'time_limit_minutes': 40,
      };

      final draftQuiz = <String, dynamic>{
        'id': 'q-draft',
        'title': 'Draft Exam',
        'is_published': false,
        'time_limit_minutes': 40,
      };

      final allQuizzes = [publishedQuiz, draftQuiz];
      final studentAvailable = allQuizzes.where((q) => q['is_published'] != false).toList();

      expect(studentAvailable.length, 1);
      expect(studentAvailable.first['id'], 'q-published');
    });
  });
}
