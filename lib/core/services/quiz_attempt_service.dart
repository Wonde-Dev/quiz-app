import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/services/audit_log_service.dart';
import 'package:quiz_app/shared/models/grade.dart';
import 'package:quiz_app/shared/models/question.dart';
import 'package:quiz_app/shared/models/quiz.dart';

class QuizAttemptData {
  const QuizAttemptData({required this.quiz, required this.questions});

  final Quiz quiz;
  final List<Question> questions;
}

class QuizSubmissionResult {
  const QuizSubmissionResult({required this.grade, required this.feedback});

  final Grade grade;
  final List<Map<String, dynamic>> feedback;
}

class QuizAttemptService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<QuizAttemptData> start(String quizId) async {
    final response = await _client.functions.invoke(
      'quiz-attempt',
      body: {'action': 'start', 'quizId': quizId},
    );
    final data = _requireMap(response.data);
    final quiz = data['quiz'];
    final questions = data['questions'];
    if (quiz is! Map<String, dynamic> || questions is! List) {
      throw const FormatException('Quiz service returned an invalid quiz');
    }
    await AuditLogService().logForCurrentUser(
      action: 'quiz_started',
      details: {
        'quiz_id': quizId,
        'quiz_title': quiz['title'] as String? ?? 'Quiz',
      },
    );
    return QuizAttemptData(
      quiz: Quiz.fromMap(quiz),
      questions: questions.map((question) {
        if (question is! Map<String, dynamic>) {
          throw const FormatException(
            'Quiz service returned an invalid question',
          );
        }
        return Question.fromMap(question);
      }).toList(),
    );
  }

  Future<QuizSubmissionResult> submit(
    String quizId,
    Map<String, dynamic> answers,
  ) async {
    final response = await _client.functions.invoke(
      'quiz-attempt',
      body: {'action': 'submit', 'quizId': quizId, 'answers': answers},
    );
    final data = _requireMap(response.data);
    final grade = data['grade'];
    if (grade is! Map<String, dynamic>) {
      throw const FormatException('Quiz service returned an invalid result');
    }
    final feedbackRaw = data['feedback'];
    if (feedbackRaw is! List ||
        feedbackRaw.any((entry) => entry is! Map<String, dynamic>)) {
      throw const FormatException('Quiz service returned invalid feedback');
    }
    return QuizSubmissionResult(
      grade: Grade.fromMap(grade),
      feedback: feedbackRaw.cast<Map<String, dynamic>>(),
    );
  }

  Map<String, dynamic> _requireMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    throw const FormatException('Quiz service returned an invalid response');
  }
}
