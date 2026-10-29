import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/shared/models/school_announcement.dart';

void main() {
  group('SchoolAnnouncement', () {
    test('serializes and deserializes correctly from map', () {
      final now = DateTime.now();
      final announcement = SchoolAnnouncement(
        id: 'ann-1',
        schoolId: '00000000-0000-4000-8000-000000000001',
        authorId: 'usr-1',
        authorName: 'Director Haile',
        authorRole: 'Director',
        title: 'Midterm Examination Schedule',
        content: 'Examinations begin next Monday. Please review the timetable.',
        targetAudience: 'all',
        isPinned: true,
        createdAt: now,
      );

      final map = announcement.toJson();
      expect(map['title'], 'Midterm Examination Schedule');
      expect(map['is_pinned'], true);

      final parsed = SchoolAnnouncement.fromJson(map);
      expect(parsed.id, 'ann-1');
      expect(parsed.title, 'Midterm Examination Schedule');
      expect(parsed.authorName, 'Director Haile');
      expect(parsed.isPinned, true);
    });

    test('handles default fallbacks for missing optional map fields', () {
      final parsed = SchoolAnnouncement.fromJson(const {});
      expect(parsed.id, '');
      expect(parsed.title, '');
      expect(parsed.authorName, 'Director');
      expect(parsed.isPinned, false);
      expect(parsed.targetAudience, 'all');
    });
  });
}

