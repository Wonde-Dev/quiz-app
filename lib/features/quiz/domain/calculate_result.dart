import 'dart:convert';
import 'package:quiz_app/shared/models/question.dart';

/// Calculates the result of a quiz attempt, comparing student answers against
/// teacher answer keys for multiple choice, true/false, fill-in-blank, and descriptive items.
class CalculateResult {
  Map<String, dynamic> call({
    required List<Question> questions,
    required Map<String, dynamic> answers,
    int passingScorePercent = 60,
  }) {
    int score = 0;
    int totalPoints = 0;

    for (final q in questions) {
      totalPoints += q.points;
      final rawAnswer = answers[q.id];
      if (rawAnswer == null) continue;

      String extractedText = '';
      String? selectedOptionId;

      if (rawAnswer is String) {
        if (rawAnswer.trim().startsWith('{') && rawAnswer.trim().endsWith('}')) {
          try {
            final parsed = jsonDecode(rawAnswer) as Map<String, dynamic>;
            selectedOptionId = parsed['option_id'] as String? ?? parsed['selected'] as String?;
            extractedText = parsed['text'] as String? ?? selectedOptionId ?? '';
          } catch (_) {
            extractedText = rawAnswer;
            selectedOptionId = rawAnswer;
          }
        } else {
          extractedText = rawAnswer;
          selectedOptionId = rawAnswer;
        }
      } else if (rawAnswer is Map) {
        selectedOptionId = rawAnswer['option_id'] as String? ?? rawAnswer['selected'] as String?;
        extractedText = rawAnswer['text'] as String? ?? selectedOptionId ?? '';
      }

      bool isCorrect = false;

      if (q.type == 'multiple_choice' || q.type == 'true_false') {
        final correctOption = q.options.where((o) => o.isCorrect).firstOrNull;
        if (correctOption != null) {
          if (selectedOptionId != null &&
              selectedOptionId.toLowerCase().trim() == correctOption.id.toLowerCase().trim()) {
            isCorrect = true;
          } else if (extractedText.toLowerCase().trim() == correctOption.text.toLowerCase().trim()) {
            isCorrect = true;
          }
        }
      } else if (q.type == 'fill_in_blank' ||
          q.type == 'blank_space' ||
          q.type == 'short_answer') {
        if (q.correctAnswer != null && q.correctAnswer!.trim().isNotEmpty) {
          final normalizedStudent = extractedText
              .trim()
              .toLowerCase()
              .replaceAll(RegExp(r'[.,!?:;]+$'), '')
              .replaceAll(RegExp(r'\s+'), ' ');
          final normalizedTeacher = q.correctAnswer!
              .trim()
              .toLowerCase()
              .replaceAll(RegExp(r'[.,!?:;]+$'), '')
              .replaceAll(RegExp(r'\s+'), ' ');

          if (normalizedStudent == normalizedTeacher) {
            isCorrect = true;
          }
        }
      }

      if (isCorrect) score += q.points;
    }

    final percentage = totalPoints > 0
        ? ((score / totalPoints) * 100).round()
        : 0;
    final passed = percentage >= passingScorePercent;

    return {
      'score': score,
      'total_points': totalPoints,
      'percentage': percentage,
      'passed': passed,
    };
  }
}
