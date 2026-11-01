import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/services/quiz_attempt_service.dart';

void main() {
  group('Exam Evaluation and Grading System', () {
    test('Evaluates multiple choice questions accurately by option ID and text', () {
      final question = {
        'id': 'q1',
        'type': 'multiple_choice',
        'text': 'Which organelle is the powerhouse of the cell?',
        'options': [
          {'id': 'a', 'text': 'Nucleus', 'is_correct': false},
          {'id': 'b', 'text': 'Mitochondria', 'is_correct': true},
          {'id': 'c', 'text': 'Ribosome', 'is_correct': false},
          {'id': 'd', 'text': 'Chloroplast', 'is_correct': false},
        ],
        'correct_answer': null,
      };

      // Match by option id
      expect(QuizAttemptService.evaluateQuestionAnswer(question, 'b'), isTrue);
      expect(QuizAttemptService.evaluateQuestionAnswer(question, 'B'), isTrue);
      expect(QuizAttemptService.evaluateQuestionAnswer(question, 'a'), isFalse);

      // Match by option text
      expect(QuizAttemptService.evaluateQuestionAnswer(question, 'Mitochondria'), isTrue);
      expect(QuizAttemptService.evaluateQuestionAnswer(question, 'mitochondria'), isTrue);
      expect(QuizAttemptService.evaluateQuestionAnswer(question, 'Nucleus'), isFalse);

      // Match with attached work JSON
      final withWork = jsonEncode({
        'option_id': 'b',
        'image_url': 'https://example.com/calculation.png',
      });
      expect(QuizAttemptService.evaluateQuestionAnswer(question, withWork), isTrue);

      final withWorkWrong = jsonEncode({
        'option_id': 'c',
        'image_url': 'https://example.com/calculation.png',
      });
      expect(QuizAttemptService.evaluateQuestionAnswer(question, withWorkWrong), isFalse);
    });

    test('Evaluates True/False questions accurately with synonyms', () {
      final questionTrue = {
        'id': 'q2',
        'type': 'true_false',
        'text': 'Water boils at 100 degrees Celsius under standard atmospheric pressure.',
        'options': [
          {'id': 'a', 'text': 'True', 'is_correct': true},
          {'id': 'b', 'text': 'False', 'is_correct': false},
        ],
      };

      expect(QuizAttemptService.evaluateQuestionAnswer(questionTrue, 'a'), isTrue);
      expect(QuizAttemptService.evaluateQuestionAnswer(questionTrue, 'True'), isTrue);
      expect(QuizAttemptService.evaluateQuestionAnswer(questionTrue, 'true'), isTrue);
      expect(QuizAttemptService.evaluateQuestionAnswer(questionTrue, 't'), isTrue);
      expect(QuizAttemptService.evaluateQuestionAnswer(questionTrue, '1'), isTrue);
      expect(QuizAttemptService.evaluateQuestionAnswer(questionTrue, 'False'), isFalse);
      expect(QuizAttemptService.evaluateQuestionAnswer(questionTrue, 'b'), isFalse);

      final questionFalse = {
        'id': 'q3',
        'type': 'true_false',
        'text': 'Photosynthesis takes place in animal cells.',
        'options': [
          {'id': 'a', 'text': 'True', 'is_correct': false},
          {'id': 'b', 'text': 'False', 'is_correct': true},
        ],
      };

      expect(QuizAttemptService.evaluateQuestionAnswer(questionFalse, 'b'), isTrue);
      expect(QuizAttemptService.evaluateQuestionAnswer(questionFalse, 'False'), isTrue);
      expect(QuizAttemptService.evaluateQuestionAnswer(questionFalse, 'false'), isTrue);
      expect(QuizAttemptService.evaluateQuestionAnswer(questionFalse, 'f'), isTrue);
      expect(QuizAttemptService.evaluateQuestionAnswer(questionFalse, '0'), isTrue);
      expect(QuizAttemptService.evaluateQuestionAnswer(questionFalse, 'True'), isFalse);
    });

    test('Evaluates Fill in the Blank and Blank Space questions with normalization and alternatives', () {
      final questionBlank = {
        'id': 'q4',
        'type': 'fill_in_blank',
        'text': 'Pure water freezes at ______ degrees Celsius under normal pressure.',
        'options': [],
        'correct_answer': '0, zero',
      };

      // Numeric answer
      expect(QuizAttemptService.evaluateQuestionAnswer(questionBlank, '0'), isTrue);
      // Alternative word answer
      expect(QuizAttemptService.evaluateQuestionAnswer(questionBlank, 'zero'), isTrue);
      expect(QuizAttemptService.evaluateQuestionAnswer(questionBlank, 'Zero'), isTrue);
      // Extra punctuation
      expect(QuizAttemptService.evaluateQuestionAnswer(questionBlank, '0.'), isTrue);
      expect(QuizAttemptService.evaluateQuestionAnswer(questionBlank, ' zero! '), isTrue);
      // Wrong answer
      expect(QuizAttemptService.evaluateQuestionAnswer(questionBlank, '100'), isFalse);

      // Slash-separated alternatives
      final questionSlash = {
        'id': 'q5',
        'type': 'blank_space',
        'text': 'Plant cells have an outer rigid ______ for structure.',
        'options': [],
        'correct_answer': 'cell wall / cellulose wall',
      };

      expect(QuizAttemptService.evaluateQuestionAnswer(questionSlash, 'cell wall'), isTrue);
      expect(QuizAttemptService.evaluateQuestionAnswer(questionSlash, 'Cell Wall'), isTrue);
      expect(QuizAttemptService.evaluateQuestionAnswer(questionSlash, 'cellulose wall'), isTrue);
      expect(QuizAttemptService.evaluateQuestionAnswer(questionSlash, 'plasma membrane'), isFalse);
    });

    test('Evaluates Short Answer and Description with text and diagrams', () {
      final questionDesc = {
        'id': 'q6',
        'type': 'description',
        'text': 'State Newton\'s First Law of Motion in one sentence.',
        'options': [],
        'correct_answer': 'An object at rest stays at rest and an object in motion stays in motion unless acted upon by an unbalanced force.',
      };

      // Exact match with whitespace differences
      expect(
        QuizAttemptService.evaluateQuestionAnswer(
          questionDesc,
          '  An object at rest stays at rest and an object in motion stays in motion unless acted upon by an unbalanced force.  ',
        ),
        isTrue,
      );

      // Answer inside JSON payload with attached image
      final answerJson = jsonEncode({
        'text': 'An object at rest stays at rest and an object in motion stays in motion unless acted upon by an unbalanced force',
        'image_url': 'https://example.com/free_body_diagram.png',
      });
      expect(QuizAttemptService.evaluateQuestionAnswer(questionDesc, answerJson), isTrue);

      expect(QuizAttemptService.evaluateQuestionAnswer(questionDesc, 'Gravity attracts objects.'), isFalse);
    });

    test('Evaluates numeric equivalence correctly', () {
      final qNumeric = {
        'id': 'q7',
        'type': 'short_answer',
        'text': 'What is the probability of flipping heads on a fair coin?',
        'options': [],
        'correct_answer': '0.5, 1/2',
      };

      expect(QuizAttemptService.evaluateQuestionAnswer(qNumeric, '0.5'), isTrue);
      expect(QuizAttemptService.evaluateQuestionAnswer(qNumeric, '.5'), isTrue);
      expect(QuizAttemptService.evaluateQuestionAnswer(qNumeric, '0.50'), isTrue);
    });
  });
}

