import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/models/user.dart';

/// Handles authentication via Supabase Auth.
class AuthService {
  SupabaseClient get _supabase => Supabase.instance.client;

  /// Sign in with email or institutional username.
  Future<AuthResponse> signIn({
    required String emailOrUsername,
    required String password,
  }) async {
    final input = emailOrUsername.trim();
    if (input.isEmpty) {
      throw const FormatException('Enter your username or email address.');
    }

    final lower = input.toLowerCase();

    // 1. Try login-by-username Edge Function if deployed
    try {
      final response = await _supabase.functions.invoke(
        'login-by-username',
        body: {'username': input, 'password': password},
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final refreshToken = data['refresh_token'];
        if (refreshToken is String && refreshToken.isNotEmpty) {
          return await _supabase.auth.setSession(refreshToken);
        }
      }
    } catch (_) {
      // Edge function not deployed or returned 404
    }

    // Build ordered list of candidate auth emails
    final candidates = <String>[];

    // Priority 1: RPC lookup from public.users
    try {
      final emailResult = await _supabase.rpc(
        'get_email_by_username',
        params: {'p_username': input},
      );
      if (emailResult is String && emailResult.trim().isNotEmpty) {
        final clean = emailResult.trim().toLowerCase();
        if (!candidates.contains(clean)) candidates.add(clean);
      }
    } catch (_) {}

    // Priority 2: Direct public.users table lookup by username
    try {
      final row = await _supabase
          .from('users')
          .select('email')
          .ilike('username', input)
          .limit(1)
          .maybeSingle();
      final lookedUp = row?['email'] as String?;
      if (lookedUp != null && lookedUp.trim().isNotEmpty) {
        final clean = lookedUp.trim().toLowerCase();
        if (!candidates.contains(clean)) candidates.add(clean);
      }
    } catch (_) {}

    // Priority 3: Alternative suffix for Student / Students
    if (lower.endsWith('@students.edu')) {
      final alt = input.replaceAll(
        RegExp(r'@students\.edu$', caseSensitive: false),
        '@Student.edu',
      );
      try {
        final row = await _supabase
            .from('users')
            .select('email')
            .ilike('username', alt)
            .limit(1)
            .maybeSingle();
        final lookedUp = row?['email'] as String?;
        if (lookedUp != null && lookedUp.trim().isNotEmpty) {
          final clean = lookedUp.trim().toLowerCase();
          if (!candidates.contains(clean)) candidates.add(clean);
        }
      } catch (_) {}
    } else if (lower.endsWith('@student.edu')) {
      final alt = input.replaceAll(
        RegExp(r'@student\.edu$', caseSensitive: false),
        '@Students.edu',
      );
      try {
        final row = await _supabase
            .from('users')
            .select('email')
            .ilike('username', alt)
            .limit(1)
            .maybeSingle();
        final lookedUp = row?['email'] as String?;
        if (lookedUp != null && lookedUp.trim().isNotEmpty) {
          final clean = lookedUp.trim().toLowerCase();
          if (!candidates.contains(clean)) candidates.add(clean);
        }
      } catch (_) {}
    }

    // Priority 4: Direct input as email (synonymous with lowercase username)
    if (!candidates.contains(lower)) {
      candidates.add(lower);
    }

    // Priority 5: Known administrator aliases
    if (lower.startsWith('wondeadmin') ||
        lower.startsWith('wondedev') ||
        lower == 'wonde' ||
        lower.contains('@admin.edu')) {
      if (!candidates.contains('wondedev369@gmail.com')) {
        candidates.add('wondedev369@gmail.com');
      }
      if (!candidates.contains('wondeadmin@admin.edu')) {
        candidates.add('wondeadmin@admin.edu');
      }
    }

    // Try signing in with each candidate in order
    AuthException? lastAuthException;
    for (final candidateEmail in candidates) {
      try {
        return await _supabase.auth.signInWithPassword(
          email: candidateEmail,
          password: password,
        );
      } on AuthException catch (e) {
        lastAuthException = e;
      } catch (_) {
        // Try next candidate
      }
    }

    if (lastAuthException != null) {
      throw lastAuthException;
    }

    return await _supabase.auth.signInWithPassword(
      email: lower,
      password: password,
    );
  }

