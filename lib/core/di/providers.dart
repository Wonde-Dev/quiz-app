import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quiz_app/core/services/audit_log_service.dart';
import 'package:quiz_app/core/services/auth_service.dart';
import 'package:quiz_app/core/services/security/screenshot_service.dart';

final supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final auditLogServiceProvider = Provider<AuditLogService>((ref) {
  return AuditLogService();
});

final screenshotServiceProvider = Provider<ScreenshotService>((ref) {
  return ScreenshotService();
});
