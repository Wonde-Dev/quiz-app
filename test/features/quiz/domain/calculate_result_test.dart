import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/features/quiz/domain/calculate_result.dart';
import 'package:quiz_app/shared/models/question.dart';

void main() {
  const questions = [
    Question(
      id: 'true-false',
      quizId: 'quiz',
      text: 'The Earth orbits the Sun.',
      type: 'true_false',
      options: [
        Option(id: 'a', text: 'True', isCorrect: true),
        Option(id: 'b', text: 'False'),
      ],
    ),
    Question(
      id: 'blank',
      quizId: 'quiz',
      text: 'The largest planet is ____.',
      type: 'short_answer',
      correctAnswer: 'Jupiter',
    ),
  ];

  test('scores true-false and fill-in-the-blank answers', () {
    final result = CalculateResult()(
      questions: questions,
      answers: {'true-false': 'a', 'blank': ' jUpItEr '},
    );

    expect(result['score'], 2);
    expect(result['total_points'], 2);
    expect(result['percentage'], 100);
    expect(result['passed'], isTrue);
  });

  test('marks an incorrect fill-in-the-blank answer wrong', () {
    final result = CalculateResult()(
      questions: questions,
      answers: {'true-false': 'b', 'blank': 'Saturn'},
    );

    expect(result['score'], 0);
    expect(result['percentage'], 0);
    expect(result['passed'], isFalse);
  });
}
