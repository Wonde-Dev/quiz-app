import 'dart:convert';
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
    // 1. Try edge function
    try {
      final response = await _client.functions.invoke(
        'quiz-attempt',
        body: {'action': 'start', 'quizId': quizId},
      );
      final data = _requireMap(response.data);
      final quiz = data['quiz'];
      final questions = data['questions'];
      if (quiz is Map<String, dynamic> && questions is List && questions.isNotEmpty) {
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
            return Question.fromMap(Map<String, dynamic>.from(question as Map));
          }).toList(),
        );
      }
    } catch (_) {}

    // 2. Try get_quiz_attempt_data RPC function
    try {
      final rpcRes = await _client.rpc(
        'get_quiz_attempt_data',
        params: {'p_quiz_id': quizId},
      );
      if (rpcRes is Map) {
        final data = Map<String, dynamic>.from(rpcRes);
        final quiz = data['quiz'];
        final questions = data['questions'];
        if (quiz is Map && questions is List && questions.isNotEmpty) {
          return QuizAttemptData(
            quiz: Quiz.fromMap(Map<String, dynamic>.from(quiz)),
            questions: questions.map((q) {
              return Question.fromMap(Map<String, dynamic>.from(q as Map));
            }).toList(),
          );
        }
      }
    } catch (_) {}

    return _fallbackStart(quizId);
  }

  Future<QuizAttemptData> _fallbackStart(String quizId) async {
    final quizRow = await _client
        .from('quizzes')
        .select()
        .eq('id', quizId)
        .single();
    final qRows = await _client
        .from('questions')
        .select()
        .eq('quiz_id', quizId)
        .order('order', ascending: true);

    final questions = List<Map<String, dynamic>>.from(qRows).map((q) {
      return Question.fromMap({
        ...q,
        'correct_answer': null,
        'explanation': null,
      });
    }).toList();

    return QuizAttemptData(
      quiz: Quiz.fromMap(quizRow),
      questions: questions,
    );
  }

  Future<QuizSubmissionResult> submit(
    String quizId,
    Map<String, dynamic> answers,
  ) async {
    try {
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
      final enriched = await _enrichFeedback(
        quizId,
        answers,
        feedbackRaw.cast<Map<String, dynamic>>(),
      );
      return QuizSubmissionResult(
        grade: Grade.fromMap(grade),
        feedback: enriched,
      );
    } catch (_) {
      return _fallbackSubmit(quizId, answers);
    }
  }

  Future<QuizSubmissionResult> _fallbackSubmit(
    String quizId,
    Map<String, dynamic> answers,
  ) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('User not logged in');

    // 1. Fetch questions
    final qRows = await _client
        .from('questions')
        .select()
        .eq('quiz_id', quizId)
        .order('order', ascending: true);
    final questions = List<Map<String, dynamic>>.from(qRows);

    int score = 0;
    int totalPoints = 0;
    int incorrectAnswers = 0;
    final feedback = <Map<String, dynamic>>[];

    for (final q in questions) {
      final points = (q['points'] as num?)?.toInt() ?? 1;
      totalPoints += points;
      final rawAns = answers[q['id']];
      bool isCorrect = false;

      if (q['type'] == 'multiple_choice' || q['type'] == 'true_false') {
        final options = q['options'] as List?;
        String? selectedOptionId;
        if (rawAns is String) {
          if (rawAns.trim().startsWith('{') && rawAns.trim().endsWith('}')) {
            try {
              final parsed = jsonDecode(rawAns) as Map<String, dynamic>;
              selectedOptionId = parsed['option_id'] as String? ??
                  parsed['selected'] as String? ??
                  parsed['text'] as String?;
            } catch (_) {
              selectedOptionId = rawAns;
            }
          } else {
            selectedOptionId = rawAns;
          }
        } else if (rawAns is Map) {
          selectedOptionId = rawAns['option_id'] as String? ??
              rawAns['selected'] as String? ??
              rawAns['text'] as String?;
        }
        if (options != null) {
          final correctOpt = options.firstWhere(
            (o) => o is Map && o['is_correct'] == true,
            orElse: () => null,
          );
          isCorrect = correctOpt != null && selectedOptionId == correctOpt['id'];
        }
      } else if (q['type'] == 'short_answer' ||
          q['type'] == 'fill_in_blank' ||
          q['type'] == 'blank_space' ||
          q['type'] == 'description') {
        final cAns = q['correct_answer'] as String?;
        String textVal = '';
        if (rawAns is String) {
          try {
            final parsed = jsonDecode(rawAns);
            if (parsed is Map && parsed.containsKey('text')) {
              textVal = parsed['text']?.toString() ?? '';
            } else {
              textVal = rawAns;
            }
          } catch (_) {
            textVal = rawAns;
          }
        } else if (rawAns is Map && rawAns.containsKey('text')) {
          textVal = rawAns['text']?.toString() ?? '';
        } else {
          textVal = rawAns?.toString() ?? '';
        }
        if (cAns != null && cAns.trim().isNotEmpty) {
          final normStudent = textVal
              .trim()
              .toLowerCase()
              .replaceAll(RegExp(r'[.,!?:;]+$'), '')
              .replaceAll(RegExp(r'\s+'), ' ');
          final normTeacher = cAns
              .trim()
              .toLowerCase()
              .replaceAll(RegExp(r'[.,!?:;]+$'), '')
              .replaceAll(RegExp(r'\s+'), ' ');
          isCorrect = normStudent == normTeacher;
        }
      }

      if (isCorrect) {
        score += points;
      } else {
        incorrectAnswers++;
      }
      final options = q['options'] as List?;
      final correctOpt = (options != null)
          ? options.firstWhere(
              (o) => o is Map && o['is_correct'] == true,
              orElse: () => null,
            )
          : null;
      feedback.add({
        'questionId': q['id'],
        'question': q['text'] ?? 'Question',
        'type': q['type'],
        'options': q['options'],
        'selectedAnswer': rawAns,
        'correctAnswer': q['type'] == 'short_answer'
            ? q['correct_answer']
            : correctOpt?['id'],
        'correctAnswerText': q['type'] == 'short_answer'
            ? q['correct_answer']
            : correctOpt?['text'],
        'explanation': q['explanation'],
        'isCorrect': isCorrect,
        'points': points,
      });
    }

    final percentage =
        totalPoints > 0 ? ((score / totalPoints) * 100).round() : 0;

    // 2. Insert Grade
    final gradeRow = await _client
        .from('grades')
        .insert({
          'student_id': user.id,
          'quiz_id': quizId,
          'score': score,
          'total_points': totalPoints,
          'incorrect_answers': incorrectAnswers,
          'percentage': percentage,
          'passed': percentage >= 50,
          'submitted_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    // 3. Upsert attempt & insert answers
    try {
      final attemptRow = await _client
          .from('quiz_attempts')
          .upsert({
            'quiz_id': quizId,
            'student_id': user.id,
            'submitted_at': DateTime.now().toIso8601String(),
            'score': score,
          }, onConflict: 'quiz_id,student_id')
          .select('id')
          .maybeSingle();

      final attemptId = attemptRow?['id'] as String?;
      if (attemptId != null) {
        final answersToInsert = questions.map((q) {
          final rawAns = answers[q['id']];
          final answerText = rawAns is Map
              ? jsonEncode(rawAns)
              : (rawAns?.toString() ?? '');
          final fb = feedback.firstWhere(
            (f) => f['question'] == q['text'],
            orElse: () => {'isCorrect': false},
          );
          return {
            'attempt_id': attemptId,
            'question_id': q['id'],
            'answer_text': answerText,
            'is_correct': fb['isCorrect'] == true,
          };
        }).toList();
        await _client.from('answers').insert(answersToInsert);
      }
    } catch (_) {}

    return QuizSubmissionResult(
      grade: Grade.fromMap(gradeRow),
      feedback: feedback,
    );
  }

  Future<List<Map<String, dynamic>>> _enrichFeedback(
    String quizId,
    Map<String, dynamic> answers,
    List<Map<String, dynamic>> rawFeedback,
  ) async {
    try {
      final qRows = await _client
          .from('questions')
          .select('id, text, type, options, correct_answer, points, explanation')
          .eq('quiz_id', quizId)
          .order('order', ascending: true);
      final questions = List<Map<String, dynamic>>.from(qRows);
      if (questions.isEmpty) return rawFeedback;

      return questions.map((q) {
        final rawAns = answers[q['id']];
        final fb = rawFeedback.firstWhere(
          (f) => f['question'] == q['text'] || f['questionId'] == q['id'],
          orElse: () => <String, dynamic>{},
        );
        final options = q['options'] as List?;
        final correctOpt = (options != null)
            ? options.firstWhere(
                (o) => o is Map && o['is_correct'] == true,
                orElse: () => null,
              )
            : null;
        return {
          'questionId': q['id'],
          'question': q['text'] ?? 'Question',
          'type': q['type'],
          'options': q['options'],
          'selectedAnswer': rawAns,
          'correctAnswer': q['type'] == 'short_answer'
              ? q['correct_answer']
              : correctOpt?['id'],
          'correctAnswerText': q['type'] == 'short_answer'
              ? q['correct_answer']
              : correctOpt?['text'],
          'explanation': q['explanation'] ?? fb['explanation'],
          'isCorrect': fb['isCorrect'] ?? false,
          'points': (q['points'] as num?)?.toInt() ?? 1,
        };
      }).toList();
    } catch (_) {
      return rawFeedback;
    }
  }

  Map<String, dynamic> _requireMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    throw const FormatException('Quiz service returned an invalid response');
  }
}
