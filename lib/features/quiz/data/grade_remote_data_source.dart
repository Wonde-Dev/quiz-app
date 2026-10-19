import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/shared/models/grade.dart';

/// Remote data source for grades and quiz attempts.
class GradeRemoteDataSource {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Grade> submitQuiz(Map<String, dynamic> data) async {
    final response = await _supabase
        .from('grades')
        .insert(data)
        .select()
        .single();
    return Grade.fromMap(response);
  }

  Future<List<Grade>> getGradesByStudent(String studentId) async {
    final response = await _supabase
        .from('grades')
        .select()
        .eq('student_id', studentId)
        .order('submitted_at', ascending: false);
    return (response as List<dynamic>)
        .map((e) => Grade.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Grade>> getGradesByQuiz(String quizId) async {
    final response = await _supabase
        .from('grades')
        .select()
        .eq('quiz_id', quizId)
        .order('submitted_at', ascending: false);
    return (response as List<dynamic>)
        .map((e) => Grade.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<Grade?> getStudentQuizAttempt(String studentId, String quizId) async {
    final response = await _supabase
        .from('grades')
        .select()
        .eq('student_id', studentId)
        .eq('quiz_id', quizId)
        .maybeSingle();
    if (response == null) return null;
    return Grade.fromMap(response);
  }
}
