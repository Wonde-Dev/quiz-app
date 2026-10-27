import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/utils/exam_script_parser.dart';

void main() {
  group('ExamScriptParser', () {
    test('parses sample script covering choose, true/false, blank space, and description', () {
      final questions = ExamScriptParser.parse(ExamScriptParser.sampleScript);

      expect(questions.length, 4);

      // 1. Choose (Multiple choice)
      final q1 = questions[0];
      expect(q1.type, 'multiple_choice');
      expect(q1.text, contains('powerhouse of the cell'));
      expect(q1.options.length, 4);
      final correctOpt1 = q1.options.firstWhere((o) => o['is_correct'] == true);
      expect(correctOpt1['id'], 'b');
      expect(correctOpt1['text'], 'Mitochondria');
      expect(q1.explanation, contains('ATP supply'));

      // 2. True / False
      final q2 = questions[1];
      expect(q2.type, 'true_false');
      expect(q2.text, contains('Photosynthesis takes place in animal cells'));
      expect(q2.options.length, 2);
      final correctOpt2 = q2.options.firstWhere((o) => o['is_correct'] == true);
      expect(correctOpt2['text'], 'False');

      // 3. Blank space (Fill in the blank)
      final q3 = questions[2];
      expect(q3.type, 'fill_in_blank');
      expect(q3.text, contains('freezes at ______ degrees'));
      expect(q3.correctAnswer, '0');

      // 4. Description (Short answer / essay)
      final q4 = questions[3];
      expect(q4.type, 'short_answer');
      expect(q4.text, contains('Describe Newton\'s Third Law'));
      expect(q4.correctAnswer, contains('equal and opposite reaction'));
    });

    test('extracts embedded diagram and image URLs from script', () {
      const scriptWithImage = '''
1. Calculate the area of the shaded region in the figure below:
[image: https://example.com/geometry_diagram.png]
A. 24 cm^2
B. 36 cm^2
C. 48 cm^2
Answer: B
''';

      final questions = ExamScriptParser.parse(scriptWithImage);
      expect(questions.length, 1);
      expect(questions.first.imageUrl, 'https://example.com/geometry_diagram.png');
      expect(questions.first.type, 'multiple_choice');
      expect(questions.first.options.length, 3);
    });

    test('merges separate answer key script into questions', () {
      const questionsOnly = '''
1. What is the currency of Japan?
A. Yuan
B. Won
C. Yen
D. Ringgit

2. The Great Wall of China is visible from the moon without aid. (True/False)

3. The capital of Ethiopia is ______ Ababa.
''';

      const separateKey = '''
1. C
2. False
3. Addis
''';

      final questions = ExamScriptParser.parse(questionsOnly, answerKeyScript: separateKey);
      expect(questions.length, 3);

      expect(questions[0].type, 'multiple_choice');
      final correct1 = questions[0].options.firstWhere((o) => o['is_correct'] == true);
      expect(correct1['id'], 'c');
      expect(correct1['text'], 'Yen');

      expect(questions[1].type, 'true_false');
      final correct2 = questions[1].options.firstWhere((o) => o['is_correct'] == true);
      expect(correct2['text'], 'False');

      expect(questions[2].type, 'fill_in_blank');
      expect(questions[2].correctAnswer, 'Addis');
    });
  });
}

