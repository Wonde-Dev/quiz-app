/// Represents a quiz created by a teacher for a course.
class Quiz {
  final String id;
  final String teacherId;
  final String? courseId;
  final String? sectionId;
  final String title;
  final String? description;
  final int? timeLimitMinutes;
  final int? passingScorePercent;
  final int totalPoints;
  final bool isPublished;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const Quiz({
    required this.id,
    required this.teacherId,
    this.courseId,
    this.sectionId,
    required this.title,
    this.description,
    this.timeLimitMinutes,
    this.passingScorePercent,
    this.totalPoints = 0,
    this.isPublished = false,
    required this.createdAt,
    this.updatedAt,
  });

  factory Quiz.fromMap(Map<String, dynamic> map) {
    return Quiz(
      id: map['id'] as String,
      teacherId: map['teacher_id'] as String? ?? '',
      courseId: map['course_id'] as String?,
      sectionId: map['section_id'] as String?,
      title: map['title'] as String? ?? '',
      description: map['description'] as String?,
      timeLimitMinutes: map['time_limit_minutes'] as int?,
      passingScorePercent: map['passing_score_percent'] as int?,
      totalPoints: map['total_points'] as int? ?? 0,
      isPublished: map['is_published'] as bool? ?? false,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'teacher_id': teacherId,
      'course_id': courseId,
      'section_id': sectionId,
      'title': title,
      'description': description,
      'time_limit_minutes': timeLimitMinutes,
      'passing_score_percent': passingScorePercent,
      'total_points': totalPoints,
      'is_published': isPublished,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Quiz copyWith({
    String? id,
    String? teacherId,
    String? courseId,
    String? sectionId,
    String? title,
    String? description,
    int? timeLimitMinutes,
    int? passingScorePercent,
    int? totalPoints,
    bool? isPublished,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Quiz(
      id: id ?? this.id,
      teacherId: teacherId ?? this.teacherId,
      courseId: courseId ?? this.courseId,
      sectionId: sectionId ?? this.sectionId,
      title: title ?? this.title,
      description: description ?? this.description,
      timeLimitMinutes: timeLimitMinutes ?? this.timeLimitMinutes,
      passingScorePercent: passingScorePercent ?? this.passingScorePercent,
      totalPoints: totalPoints ?? this.totalPoints,
      isPublished: isPublished ?? this.isPublished,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}