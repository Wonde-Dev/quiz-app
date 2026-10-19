import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/shared/models/quiz.dart';
import 'package:quiz_app/shared/models/question.dart';

/// Remote data source for quizzes and questions.
class QuizRemoteDataSource {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Quiz> createQuiz(Map<String, dynamic> data) async {
    final response = await _supabase
        .from('quizzes')
        .insert(data)
        .select()
        .single();
    return Quiz.fromMap(response);
  }

  Future<Quiz> updateQuiz(String id, Map<String, dynamic> data) async {
    final response = await _supabase
        .from('quizzes')
        .update(data)
        .eq('id', id)
        .select()
        .single();
    return Quiz.fromMap(response);
  }

  Future<void> deleteQuiz(String id) async {
    await _supabase.from('quizzes').delete().eq('id', id);
  }

  Future<Quiz?> getQuiz(String id) async {
    final response = await _supabase
        .from('quizzes')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (response == null) return null;
    return Quiz.fromMap(response);
  }

  Future<List<Quiz>> getQuizzesByTeacher(
    String teacherId, {
    bool publishedOnly = false,
  }) async {
    var query = _supabase.from('quizzes').select().eq('teacher_id', teacherId);
    if (publishedOnly) {
      query = query.eq('is_published', true);
    }
    final response = await query.order('created_at', ascending: false);
    return (response as List<dynamic>)
        .map((e) => Quiz.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Quiz>> getPublishedQuizzes({
    String? courseId,
    String? sectionId,
  }) async {
    var query = _supabase.from('quizzes').select().eq('is_published', true);
    if (courseId != null) {
      query = query.eq('course_id', courseId);
    }
    if (sectionId != null) {
      query = query.eq('section_id', sectionId);
    }
    final response = await query.order('created_at', ascending: false);
    return (response as List<dynamic>)
        .map((e) => Quiz.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<Question> createQuestion(Map<String, dynamic> data) async {
    final response = await _supabase
        .from('questions')
        .insert(data)
        .select()
        .single();
    return Question.fromMap(response);
  }

  Future<void> deleteQuestion(String id) async {
    await _supabase.from('questions').delete().eq('id', id);
  }

  Future<List<Question>> getQuestionsByQuiz(String quizId) async {
    final response = await _supabase
        .from('questions')
        .select()
        .eq('quiz_id', quizId)
        .order('order', ascending: true);
    return (response as List<dynamic>)
        .map((e) => Question.fromMap(e as Map<String, dynamic>))
        .toList();
  }
}
