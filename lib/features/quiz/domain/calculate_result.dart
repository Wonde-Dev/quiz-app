import 'package:quiz_app/shared/models/question.dart';

/// Calculates the result of a quiz attempt.
class CalculateResult {
  /// Returns a [Grade]-like map with score, totalPoints, percentage, passed.
  /// [passingScorePercent] defaults to 60.
  Map<String, dynamic> call({
    required List<Question> questions,
    required Map<String, dynamic> answers,
    int passingScorePercent = 60,
  }) {
    int score = 0;
    int totalPoints = 0;

    for (final q in questions) {
      totalPoints += q.points;
      final userAnswer = answers[q.id];
      if (userAnswer == null) continue;

      bool isCorrect = false;
      if (q.type == 'multiple_choice' || q.type == 'true_false') {
        // Find the correct option
        final correctOption = q.options.where((o) => o.isCorrect).firstOrNull;
        if (correctOption != null && userAnswer == correctOption.id) {
          isCorrect = true;
        }
      } else if (q.type == 'short_answer') {
        if (q.correctAnswer != null &&
            userAnswer.toString().toLowerCase().trim() ==
                q.correctAnswer!.toLowerCase().trim()) {
          isCorrect = true;
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
