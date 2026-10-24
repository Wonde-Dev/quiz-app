class CourseResource {
  final String id;
  final String title;
  final String? description;
  final String fileName;
  final String fileUrl;
  final String fileType; // pdf, worksheet, exam, study_guide
  final int? fileSize;
  final String? schoolId;
  final String? teacherId;
  final String? teacherName;
  final String? targetGrade;
  final String? targetSection;
  final DateTime createdAt;

  const CourseResource({
    required this.id,
    required this.title,
    this.description,
    required this.fileName,
    required this.fileUrl,
    this.fileType = 'pdf',
    this.fileSize,
    this.schoolId,
    this.teacherId,
    this.teacherName,
    this.targetGrade,
    this.targetSection,
    required this.createdAt,
  });

  factory CourseResource.fromMap(Map<String, dynamic> map) {
    return CourseResource(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? 'Untitled Resource',
      description: map['description'] as String?,
      fileName: map['file_name'] as String? ?? 'document.pdf',
      fileUrl: map['file_url'] as String? ?? '',
      fileType: map['file_type'] as String? ?? 'pdf',
      fileSize: map['file_size'] as int?,
      schoolId: map['school_id'] as String?,
      teacherId: map['teacher_id'] as String?,
      teacherName: map['teacher_name'] as String?,
      targetGrade: map['target_grade'] as String?,
      targetSection: map['target_section'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'file_name': fileName,
      'file_url': fileUrl,
      'file_type': fileType,
      'file_size': fileSize,
      'school_id': schoolId,
      'teacher_id': teacherId,
      'teacher_name': teacherName,
      'target_grade': targetGrade,
      'target_section': targetSection,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

