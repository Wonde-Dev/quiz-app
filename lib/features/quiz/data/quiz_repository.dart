import 'package:quiz_app/features/quiz/data/grade_remote_data_source.dart';
import 'package:quiz_app/features/quiz/data/quiz_remote_data_source.dart';
import 'package:quiz_app/shared/models/grade.dart';
import 'package:quiz_app/shared/models/question.dart';
import 'package:quiz_app/shared/models/quiz.dart';

/// Repository interface for quiz operations.
abstract class QuizRepository {
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

/// Concrete implementation using Supabase.
class QuizRepositoryImpl implements QuizRepository {
  final QuizRemoteDataSource _quizRemote;
  final GradeRemoteDataSource _gradeRemote;

  QuizRepositoryImpl(this._quizRemote, this._gradeRemote);

  @override
  Future<Quiz> createQuiz(Map<String, dynamic> data) =>
      _quizRemote.createQuiz(data);

  @override
  Future<Quiz> updateQuiz(String id, Map<String, dynamic> data) =>
      _quizRemote.updateQuiz(id, data);

  @override
  Future<void> deleteQuiz(String id) => _quizRemote.deleteQuiz(id);

  @override
  Future<Quiz?> getQuiz(String id) => _quizRemote.getQuiz(id);

  @override
  Future<List<Quiz>> getQuizzesByTeacher(
    String teacherId, {
    bool publishedOnly = false,
  }) =>
      _quizRemote.getQuizzesByTeacher(teacherId, publishedOnly: publishedOnly);

  @override
  Future<List<Quiz>> getPublishedQuizzes({
    String? courseId,
    String? sectionId,
  }) =>
      _quizRemote.getPublishedQuizzes(courseId: courseId, sectionId: sectionId);

  @override
  Future<Question> createQuestion(Map<String, dynamic> data) =>
      _quizRemote.createQuestion(data);

  @override
  Future<void> deleteQuestion(String id) => _quizRemote.deleteQuestion(id);

  @override
  Future<List<Question>> getQuestionsByQuiz(String quizId) =>
      _quizRemote.getQuestionsByQuiz(quizId);

  @override
  Future<Grade> submitQuiz(Map<String, dynamic> data) =>
      _gradeRemote.submitQuiz(data);

  @override
  Future<List<Grade>> getGradesByStudent(String studentId) =>
      _gradeRemote.getGradesByStudent(studentId);

  @override
  Future<List<Grade>> getGradesByQuiz(String quizId) =>
      _gradeRemote.getGradesByQuiz(quizId);

  @override
  Future<Grade?> getStudentQuizAttempt(String studentId, String quizId) =>
      _gradeRemote.getStudentQuizAttempt(studentId, quizId);
}
