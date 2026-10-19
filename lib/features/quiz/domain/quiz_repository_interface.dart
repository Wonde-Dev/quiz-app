import 'package:quiz_app/shared/models/grade.dart';
import 'package:quiz_app/shared/models/question.dart';
import 'package:quiz_app/shared/models/quiz.dart';

/// Abstract repository interface for quiz operations.
abstract class QuizRepositoryInterface {
  Future<Quiz> createQuiz(Map<String, dynamic> data);
  Future<Quiz> updateQuiz(String id, Map<String, dynamic> data);
  Future<void> deleteQuiz(String id);
  Future<Quiz?> getQuiz(String id);
  Future<List<Quiz>> getQuizzesByTeacher(
    String teacherId, {
    bool publishedOnly = false,
  });
  Future<List<Quiz>> getPublishedQuizzes({String? courseId, String? sectionId});
  Future<Question> createQuestion(Map<String, dynamic> data);
  Future<void> deleteQuestion(String id);
  Future<List<Question>> getQuestionsByQuiz(String quizId);
  Future<Grade> submitQuiz(Map<String, dynamic> data);
  Future<List<Grade>> getGradesByStudent(String studentId);
  Future<List<Grade>> getGradesByQuiz(String quizId);
  Future<Grade?> getStudentQuizAttempt(String studentId, String quizId);
}
