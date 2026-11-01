import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/shared/models/course_resource.dart';

class CourseResourceService {
  SupabaseClient get _supabase => Supabase.instance.client;

  // Local fallback storage cache in case table hasn't been migrated
  static final List<CourseResource> _fallbackCache = [];
  static bool _isMaterialsLockedFallback = false;

  /// Checks if study materials (PDFs & Videos) are locked for exam mode
  Future<bool> isMaterialsLocked({String? schoolId}) async {
    try {
      final res = await _supabase.rpc(
        'get_materials_lock_status',
        params: {'p_school_id': schoolId},
      );
      if (res is Map && res['materials_locked'] != null) {
        final locked = res['materials_locked'] == true;
        _isMaterialsLockedFallback = locked;
        return locked;
      }
    } catch (_) {}

    try {
      if (schoolId != null) {
        final row = await _supabase
            .from('schools')
            .select('materials_locked')
            .eq('id', schoolId)
            .maybeSingle();
        if (row != null && row['materials_locked'] != null) {
          final locked = row['materials_locked'] == true;
          _isMaterialsLockedFallback = locked;
          return locked;
        }
      }
    } catch (_) {}

    return _isMaterialsLockedFallback;
  }

  /// One-button toggle to lock or unlock study materials (PDFs & Videos)
  Future<bool> toggleMaterialsLock(bool locked, {String? schoolId}) async {
    _isMaterialsLockedFallback = locked;
    try {
      final res = await _supabase.rpc(
        'toggle_materials_lock',
        params: {
          'p_locked': locked,
          'p_school_id': schoolId,
        },
      );
      if (res is Map && res['success'] == true) {
        return res['materials_locked'] == true;
      }
    } catch (e) {
      debugPrint('toggle_materials_lock RPC note: $e');
    }

    try {
      if (schoolId != null) {
        await _supabase
            .from('schools')
            .update({'materials_locked': locked})
            .eq('id', schoolId);
      }
    } catch (_) {}

    return locked;
  }

  Future<CourseResource> uploadResource({
    required Uint8List fileBytes,
    required String fileName,
    required String title,
    String? description,
    required String targetGrade,
    required String targetSection,
    required String teacherId,
    required String teacherName,
    String? schoolId,
    String fileType = 'pdf',
    String? thumbnailUrl,
    Uint8List? thumbnailBytes,
    String? thumbnailFileName,
  }) async {
    final cleanFileName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath = 'teachers/$teacherId/${DateTime.now().millisecondsSinceEpoch}_$cleanFileName';

    String fileUrl = '';

    // 1. Try uploading to 'course-materials' bucket
    try {
      await _supabase.storage.from('course-materials').uploadBinary(
            storagePath,
            fileBytes,
            fileOptions: const FileOptions(contentType: 'application/pdf', upsert: true),
          );
      fileUrl = _supabase.storage.from('course-materials').getPublicUrl(storagePath);
    } catch (e) {
      debugPrint('course-materials bucket upload note: $e');
      // Fallback: try 'profile-photos' bucket if course-materials doesn't exist yet
      try {
        final fallbackPath = 'docs/$storagePath';
        await _supabase.storage.from('profile-photos').uploadBinary(
              fallbackPath,
              fileBytes,
              fileOptions: const FileOptions(contentType: 'application/pdf', upsert: true),
            );
        fileUrl = _supabase.storage.from('profile-photos').getPublicUrl(fallbackPath);
      } catch (e2) {
        debugPrint('Fallback storage upload note: $e2');
      }
    }

    String? finalThumbnailUrl = thumbnailUrl?.trim();
    if (thumbnailBytes != null && thumbnailBytes.isNotEmpty) {
      final cleanThumbName = (thumbnailFileName ?? 'thumb.png').replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final thumbPath = 'teachers/$teacherId/thumb_${DateTime.now().millisecondsSinceEpoch}_$cleanThumbName';
      try {
        await _supabase.storage.from('course-materials').uploadBinary(
              thumbPath,
              thumbnailBytes,
              fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
            );
        finalThumbnailUrl = _supabase.storage.from('course-materials').getPublicUrl(thumbPath);
      } catch (e) {
        try {
          final fallbackThumbPath = 'thumbs/$thumbPath';
          await _supabase.storage.from('profile-photos').uploadBinary(
                fallbackThumbPath,
                thumbnailBytes,
                fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
              );
          finalThumbnailUrl = _supabase.storage.from('profile-photos').getPublicUrl(fallbackThumbPath);
        } catch (_) {}
      }
    }

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final resourceMap = {
      'id': id,
      'title': title.trim(),
      'description': description?.trim(),
      'file_name': fileName,
      'file_url': fileUrl,
      'file_type': fileType,
      'file_size': fileBytes.length,
      if (finalThumbnailUrl != null && finalThumbnailUrl.isNotEmpty) 'thumbnail_url': finalThumbnailUrl,
      'school_id': schoolId,
      'teacher_id': teacherId,
      'teacher_name': teacherName,
      'target_grade': targetGrade,
      'target_section': targetSection,
      'created_at': DateTime.now().toIso8601String(),
    };

    try {
      final inserted = await _supabase
          .from('course_resources')
          .insert(resourceMap)
          .select()
          .single();
      final resource = CourseResource.fromMap(inserted);
      _fallbackCache.insert(0, resource);
      return resource;
    } catch (e) {
      debugPrint('course_resources insert fallback note: $e');
      final fallbackResource = CourseResource.fromMap(resourceMap);
      _fallbackCache.insert(0, fallbackResource);
      return fallbackResource;
    }
  }

