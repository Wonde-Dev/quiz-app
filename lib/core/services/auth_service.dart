import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/models/user.dart';

/// Handles authentication via Supabase Auth.
class AuthService {
  SupabaseClient get _supabase => Supabase.instance.client;

  /// Sign in with email or a legacy school username.
  Future<AuthResponse> signIn({
    required String emailOrUsername,
    required String password,
  }) async {
    final input = emailOrUsername.trim();
    final isAppAlias = RegExp(
      r'^[A-Za-z0-9]{1,50}@(admin|teacher|student|a|t|s)\.edu$',
      caseSensitive: false,
    ).hasMatch(input);
    final isEmail = input.contains('@') && !isAppAlias;
    if (!isEmail || isAppAlias) {
      final response = await _supabase.functions.invoke(
        'login-by-username',
        body: {'username': input, 'password': password},
      );
      if (response.data is! Map<String, dynamic>) {
        throw const FormatException(
          'Sign-in service returned an invalid response',
        );
      }
      final result = response.data as Map<String, dynamic>;
      final refreshToken = result['refresh_token'];
      if (refreshToken is! String || refreshToken.isEmpty) {
        throw const FormatException('Sign-in service returned no session');
      }
      return _supabase.auth.setSession(refreshToken);
    }
    return await _supabase.auth.signInWithPassword(
      email: input.toLowerCase(),
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
    final response = await _supabase
        .from('users')
        .select(
          'id, email, username, role, school_id, full_name, avatar_url, '
          'must_change_password, requested_role, approval_status, is_active, '
          'created_at, last_login',
        )
        .eq('id', uid)
        .maybeSingle();
    if (response == null) return null;
    return AppUser.fromMap(response);
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
