import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/shared/models/school_announcement.dart';

class AnnouncementService {
  AnnouncementService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const String ciroSchoolId = '00000000-0000-4000-8000-000000000001';

  Future<List<SchoolAnnouncement>> fetchAnnouncements({
    String schoolId = ciroSchoolId,
    int limit = 10,
  }) async {
    try {
      final rows = await _client
          .from('school_announcements')
          .select()
          .eq('school_id', schoolId)
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false)
          .limit(limit);

      return (rows as List)
          .map((r) => SchoolAnnouncement.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('fetchAnnouncements notice: $e');
      return [];
    }
  }

  Future<bool> createAnnouncement({
    required String title,
    required String content,
    required String authorName,
    required String authorRole,
    String targetAudience = 'all',
    bool isPinned = false,
    String schoolId = ciroSchoolId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    try {
      await _client.from('school_announcements').insert({
        'school_id': schoolId,
        'author_id': user.id,
        'author_name': authorName,
        'author_role': authorRole,
        'title': title.trim(),
        'content': content.trim(),
        'target_audience': targetAudience,
        'is_pinned': isPinned,
      });
      return true;
    } catch (e) {
      debugPrint('createAnnouncement error: $e');
      rethrow;
    }
  }

  Future<bool> updateAnnouncement({
    required String id,
    required String title,
    required String content,
    String targetAudience = 'all',
    bool isPinned = false,
  }) async {
    try {
      await _client.from('school_announcements').update({
        'title': title.trim(),
        'content': content.trim(),
        'target_audience': targetAudience,
        'is_pinned': isPinned,
      }).eq('id', id);
      return true;
    } catch (e) {
      debugPrint('updateAnnouncement error: $e');
      rethrow;
    }
  }

  Future<bool> deleteAnnouncement(String id) async {
    try {
      await _client.from('school_announcements').delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('deleteAnnouncement error: $e');
      rethrow;
    }
  }
}

