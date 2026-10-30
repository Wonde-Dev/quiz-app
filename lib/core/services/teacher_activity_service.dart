// core/services/teacher_activity_service.dart

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/teacher_academic_activity.dart';

class TeacherActivityService {
  static const String ciroSchoolId = '00000000-0000-4000-8000-000000000001';
  final SupabaseClient _client = Supabase.instance.client;

  /// Fetch teacher academic activities for the school.
  /// Shows when teachers create quizzes, publish exams, upload resources.
  /// Strictly contains NO private student data.
  Future<List<TeacherAcademicActivity>> fetchActivities({
    String? schoolId,
    int limit = 50,
  }) async {
    final effectiveSchoolId = schoolId ?? ciroSchoolId;

    // 1. Try dedicated RPC
    try {
      final res = await _client.rpc(
        'get_teacher_academic_activities',
        params: {
          'p_school_id': effectiveSchoolId,
          'p_limit': limit,
        },
      );
      if (res is List) {
        return res
            .map((item) =>
                TeacherAcademicActivity.fromMap(item as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('get_teacher_academic_activities RPC note: $e');
    }

    // 2. Direct table fallback
    try {
      final rows = await _client
          .from('teacher_academic_activities')
          .select()
          .eq('school_id', effectiveSchoolId)
          .order('created_at', ascending: false)
          .limit(limit);

      return (rows as List)
          .map((item) =>
              TeacherAcademicActivity.fromMap(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('teacher_academic_activities table fallback note: $e');
      return [];
    }
  }

  /// Transfer Super Admin Ownership to another eligible active user account.
  /// Requires caller to confirm their current password.
  Future<Map<String, dynamic>> transferSuperAdminOwnership({
    required String targetUserId,
    required String currentPassword,
  }) async {
    final res = await _client.rpc(
      'transfer_super_admin_ownership',
      params: {
        'p_target_user_id': targetUserId,
        'p_current_password': currentPassword,
      },
    );
    if (res is Map) {
      return Map<String, dynamic>.from(res);
    }
    return {'success': true, 'message': 'Ownership transferred successfully'};
  }

  /// Transfer Director Position to an eligible Faculty Teacher.
  /// Requires caller (active Director or Super Admin) to confirm their current password.
  Future<Map<String, dynamic>> transferDirectorPosition({
    required String targetTeacherId,
    required String currentPassword,
  }) async {
    final res = await _client.rpc(
      'transfer_director_position',
      params: {
        'p_target_teacher_id': targetTeacherId,
        'p_current_password': currentPassword,
      },
    );
    if (res is Map) {
      return Map<String, dynamic>.from(res);
    }
    return {'success': true, 'message': 'Director position transferred successfully'};
  }

  /// Suspend or Activate an account with strict RBAC:
  /// Super Admin can suspend/activate anyone except Super Admin.
  /// School Director can only suspend/activate Faculty Teachers.
  Future<Map<String, dynamic>> toggleUserStatus({
    required String userId,
    required bool isActive,
  }) async {
    final res = await _client.rpc(
      'toggle_user_status',
      params: {
        'p_user_id': userId,
        'p_is_active': isActive,
      },
    );
    if (res is Map) {
      return Map<String, dynamic>.from(res);
    }
    return {'success': true, 'is_active': isActive};
  }
}

