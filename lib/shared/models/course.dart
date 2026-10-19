/// Represents a course/subject taught by a teacher to a section.
class Course {
  final String id;
  final String schoolId;
  final String? sectionId;
  final String teacherId;
  final String name;
  final String? description;
  final String? subject;
  final DateTime createdAt;

  const Course({
    required this.id,
    required this.schoolId,
    this.sectionId,
    required this.teacherId,
    required this.name,
    this.description,
    this.subject,
    required this.createdAt,
  });

  factory Course.fromMap(Map<String, dynamic> map) {
    return Course(
      id: map['id'] as String,
      schoolId: map['school_id'] as String,
      sectionId: map['section_id'] as String?,
      teacherId: map['teacher_id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      subject: map['subject'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'school_id': schoolId,
      'section_id': sectionId,
      'teacher_id': teacherId,
      'name': name,
      'description': description,
      'subject': subject,
      'created_at': createdAt.toIso8601String(),
    };
  }
}