  Future<CourseResource> addVideoResource({
    required String title,
    String? description,
    required String videoUrl,
    String? customThumbnailUrl,
    Uint8List? thumbnailBytes,
    String? thumbnailFileName,
    required String targetGrade,
    required String targetSection,
    required String teacherId,
    required String teacherName,
    String? schoolId,
  }) async {
    String finalThumbnailUrl = customThumbnailUrl ?? '';

    // If custom thumbnail image bytes provided, upload it to storage
    if (thumbnailBytes != null && thumbnailBytes.isNotEmpty) {
      try {
        final cleanName = (thumbnailFileName ?? 'thumb.jpg')
            .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final storagePath =
            'thumbnails/$teacherId/${DateTime.now().millisecondsSinceEpoch}_$cleanName';
        await _supabase.storage.from('course-materials').uploadBinary(
              storagePath,
              thumbnailBytes,
              fileOptions:
                  const FileOptions(contentType: 'image/jpeg', upsert: true),
            );
        finalThumbnailUrl =
            _supabase.storage.from('course-materials').getPublicUrl(storagePath);
      } catch (e) {
        debugPrint('Thumbnail upload note: $e');
      }
    }

    if (finalThumbnailUrl.isEmpty) {
      finalThumbnailUrl = CourseResource.extractYoutubeThumbnail(videoUrl) ?? '';
    }

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final resourceMap = {
      'id': id,
      'title': title.trim(),
      'description': description?.trim(),
      'file_name': 'Video: $title',
      'file_url': videoUrl.trim(),
      'file_type': 'video',
      'video_url': videoUrl.trim(),
      'thumbnail_url': finalThumbnailUrl.isNotEmpty ? finalThumbnailUrl : null,
      'school_id': schoolId,
      'teacher_id': teacherId,
      'teacher_name': teacherName,
      'target_grade': targetGrade,
      'target_section': targetSection,
      'created_at': DateTime.now().toIso8601String(),
    };

    try {
      final inserted = await _supabase
          .from('course_resources')
          .insert(resourceMap)
          .select()
          .single();
      final resource = CourseResource.fromMap(inserted);
      _fallbackCache.insert(0, resource);
      return resource;
    } catch (e) {
      debugPrint('course_resources video insert note: $e');
      final fallbackResource = CourseResource.fromMap(resourceMap);
      _fallbackCache.insert(0, fallbackResource);
      return fallbackResource;
    }
  }

  Future<List<CourseResource>> getResourcesForStudent({
    String? targetGrade,
    String? targetSection,
    String? schoolId,
  }) async {
    List<CourseResource> list = [];

    try {
      final rows = await _supabase
          .from('course_resources')
          .select()
          .order('created_at', ascending: false);

      list = (rows as List).map((r) => CourseResource.fromMap(r)).toList();
      if (schoolId != null) {
        list = list.where((r) => r.schoolId == null || r.schoolId == schoolId).toList();
      }
    } catch (e) {
      if (e is! PostgrestException || e.code != 'PGRST205') {
        debugPrint('getResourcesForStudent note: $e');
      }
      list = List.from(_fallbackCache);
    }

    // Filter strictly by student's grade and section
    final cleanGrade = targetGrade?.trim().toLowerCase();
    final cleanSection = targetSection?.trim().toLowerCase();

    if (cleanGrade == null && cleanSection == null) {
      return list;
    }

    return list.where((res) {
      final resGrade = res.targetGrade?.trim().toLowerCase();
      final resSection = res.targetSection?.trim().toLowerCase();

      // If resource is general for everyone
      if ((resGrade == null || resGrade.isEmpty) && (resSection == null || resSection.isEmpty)) {
        return true;
      }

      // Check grade match
      if (cleanGrade != null && resGrade != null && resGrade.isNotEmpty) {
        final matchesGrade = cleanGrade.contains(resGrade) ||
            resGrade.contains(cleanGrade) ||
            cleanGrade.replaceAll(RegExp(r'[^0-9]'), '') == resGrade.replaceAll(RegExp(r'[^0-9]'), '');
        if (!matchesGrade) return false;
      }

      // Check section match
      if (cleanSection != null && resSection != null && resSection.isNotEmpty) {
        final matchesSection = cleanSection.contains(resSection) ||
            resSection.contains(cleanSection) ||
            cleanSection.replaceAll('section', '').trim() == resSection.replaceAll('section', '').trim();
        if (!matchesSection) return false;
      }

      return true;
    }).toList();
  }

  Future<List<CourseResource>> getResourcesByTeacher(String teacherId) async {
    try {
      final rows = await _supabase
          .from('course_resources')
          .select()
          .eq('teacher_id', teacherId)
          .order('created_at', ascending: false);
      return (rows as List).map((r) => CourseResource.fromMap(r)).toList();
    } catch (e) {
      debugPrint('getResourcesByTeacher note: $e');
      return _fallbackCache.where((r) => r.teacherId == teacherId).toList();
    }
  }

  Future<void> deleteResource(String resourceId) async {
    try {
      await _supabase.from('course_resources').delete().eq('id', resourceId);
    } catch (e) {
      debugPrint('deleteResource note: $e');
    }
    _fallbackCache.removeWhere((r) => r.id == resourceId);
  }
}