  Future<AuthResponse> registerAccount({
    required String fullName,
    required String username,
    required String email,
    required String password,
    required String requestedRole,
    String? schoolId,
    String? sectionId,
    String? requestedGrade,
    String? requestedClass,
    String? requestedSubject,
  }) async {
    return _supabase.auth.signUp(
      email: email.trim().toLowerCase(),
      password: password,
      data: {
        'full_name': fullName.trim(),
        'username': username.trim(),
        'requested_role': requestedRole,
        'school_id': schoolId,
        'section_id': sectionId,
        'requested_grade': requestedGrade,
        'requested_class': requestedClass,
        'requested_subject': requestedSubject,
      },
    );
  }

  Future<void> updateProfile({String? fullName, String? avatarPath}) async {
    final body = <String, String>{};
    if (fullName != null) body['fullName'] = fullName.trim();
    if (avatarPath != null) body['avatarPath'] = avatarPath;
    await _supabase.functions.invoke('update-profile', body: body);
  }

  Future<String> uploadAvatar({
    required XFile image,
    required String userId,
  }) async {
    final extension = image.name.split('.').last.toLowerCase();
    const contentTypes = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
    };
    final contentType = contentTypes[extension];
    if (contentType == null) {
      throw const FormatException('Choose a JPG, PNG, or WebP image.');
    }
    if (await image.length() > 5 * 1024 * 1024) {
      throw const FormatException('Profile images must be 5 MB or smaller.');
    }
    final path = '$userId/avatar.$extension';
    await _supabase.storage
        .from('profile-photos')
        .uploadBinary(
          path,
          await image.readAsBytes(),
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return path;
  }

  Future<void> sendPasswordReset(String email) async {
    await _supabase.auth.resetPasswordForEmail(email.trim());
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  /// Current authenticated user (Supabase Auth user).
  User? get currentUser => _supabase.auth.currentUser;

  /// Get the app user record from the `users` table by auth uid.
  Future<AppUser?> getAppUser(String uid) async {
    try {
      final response = await _supabase
          .from('users')
          .select(
            'id, email, username, role, school_id, full_name, avatar_url, '
            'must_change_password, requested_role, approval_status, is_active, '
            'created_at, last_login',
          )
          .eq('id', uid)
          .maybeSingle();
      if (response != null) {
        return AppUser.fromMap(response);
      }
    } catch (e) {
      debugPrint('getAppUser query note: $e');
    }

    // Auto-heal if user exists in auth.users but record is missing in public.users:
    final current = _supabase.auth.currentUser;
    if (current != null && current.id == uid) {
      final emailLower = current.email?.toLowerCase() ?? '';
      final role = (emailLower.contains('admin') ||
              emailLower == 'wondedev369@gmail.com')
          ? 'admin'
          : (emailLower.contains('teacher') ? 'teacher' : 'student');
      final fallbackMap = {
        'id': uid,
        'email': emailLower,
        'username': current.userMetadata?['username'] as String? ??
            current.email ??
            'User',
        'full_name': current.userMetadata?['full_name'] as String? ?? 'User',
        'role': role,
        'school_id': current.userMetadata?['school_id'] as String?,
        'is_active': true,
        'approval_status': 'approved',
        'must_change_password': false,
        'created_at': DateTime.now().toIso8601String(),
      };
      try {
        await _supabase.from('users').insert(fallbackMap);
      } catch (_) {}
      return AppUser.fromMap(fallbackMap);
    }

    return null;
  }

  /// Refresh the app user record (e.g. after password change).
  Future<AppUser?> refreshAppUser(String uid) async {
    return getAppUser(uid);
  }

  /// Update must_change_password flag.
  Future<void> setMustChangePassword(String uid, bool value) async {
    await _supabase
        .from('users')
        .update({'must_change_password': value})
        .eq('id', uid);
  }

  /// Reset password via Supabase OTP.
  Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }

  /// Update user password (requires current session).
  Future<void> updatePassword(String newPassword) async {
    await _supabase.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<void> changeOwnPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final email = _supabase.auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      throw StateError('Your session has expired. Sign in again.');
    }
    await _supabase.auth.signInWithPassword(
      email: email,
      password: currentPassword,
    );
    await updatePassword(newPassword);
  }

  /// Stream of auth state changes.
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;
}
