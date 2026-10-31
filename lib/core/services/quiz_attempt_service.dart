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

  /// Robust evaluation of student answers against teacher answer keys for all question types.
  static bool evaluateQuestionAnswer(Map<String, dynamic> q, dynamic rawAns) {
    if (rawAns == null) return false;
    final type = (q['type'] as String? ?? 'multiple_choice').toLowerCase();

    // 1. Multiple Choice / True-False
    if (type == 'multiple_choice' || type == 'true_false') {
      final options = (q['options'] as List?)?.cast<dynamic>() ?? [];
      final correctOpt = options.firstWhere(
        (o) => o is Map && o['is_correct'] == true,
        orElse: () => null,
      );

      String studentChoice = '';
      if (rawAns is String) {
        if (rawAns.trim().startsWith('{') && rawAns.trim().endsWith('}')) {
          try {
            final parsed = jsonDecode(rawAns) as Map<String, dynamic>;
            studentChoice = (parsed['option_id'] ?? parsed['selected'] ?? parsed['text'] ?? '').toString();
          } catch (_) {
            studentChoice = rawAns;
          }
        } else {
          studentChoice = rawAns;
        }
      } else if (rawAns is Map) {
        studentChoice = (rawAns['option_id'] ?? rawAns['selected'] ?? rawAns['text'] ?? '').toString();
      } else {
        studentChoice = rawAns.toString();
      }

      final normStudent = studentChoice.trim().toLowerCase();
      if (normStudent.isEmpty) return false;

      // Check matching option in options list
      if (correctOpt != null && correctOpt is Map) {
        final optId = (correctOpt['id'] ?? '').toString().trim().toLowerCase();
        final optText = (correctOpt['text'] ?? '').toString().trim().toLowerCase();

        if (normStudent == optId || normStudent == optText) {
          return true;
        }

        // True/False synonyms
        if (type == 'true_false') {
          final isOptTrue = optText == 'true' || optId == 'true' || optId == 't' || optId == '1';
          final isOptFalse = optText == 'false' || optId == 'false' || optId == 'f' || optId == '0';
          final isStudentTrue = normStudent == 'true' || normStudent == 't' || normStudent == 'yes' || normStudent == '1';
          final isStudentFalse = normStudent == 'false' || normStudent == 'f' || normStudent == 'no' || normStudent == '0';

          if (isOptTrue && isStudentTrue) return true;
          if (isOptFalse && isStudentFalse) return true;
        }
      }

      // Check if student matched any option whose is_correct is true
      for (final opt in options) {
        if (opt is Map && opt['is_correct'] == true) {
          final optId = (opt['id'] ?? '').toString().trim().toLowerCase();
          final optText = (opt['text'] ?? '').toString().trim().toLowerCase();
          if (normStudent == optId || normStudent == optText) {
            return true;
          }
        }
      }

      // If correct_answer string was given directly on question
      final cAns = (q['correct_answer'] as String?)?.trim().toLowerCase();
      if (cAns != null && cAns.isNotEmpty) {
        if (normStudent == cAns) return true;
        for (final opt in options) {
          if (opt is Map) {
            final optId = (opt['id'] ?? '').toString().trim().toLowerCase();
            final optText = (opt['text'] ?? '').toString().trim().toLowerCase();
            if ((normStudent == optId || normStudent == optText) && (cAns == optId || cAns == optText)) {
              return true;
            }
          }
        }
        if (type == 'true_false') {
          final isAnsTrue = cAns == 'true' || cAns == 't' || cAns == '1';
          final isAnsFalse = cAns == 'false' || cAns == 'f' || cAns == '0';
          final isStudentTrue = normStudent == 'true' || normStudent == 't' || normStudent == 'yes' || normStudent == '1';
          final isStudentFalse = normStudent == 'false' || normStudent == 'f' || normStudent == 'no' || normStudent == '0';
          if (isAnsTrue && isStudentTrue) return true;
          if (isAnsFalse && isStudentFalse) return true;
        }
      }

      return false;
    }

    // 2. Short answer / Fill in the blank / Blank space / Description
    String textVal = '';
    if (rawAns is String) {
      if (rawAns.trim().startsWith('{') && rawAns.trim().endsWith('}')) {
        try {
          final parsed = jsonDecode(rawAns) as Map<String, dynamic>;
          textVal = (parsed['text'] ?? '').toString();
        } catch (_) {
          textVal = rawAns;
        }
      } else {
        textVal = rawAns;
      }
    } else if (rawAns is Map) {
      textVal = (rawAns['text'] ?? '').toString();
    } else {
      textVal = rawAns.toString();
    }

    final normStudent = textVal
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[.,!?:;]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ');

    if (normStudent.isEmpty) return false;

    final cAns = (q['correct_answer'] as String?)?.trim();
    if (cAns != null && cAns.isNotEmpty && cAns != 'Teacher manual evaluation') {
      final alternatives = cAns
          .split(RegExp(r'[,;/|]'))
          .map((a) => a.trim().toLowerCase().replaceAll(RegExp(r'[.,!?:;]+$'), '').replaceAll(RegExp(r'\s+'), ' '))
          .where((a) => a.isNotEmpty)
          .toList();

      final fullNormTeacher = cAns
          .toLowerCase()
          .replaceAll(RegExp(r'[.,!?:;]+$'), '')
          .replaceAll(RegExp(r'\s+'), ' ');

      if (normStudent == fullNormTeacher || alternatives.contains(normStudent)) {
        return true;
      }

      // Check numeric equivalence (e.g. "0" == "0.0")
      final numStudent = num.tryParse(normStudent);
      final numTeacher = num.tryParse(fullNormTeacher);
      if (numStudent != null && numTeacher != null && numStudent == numTeacher) {
        return true;
      }
      for (final alt in alternatives) {
        final numAlt = num.tryParse(alt);
        if (numStudent != null && numAlt != null && numStudent == numAlt) {
          return true;
        }
      }
    }

    // Check accepted_answers JSONB array if present
    final accepted = q['accepted_answers'];
    if (accepted is List) {
      for (final a in accepted) {
        final normA = a.toString().trim().toLowerCase().replaceAll(RegExp(r'[.,!?:;]+$'), '').replaceAll(RegExp(r'\s+'), ' ');
        if (normStudent == normA) return true;
        final numA = num.tryParse(normA);
        final numStudent = num.tryParse(normStudent);
        if (numStudent != null && numA != null && numStudent == numA) return true;
      }
    }

    return false;
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
      final isCorrect = evaluateQuestionAnswer(q, rawAns);

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

      final isTextQ = q['type'] == 'short_answer' ||
          q['type'] == 'fill_in_blank' ||
          q['type'] == 'blank_space' ||
          q['type'] == 'description';

      feedback.add({
        'questionId': q['id'],
        'question': q['text'] ?? 'Question',
        'type': q['type'],
        'options': q['options'],
        'selectedAnswer': rawAns,
        'correctAnswer': isTextQ
            ? q['correct_answer']
            : (correctOpt?['id'] ?? q['correct_answer']),
        'correctAnswerText': isTextQ
            ? q['correct_answer']
            : (correctOpt?['text'] ?? q['correct_answer']),
        'explanation': q['explanation'],
        'isCorrect': isCorrect,
        'points': points,
      });
    }

    final percentage =
        totalPoints > 0 ? ((score / totalPoints) * 100).round() : 0;
    final passed = percentage >= 50;

    // Build structured answer list for database persistence
    final answersList = questions.map((q) {
      final rawAns = answers[q['id']];
      final answerText = rawAns is Map
          ? jsonEncode(rawAns)
          : (rawAns?.toString() ?? '');
      final fb = feedback.firstWhere(
        (f) => f['questionId'] == q['id'] || f['question'] == q['text'],
        orElse: () => {'isCorrect': false},
      );
      return {
        'question_id': q['id'],
        'answer_text': answerText,
        'is_correct': fb['isCorrect'] == true,
      };
    }).toList();

    // 1. Try atomic RPC submission first
    try {
      final rpcRes = await _client.rpc(
        'submit_student_quiz_attempt',
        params: {
          'p_quiz_id': quizId,
          'p_student_id': user.id,
          'p_score': score,
          'p_total_points': totalPoints,
          'p_percentage': percentage,
          'p_passed': passed,
          'p_answers': answersList,
        },
      );

      if (rpcRes is Map && rpcRes['success'] == true) {
        return QuizSubmissionResult(
          grade: Grade(
            id: rpcRes['attempt_id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
            studentId: user.id,
            quizId: quizId,
            score: score,
            totalPoints: totalPoints,
            percentage: percentage,
            passed: passed,
            submittedAt: DateTime.now(),
          ),
          feedback: feedback,
        );
      }
    } catch (rpcError) {
      // Fallback to table inserts below
    }

    // 2. Direct table insert fallback: First clean up prior grade if any
    Map<String, dynamic> gradeRow = {};
    try {
      await _client
          .from('grades')
          .delete()
          .eq('student_id', user.id)
          .eq('quiz_id', quizId);

      gradeRow = await _client
          .from('grades')
          .insert({
            'student_id': user.id,
            'quiz_id': quizId,
            'score': score,
            'total_points': totalPoints,
            'incorrect_answers': incorrectAnswers,
            'percentage': percentage,
            'passed': passed,
            'submitted_at': DateTime.now().toIso8601String(),
            'graded_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();
    } catch (_) {
      gradeRow = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'student_id': user.id,
        'quiz_id': quizId,
        'score': score,
        'total_points': totalPoints,
        'incorrect_answers': incorrectAnswers,
        'percentage': percentage,
        'passed': passed,
        'submitted_at': DateTime.now().toIso8601String(),
        'graded_at': DateTime.now().toIso8601String(),
      };
    }

    // 3. Upsert attempt & insert answers
    try {
      final attemptRow = await _client
          .from('quiz_attempts')
          .upsert({
            'quiz_id': quizId,
            'student_id': user.id,
            'submitted_at': DateTime.now().toIso8601String(),
            'completed_at': DateTime.now().toIso8601String(),
            'score': score,
            'status': 'submitted',
          }, onConflict: 'quiz_id,student_id')
          .select('id')
          .maybeSingle();

      final attemptId = attemptRow?['id'] as String?;
      if (attemptId != null) {
        await _client.from('answers').delete().eq('attempt_id', attemptId);
        final answersToInsert = answersList.map((a) {
          return {
            'attempt_id': attemptId,
            'question_id': a['question_id'],
            'answer_text': a['answer_text'],
            'is_correct': a['is_correct'],
          };
        }).toList();
        if (answersToInsert.isNotEmpty) {
          await _client.from('answers').insert(answersToInsert);
        }
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
          .select('id, text, type, options, correct_answer, points, explanation, accepted_answers')
          .eq('quiz_id', quizId)
          .order('order', ascending: true);
      final questions = List<Map<String, dynamic>>.from(qRows);
      if (questions.isEmpty) return rawFeedback;

      return questions.map((q) {
        final rawAns = answers[q['id']];
        final fb = rawFeedback.firstWhere(
          (f) => f['questionId'] == q['id'] || f['question'] == q['text'],
          orElse: () => <String, dynamic>{},
        );
        final options = q['options'] as List?;
        final correctOpt = (options != null)
            ? options.firstWhere(
                (o) => o is Map && o['is_correct'] == true,
                orElse: () => null,
              )
            : null;

        final isTextQ = q['type'] == 'short_answer' ||
            q['type'] == 'fill_in_blank' ||
            q['type'] == 'blank_space' ||
            q['type'] == 'description';

        final bool isCorrect = fb.containsKey('isCorrect')
            ? (fb['isCorrect'] == true)
            : evaluateQuestionAnswer(q, rawAns);

        return {
          'questionId': q['id'],
          'question': q['text'] ?? 'Question',
          'type': q['type'],
          'options': q['options'],
          'selectedAnswer': rawAns,
          'correctAnswer': isTextQ
              ? q['correct_answer']
              : (correctOpt?['id'] ?? q['correct_answer']),
          'correctAnswerText': isTextQ
              ? q['correct_answer']
              : (correctOpt?['text'] ?? q['correct_answer']),
          'explanation': q['explanation'] ?? fb['explanation'],
          'isCorrect': isCorrect,
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
