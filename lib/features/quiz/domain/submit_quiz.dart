import 'package:quiz_app/features/quiz/data/quiz_repository.dart';

/// Abstract use case for submitting a quiz.
abstract class SubmitQuiz {
  Future<void> call(
    String quizId,
    String studentId,
    Map<String, dynamic> answers,
  );
}

class SubmitQuizImpl implements SubmitQuiz {
  final QuizRepository repository;

  SubmitQuizImpl(this.repository);

  @override
  Future<void> call(
    String quizId,
    String studentId,
    Map<String, dynamic> answers,
  ) async {
    await repository.submitQuiz({
      'quiz_id': quizId,
      'student_id': studentId,
      ...answers,
    });
  }
}
