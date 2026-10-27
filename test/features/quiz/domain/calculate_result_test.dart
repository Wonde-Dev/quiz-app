import 'dart:convert';
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
      type: 'fill_in_blank',
      correctAnswer: 'Jupiter',
    ),
    Question(
      id: 'choose',
      quizId: 'quiz',
      text: 'Which organelle is powerhouse of cell?',
      type: 'multiple_choice',
      options: [
        Option(id: 'a', text: 'Nucleus'),
        Option(id: 'b', text: 'Mitochondria', isCorrect: true),
      ],
    ),
    Question(
      id: 'desc',
      quizId: 'quiz',
      text: 'Describe photosynthesis.',
      type: 'short_answer',
      correctAnswer: 'Plants convert light into chemical energy',
    ),
  ];

  test('scores true-false, fill-in-the-blank, multiple-choice, and descriptive answers', () {
    final result = CalculateResult()(
      questions: questions,
      answers: {
        'true-false': 'a',
        'blank': ' jUpItEr. ',
        'choose': 'b',
        'desc': 'Plants convert light into chemical energy',
      },
    );

    expect(result['score'], 4);
    expect(result['total_points'], 4);
    expect(result['percentage'], 100);
    expect(result['passed'], isTrue);
  });

  test('handles JSON-encoded answers with student attached work/image', () {
    final jsonAnswer = jsonEncode({
      'text': 'Jupiter',
      'image_url': 'https://storage.supabase.com/handwritten_calc.jpg',
    });

    final result = CalculateResult()(
      questions: questions,
      answers: {
        'true-false': 'True',
        'blank': jsonAnswer,
        'choose': jsonEncode({'option_id': 'b', 'image_url': 'https://img.jpg'}),
        'desc': 'Plants convert light into chemical energy.',
      },
    );

    expect(result['score'], 4);
    expect(result['percentage'], 100);
  });

  test('marks incorrect answers wrong', () {
    final result = CalculateResult()(
      questions: questions,
      answers: {
        'true-false': 'b',
        'blank': 'Saturn',
        'choose': 'a',
        'desc': 'Wrong explanation',
      },
    );

    expect(result['score'], 0);
    expect(result['percentage'], 0);
    expect(result['passed'], isFalse);
  });
}
