/// Represents a section/class within a school (e.g. Grade 10-A).
class Section {
  final String id;
  final String schoolId;
  final String name;
  final String? grade;
  final String? academicYear;
  final DateTime createdAt;

  const Section({
    required this.id,
    required this.schoolId,
    required this.name,
    this.grade,
    this.academicYear,
    required this.createdAt,
  });

  factory Section.fromMap(Map<String, dynamic> map) {
    return Section(
      id: map['id'] as String,
      schoolId: map['school_id'] as String,
      name: map['name'] as String,
      grade: map['grade'] as String?,
      academicYear: map['academic_year'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'school_id': schoolId,
      'name': name,
      'grade': grade,
      'academic_year': academicYear,
      'created_at': createdAt.toIso8601String(),
    };
  }
}