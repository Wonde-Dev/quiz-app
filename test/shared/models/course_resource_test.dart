import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/shared/models/course_resource.dart';

void main() {
  group('CourseResource', () {
    test('serializes and deserializes correctly from map', () {
      final now = DateTime.now();
      final resource = CourseResource(
        id: 'res-123',
        title: 'Math Grade 10 Worksheet 1',
        description: 'Quadratic equations revision',
        fileName: 'math_g10_ws1.pdf',
        fileUrl: 'https://vsknxaxrwvpdevocnojn.supabase.co/storage/v1/object/public/course-materials/test.pdf',
        fileType: 'worksheet',
        fileSize: 102400,
        schoolId: 'school-1',
        teacherId: 'teacher-1',
        teacherName: 'Teacher Abebe',
        targetGrade: 'Grade 10',
        targetSection: 'Section A',
        createdAt: now,
      );

      final map = resource.toMap();
      expect(map['id'], 'res-123');
      expect(map['title'], 'Math Grade 10 Worksheet 1');
      expect(map['target_grade'], 'Grade 10');
      expect(map['target_section'], 'Section A');
      expect(map['file_type'], 'worksheet');

      final fromMap = CourseResource.fromMap(map);
      expect(fromMap.id, resource.id);
      expect(fromMap.title, resource.title);
      expect(fromMap.targetGrade, resource.targetGrade);
      expect(fromMap.targetSection, resource.targetSection);
      expect(fromMap.fileName, resource.fileName);
    });

    test('handles default fallbacks for missing optional map fields', () {
      final resource = CourseResource.fromMap({
        'id': 'res-999',
        'title': 'General Study Notes',
        'file_name': 'notes.pdf',
        'file_url': 'https://example.com/notes.pdf',
      });

      expect(resource.id, 'res-999');
      expect(resource.title, 'General Study Notes');
      expect(resource.fileType, 'pdf');
      expect(resource.targetGrade, isNull);
      expect(resource.targetSection, isNull);
      expect(resource.description, isNull);
    });
  });
}

