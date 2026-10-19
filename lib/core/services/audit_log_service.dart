import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/models/audit_log.dart';

/// Writes audit entries to Supabase.
class AuditLogService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<void> logForCurrentUser({
    required String action,
    String? targetUser,
    Map<String, dynamic>? details,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before recording account activity.');
    }
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final actorName = metadata['full_name'] as String? ?? user.email ?? user.id;
    await log(
      action: action,
      performedBy: user.id,
      targetUser: targetUser,
      details: {'actor_name': actorName, ...?details},
    );
  }

  Future<void> log({
    required String action,
    required String performedBy,
    String? targetUser,
    Map<String, dynamic>? details,
    String? ipAddress,
    String? userAgent,
  }) async {
    await _supabase.from('audit_logs').insert({
      'action': action,
      'performed_by': performedBy,
      'target_user': targetUser,
      'details': details,
      'ip_address': ipAddress,
      'user_agent': userAgent,
    });
  }

  Future<void> logPasswordReset({
    required String teacherId,
    required String studentId,
  }) async {
    await log(
      action: 'password_reset',
      performedBy: teacherId,
      targetUser: studentId,
      details: {'timestamp': DateTime.now().toIso8601String()},
    );
  }

  Future<void> logSuspiciousActivity({
    required String quizId,
    required String activity,
    Map<String, dynamic>? details,
    String? performedBy,
  }) async {
    final actorId = performedBy ?? _supabase.auth.currentUser?.id;
    if (actorId == null) {
      throw StateError('Sign in before recording quiz activity.');
    }
    await log(
      action: activity,
      performedBy: actorId,
      details: {
        'quiz_id': quizId,
        'activity': activity,
        'timestamp': DateTime.now().toIso8601String(),
        ...?details,
      },
    );
  }

  Future<List<AuditLog>> fetchLogs({int limit = 100, String? action}) async {
    final response = action == null
        ? await _supabase
              .from('audit_logs')
              .select(
                'id, action, performed_by, target_user, details, created_at',
              )
              .order('created_at', ascending: false)
              .limit(limit)
        : await _supabase
              .from('audit_logs')
              .select(
                'id, action, performed_by, target_user, details, created_at',
              )
              .eq('action', action)
              .order('created_at', ascending: false)
              .limit(limit);
    return (response as List<dynamic>)
        .map((e) => AuditLog.fromMap(e as Map<String, dynamic>))
        .toList();
  }
}
