// shared/models/teacher_academic_activity.dart

/// Represents an academic activity performed by a faculty teacher (e.g. prepared quiz,
/// published examination, uploaded learning resource, entered marks).
/// Note: Contains NO private student information or scores to preserve student privacy.
class TeacherAcademicActivity {
  final String id;
  final String schoolId;
  final String teacherId;
  final String teacherName;
  final String activityType;
  final String description;
  final String? subject;
  final String? targetGrade;
  final String? targetSection;
  final String status;
  final DateTime createdAt;

  const TeacherAcademicActivity({
    required this.id,
    required this.schoolId,
    required this.teacherId,
    required this.teacherName,
    required this.activityType,
    required this.description,
    this.subject,
    this.targetGrade,
    this.targetSection,
    this.status = 'Active',
    required this.createdAt,
  });

  factory TeacherAcademicActivity.fromMap(Map<String, dynamic> map) {
    return TeacherAcademicActivity(
      id: map['id']?.toString() ?? '',
      schoolId: map['school_id']?.toString() ?? '00000000-0000-4000-8000-000000000001',
      teacherId: map['teacher_id']?.toString() ?? '',
      teacherName: map['teacher_name']?.toString() ?? 'Faculty Teacher',
      activityType: map['activity_type']?.toString() ?? 'quiz_created',
      description: map['description']?.toString() ?? '',
      subject: map['subject']?.toString(),
      targetGrade: map['target_grade']?.toString(),
      targetSection: map['target_section']?.toString(),
      status: map['status']?.toString() ?? 'Active',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'school_id': schoolId,
      'teacher_id': teacherId,
      'teacher_name': teacherName,
      'activity_type': activityType,
      'description': description,
      'subject': subject,
      'target_grade': targetGrade,
      'target_section': targetSection,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }

  String get displayType {
    switch (activityType) {
      case 'examination_published':
        return 'Examination Published';
      case 'quiz_created':
        return 'Quiz Created';
      case 'resource_uploaded':
        return 'Study Resource';
      case 'marks_evaluated':
        return 'Marks Evaluated';
      default:
        return 'Academic Activity';
    }
  }

  String get targetDisplay {
    final parts = <String>[];
    if (targetGrade != null && targetGrade!.isNotEmpty) parts.add(targetGrade!);
    if (targetSection != null && targetSection!.isNotEmpty) parts.add(targetSection!);
    if (parts.isEmpty) return 'All Classes';
    return parts.join(' - ');
  }
}

