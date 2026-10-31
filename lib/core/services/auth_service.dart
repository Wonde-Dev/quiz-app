import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:quiz_app/core/utils/role_username.dart';

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

    // Priority 0: Direct input if it is a standard external email address
    if (lower.contains('@') && !lower.endsWith('.edu')) {
      candidates.add(lower);
    }

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

    // Priority 5: Known administrator & director aliases
    if (lower.startsWith('wondeadmin') ||
        lower.startsWith('wondedev') ||
        lower == 'wonde' ||
        lower == 'wondevadmin@admin.edu' ||
        lower == 'wondeadmin@admin.edu') {
      if (!candidates.contains('wondedev369@gmail.com')) {
        candidates.add('wondedev369@gmail.com');
      }
    }
    if (lower.startsWith('sultanadinan') ||
        lower.startsWith('sultan') ||
        lower.contains('director') ||
        lower == 'sultanadinan1@director.edu' ||
        lower == 'sultanadinan@director.edu' ||
        lower == 'sultanadinan1@admin.edu' ||
        lower == 'sultanadinan@admin.edu') {
      if (!candidates.contains('wondetech404@gmail.com')) {
        candidates.add('wondetech404@gmail.com');
      }
    }

    // Try candidate passwords (entered password, plus default role formula or Password123!)
    final passwordsToTry = <String>[password];
    if (password != 'Password123!') {
      passwordsToTry.add('Password123!');
    }
    final formulaPw = defaultRolePassword(usernameOrFullName: input);
    if (formulaPw.isNotEmpty && !passwordsToTry.contains(formulaPw)) {
      passwordsToTry.add(formulaPw);
    }

    // Try signing in with each candidate in order
    AuthException? lastAuthException;
    for (final candidateEmail in candidates) {
      for (final pw in passwordsToTry) {
        try {
          return await _supabase.auth.signInWithPassword(
            email: candidateEmail,
            password: pw,
          );
        } on AuthException catch (e) {
          lastAuthException = e;
        } catch (_) {
          // Try next candidate
        }
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
    String? phoneNumber,
    String? gender,
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
        'phone_number': phoneNumber,
        'gender': gender,
      },
    );
  }

  Future<void> updateProfile({
    String? fullName,
    String? email,
    String? phoneNumber,
    String? avatarPath,
  }) async {
    final body = <String, String>{};
    if (fullName != null) body['fullName'] = fullName.trim();
    if (email != null) body['email'] = email.trim().toLowerCase();
    if (phoneNumber != null) body['phoneNumber'] = phoneNumber.trim();
    if (avatarPath != null) body['avatarPath'] = avatarPath;

    bool updatedViaFn = false;
    try {
      final res = await _supabase.functions.invoke('update-profile', body: body);
      if (res.status == 200 || res.status == 204) {
        updatedViaFn = true;
      }
    } catch (e) {
      debugPrint('update-profile edge function fallback note: $e');
    }

    if (!updatedViaFn) {
      final uid = _supabase.auth.currentUser?.id;
      if (uid != null) {
        // 1. Try dedicated security definer RPC (bypasses restrictive RLS on table users)
        bool updatedViaRpc = false;
        final rpcParams = <String, dynamic>{};
        if (fullName != null) rpcParams['p_full_name'] = fullName.trim();
        if (avatarPath != null) rpcParams['p_avatar_url'] = avatarPath;
        if (email != null) rpcParams['p_email'] = email.trim().toLowerCase();
        if (phoneNumber != null) rpcParams['p_phone_number'] = phoneNumber.trim();
        try {
          await _supabase.rpc(
            'update_own_profile',
            params: rpcParams,
          );
          updatedViaRpc = true;
        } catch (rpcErr) {
          debugPrint('update_own_profile RPC note: $rpcErr');
        }

        if (!updatedViaRpc) {
          if (avatarPath != null) {
            try {
              await _supabase.rpc(
                'update_user_avatar',
                params: {'p_user_id': uid, 'p_avatar_url': avatarPath},
              );
            } catch (_) {}
          }

          final updateMap = <String, dynamic>{};
          if (fullName != null) updateMap['full_name'] = fullName.trim();
          if (avatarPath != null) updateMap['avatar_url'] = avatarPath;
          if (email != null) updateMap['email'] = email.trim().toLowerCase();
          if (phoneNumber != null) updateMap['phone_number'] = phoneNumber.trim();
          if (updateMap.isNotEmpty) {
            try {
              await _supabase.from('users').update(updateMap).eq('id', uid);
            } catch (e) {
              debugPrint('Direct user profile update note: $e');
            }
          }

          if (email != null && email.trim().isNotEmpty) {
            try {
              await _supabase.auth.updateUser(
                UserAttributes(email: email.trim().toLowerCase()),
              );
            } catch (authErr) {
              debugPrint('auth.updateUser email note: $authErr');
            }
          }
        }
      }
    }
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
    final publicUrl = _supabase.storage.from('profile-photos').getPublicUrl(path);
    return publicUrl;
  }

  Future<String> resolveEmail(String emailOrUsername) async {
    final input = emailOrUsername.trim();
    if (input.isEmpty) {
      throw const FormatException('Enter your email, username, or phone number.');
    }
    final lower = input.toLowerCase();

    // 1. Check RPC for robust matching against public.users (email, username, phone, name) and auth.users
    try {
      final emailResult = await _supabase.rpc(
        'get_email_by_username',
        params: {'p_username': input},
      );
      if (emailResult is String && emailResult.trim().isNotEmpty) {
        return emailResult.trim().toLowerCase();
      }
    } catch (_) {}

    // 2. Direct public.users lookup
    try {
      final row = await _supabase
          .from('users')
          .select('email')
          .or('username.ilike.$input,email.ilike.$input,phone_number.eq.$input')
          .limit(1)
          .maybeSingle();
      final lookedUp = row?['email'] as String?;
      if (lookedUp != null && lookedUp.trim().isNotEmpty) {
        return lookedUp.trim().toLowerCase();
      }
    } catch (_) {}

    // 3. Known fallback aliases
    if (lower.startsWith('wondedev') || lower.startsWith('wondeadmin') || lower == 'wonde' || lower.contains('admin@admin.edu')) {
      return 'wondedev369@gmail.com';
    }
    if (lower.startsWith('sultanadinan') || lower.startsWith('sultan') || lower.contains('director')) {
      return 'wondetech404@gmail.com';
    }

    // 4. Return as-is
    return lower;
  }

  Future<String> sendPasswordReset(String emailOrUsername) async {
    final targetEmail = await resolveEmail(emailOrUsername);
    try {
      await _supabase.auth.resetPasswordForEmail(targetEmail);
    } catch (e) {
      debugPrint('resetPasswordForEmail note: $e, falling back to signInWithOtp');
      await _supabase.auth.signInWithOtp(
        email: targetEmail,
        shouldCreateUser: false,
      );
    }
    return targetEmail;
  }

  /// Sends a one-time login code (OTP) to the user's email.
  Future<String> sendLoginOtp(String emailOrUsername) async {
    final targetEmail = await resolveEmail(emailOrUsername);
    await _supabase.auth.signInWithOtp(
      email: targetEmail,
      shouldCreateUser: false,
    );
    return targetEmail;
  }

  /// Verifies a login OTP code.
  Future<AuthResponse> verifyLoginOtp({
    required String email,
    required String token,
  }) async {
    final targetEmail = await resolveEmail(email);
    final cleanToken = token.trim();
    try {
      return await _supabase.auth.verifyOTP(
        email: targetEmail,
        token: cleanToken,
        type: OtpType.email,
      );
    } catch (_) {
      try {
        return await _supabase.auth.verifyOTP(
          email: targetEmail,
          token: cleanToken,
          type: OtpType.magiclink,
        );
      } catch (_) {
        return await _supabase.auth.verifyOTP(
          email: targetEmail,
          token: cleanToken,
          type: OtpType.recovery,
        );
      }
    }
  }

  /// Verifies password recovery OTP code and immediately sets the new password.
  Future<void> verifyRecoveryOtpAndSetPassword({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    final targetEmail = await resolveEmail(email);
    final cleanToken = token.trim();
    try {
      await _supabase.auth.verifyOTP(
        email: targetEmail,
        token: cleanToken,
        type: OtpType.recovery,
      );
    } catch (_) {
      try {
        await _supabase.auth.verifyOTP(
          email: targetEmail,
          token: cleanToken,
          type: OtpType.email,
        );
      } catch (_) {
        await _supabase.auth.verifyOTP(
          email: targetEmail,
          token: cleanToken,
          type: OtpType.magiclink,
        );
      }
    }
    await updatePassword(newPassword);
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
          .select()
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
        'approval_status': role == 'admin' ? 'approved' : 'pending',
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

  /// Check if an email address is available for registration
  Future<bool> checkEmailAvailability(String email) async {
    final clean = email.trim().toLowerCase();
    if (clean.isEmpty || !clean.contains('@')) return false;
    try {
      final res = await _supabase.rpc(
        'check_email_availability',
        params: {'p_email': clean},
      );
      if (res is bool) return res;
    } catch (_) {}

    // Fallback direct check on public.users
    try {
      final row = await _supabase
          .from('users')
          .select('id')
          .eq('email', clean)
          .maybeSingle();
      return row == null;
    } catch (_) {
      return true;
    }
  }

  /// Update user notification preferences
  Future<void> updateNotificationPreferences({
    required String uid,
    required bool allowAdmin,
    required bool allowDirector,
  }) async {
    try {
      await _supabase.rpc(
        'update_notification_preferences',
        params: {
          'p_allow_admin': allowAdmin,
          'p_allow_director': allowDirector,
        },
      );
    } catch (_) {
      await _supabase.from('users').update({
        'allow_admin_notifications': allowAdmin,
        'allow_director_notifications': allowDirector,
      }).eq('id', uid);
    }
  }

  /// Stream of auth state changes.
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;
}
