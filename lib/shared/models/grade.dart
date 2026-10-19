/// Represents a student's grade for a quiz attempt.
class Grade {
  final String id;
  final String studentId;
  final String quizId;
  final String? courseId;
  final int score;
  final int totalPoints;
  final int? percentage;
  final bool passed;
  final DateTime submittedAt;
  final DateTime? gradedAt;

  const Grade({
    required this.id,
    required this.studentId,
    required this.quizId,
    this.courseId,
    required this.score,
    required this.totalPoints,
    this.percentage,
    required this.passed,
    required this.submittedAt,
    this.gradedAt,
  });

  factory Grade.fromMap(Map<String, dynamic> map) {
    return Grade(
      id: map['id'] as String,
      studentId: map['student_id'] as String,
      quizId: map['quiz_id'] as String,
      courseId: map['course_id'] as String?,
      score: map['score'] as int? ?? 0,
      totalPoints: map['total_points'] as int? ?? 0,
      percentage: map['percentage'] as int?,
      passed: map['passed'] as bool? ?? false,
      submittedAt: map['submitted_at'] != null
          ? DateTime.parse(map['submitted_at'] as String)
          : DateTime.now(),
      gradedAt: map['graded_at'] != null
          ? DateTime.parse(map['graded_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'student_id': studentId,
      'quiz_id': quizId,
      'course_id': courseId,
      'score': score,
      'total_points': totalPoints,
      'percentage': percentage,
      'passed': passed,
      'submitted_at': submittedAt.toIso8601String(),
      'graded_at': gradedAt?.toIso8601String(),
    };
  }

  double get percent => totalPoints > 0 ? (score / totalPoints) * 100 : 0.0;
}