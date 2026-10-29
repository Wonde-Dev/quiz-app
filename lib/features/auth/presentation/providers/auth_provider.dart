import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/di/providers.dart';
import 'package:quiz_app/core/services/auth_service.dart';
import 'package:quiz_app/core/utils/supabase_error_message.dart';
import 'package:quiz_app/shared/models/user.dart';

/// Auth state provider.
final authStateProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

/// Auth state.
class AuthState {
  final AppUser? user;
  final bool isLoading;
  final String? error;
  final String? successMessage;
  final bool needsPasswordChange;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.successMessage,
    this.needsPasswordChange = false,
  });

  AuthState copyWith({
    AppUser? user,
    bool? isLoading,
    String? error,
    String? successMessage,
    bool? needsPasswordChange,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      successMessage: successMessage ?? this.successMessage,
      needsPasswordChange: needsPasswordChange ?? this.needsPasswordChange,
    );
  }

  bool get isLoggedIn => user != null;
  bool get isAdmin => AppRoles.isAdmin(user?.role);
  bool get isSubAdmin => user?.role == AppRoles.subadmin;
  bool get isTeacher => user?.role == AppRoles.teacher;
  bool get isStudent => user?.role == AppRoles.student;
  bool get isPendingApproval => user?.isPendingApproval ?? false;
  bool get isRejected => user?.isRejected ?? false;
}

/// Auth notifier.
class AuthNotifier extends Notifier<AuthState> {
  AuthService get _authService => ref.read(authServiceProvider);

  @override
  AuthState build() {
    Future.microtask(checkSession);
    return const AuthState(isLoading: true);
  }

  void clearMessages() {
    state = AuthState(
      user: state.user,
      isLoading: state.isLoading,
      needsPasswordChange: state.needsPasswordChange,
    );
  }

  void setMessage({String? error, String? successMessage}) {
    state = AuthState(
      user: state.user,
      isLoading: state.isLoading,
      needsPasswordChange: state.needsPasswordChange,
      error: error,
      successMessage: successMessage,
    );
  }

  Future<void> sendPasswordReset(String email) async {
    state = const AuthState(isLoading: true);
    try {
      await _authService.sendPasswordReset(email);
      state = const AuthState(
        successMessage: 'Password reset link sent. Check your email.',
      );
    } catch (error) {
      state = AuthState(error: 'Could not send reset link: $error');
    }
  }

  Future<void> signIn({
    required String emailOrUsername,
    required String password,
    String? expectedRole,
  }) async {
    state = const AuthState(isLoading: true);
    try {
      await _authService.signIn(
        emailOrUsername: emailOrUsername,
        password: password,
      );
      final supabaseUser = _authService.currentUser;
      if (supabaseUser == null) {
        state = const AuthState(error: 'Invalid username or password');
        return;
      }
      final appUser = await _authService.getAppUser(supabaseUser.id);
      if (appUser == null) {
        await _authService.signOut();
        state = const AuthState(error: 'User record not found. Contact admin.');
        return;
      }
      if (!appUser.isActive) {
        await _authService.signOut();
        state = const AuthState(
          error: 'This account is disabled. Contact an administrator.',
        );
        return;
      }
      if (appUser.isPendingApproval) {
        await _authService.signOut();
        state = AuthState(
          error: appUser.role == 'teacher' || appUser.requestedRole == 'teacher'
              ? 'Your teacher registration is pending approval by the School Administrator or Director. Please wait for activation before signing in.'
              : 'Your student registration is pending approval by your class Attendance Teacher (${appUser.attendanceClass ?? appUser.assignedClass ?? "assigned class"}) or Administrator. Please wait for activation before signing in.',
        );
        return;
      }
      if (appUser.isRejected) {
        await _authService.signOut();
        state = const AuthState(
          error:
              'Your registration request was declined. Please contact your school administrator.',
        );
        return;
      }
      if (![
        AppRoles.admin,
        AppRoles.subadmin,
        AppRoles.teacher,
        AppRoles.student,
      ].contains(appUser.role)) {
        await _authService.signOut();
        state = const AuthState(error: 'This account has an unsupported role.');
        return;
      }
      if (expectedRole != null && !appUser.canSignInWithRole(expectedRole)) {
        await _authService.signOut();
        state = AuthState(
          error: appUser.isPendingApproval
              ? 'This account is waiting for ${appUser.requestedRole} access approval and can use its current student access while pending.'
              : 'This account is registered as a ${appUser.role}. Check that your username matches your assigned role.',
        );
        return;
      }
      state = AuthState(
        user: appUser,
        needsPasswordChange: appUser.mustChangePassword,
      );
      try {
        await ref
            .read(auditLogServiceProvider)
            .logForCurrentUser(action: 'user_signed_in');
      } catch (error) {
        state = AuthState(
          user: appUser,
          needsPasswordChange: appUser.mustChangePassword,
          error: 'Signed in, but activity could not be recorded: $error',
        );
      }
    } catch (e) {
      state = AuthState(error: 'Sign in failed: $e');
    }
  }

  Future<void> register({
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
    state = const AuthState(isLoading: true);
    try {
      final response = await _authService.registerAccount(
        fullName: fullName,
        username: username,
        email: email,
        password: password,
        requestedRole: requestedRole,
        schoolId: schoolId,
        sectionId: sectionId,
        requestedGrade: requestedGrade,
        requestedClass: requestedClass,
        requestedSubject: requestedSubject,
        phoneNumber: phoneNumber,
        gender: gender,
      );
      if (response.user == null) {
        throw StateError('The registration did not return a user account.');
      }
      if (response.session != null) {
        await _authService.signOut();
      }
      state = AuthState(
        successMessage: requestedRole == 'teacher'
            ? 'Registration submitted! Your teacher account is pending School Administrator or Director approval before you can sign in with $username.'
            : 'Registration submitted! Your student account is pending approval by your class Attendance Teacher or School Administrator before you can sign in with $username.',
      );
    } catch (error) {
      state = AuthState(
        error: supabaseErrorMessage(error, action: 'Could not create account'),
      );
    }
  }

  Future<List<Map<String, dynamic>>> loadSchools() async {
    final rows = await ref
        .read(supabaseProvider)
        .from('schools')
        .select('id, name')
        .order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> loadSections(String schoolId) async {
    final rows = await ref
        .read(supabaseProvider)
        .from('sections')
        .select('id, grade_id, name, school_grades!inner(name)')
        .eq('school_id', schoolId)
        .order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> loadGrades(String schoolId) async {
    final rows = await ref
        .read(supabaseProvider)
        .from('school_grades')
        .select('id, name')
        .eq('school_id', schoolId)
        .order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> saveFullName(String fullName) async {
    final existing = state.user;
    if (existing == null) return;
    state = AuthState(
      user: existing,
      needsPasswordChange: state.needsPasswordChange,
      isLoading: true,
    );
    try {
      await _authService.updateProfile(fullName: fullName);
      final updatedUser = await _authService.getAppUser(existing.id);
      if (updatedUser == null) {
        throw StateError('Profile could not be reloaded after saving.');
      }
      state = AuthState(
        user: updatedUser,
        needsPasswordChange: updatedUser.mustChangePassword,
      );
    } catch (error) {
      state = AuthState(
        user: existing,
        needsPasswordChange: state.needsPasswordChange,
        error: 'Could not save profile: $error',
      );
      rethrow;
    }
  }

  Future<void> saveAvatar(XFile image) async {
    final existing = state.user;
    if (existing == null) return;
    state = AuthState(
      user: existing,
      needsPasswordChange: state.needsPasswordChange,
      isLoading: true,
    );
    try {
      final path = await _authService.uploadAvatar(
        image: image,
        userId: existing.id,
      );
      await _authService.updateProfile(avatarPath: path);
      final updatedUser = await _authService.getAppUser(existing.id);
      if (updatedUser == null) {
        throw StateError('Profile could not be reloaded after photo upload.');
      }
      state = AuthState(
        user: updatedUser,
        needsPasswordChange: updatedUser.mustChangePassword,
      );
    } catch (error) {
      state = AuthState(
        user: existing,
        needsPasswordChange: state.needsPasswordChange,
        error: 'Could not update profile photo: $error',
      );
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
    state = const AuthState();
  }

  Future<void> updatePassword(String newPassword) async {
    state = AuthState(
      user: state.user,
      isLoading: true,
      needsPasswordChange: state.needsPasswordChange,
    );
    try {
      await _authService.updatePassword(newPassword);
      final supabaseUser = _authService.currentUser;
      if (supabaseUser == null) {
        throw StateError('Your session expired. Sign in again.');
      }
      await _authService.setMustChangePassword(supabaseUser.id, false);
      final appUser = await _authService.getAppUser(supabaseUser.id);
      if (appUser == null) {
        state = const AuthState(
          error: 'User record not found after password update.',
        );
        return;
      }
      state = AuthState(user: appUser, needsPasswordChange: false);
    } catch (e) {
      state = AuthState(
        user: state.user,
        needsPasswordChange: state.needsPasswordChange,
        error: 'Password update failed: $e',
      );
    }
  }

  Future<void> changeOwnPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final existing = state.user;
    if (existing == null) {
      throw StateError('Please sign in to change your password.');
    }
    state = AuthState(
      user: existing,
      needsPasswordChange: state.needsPasswordChange,
      isLoading: true,
    );
    try {
      await _authService.changeOwnPassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      final updatedUser = await _authService.getAppUser(existing.id);
      if (updatedUser == null) {
        throw StateError('Your account could not be reloaded.');
      }
      var message = 'Your password has been changed.';
      try {
        await ref
            .read(auditLogServiceProvider)
            .logForCurrentUser(action: 'password_changed');
      } catch (error) {
        message =
            'Password changed, but activity could not be recorded: $error';
      }
      state = AuthState(
        user: updatedUser,
        needsPasswordChange: updatedUser.mustChangePassword,
        successMessage: message,
      );
    } catch (error) {
      state = AuthState(
        user: existing,
        needsPasswordChange: state.needsPasswordChange,
        error: 'Could not change password: $error',
      );
      rethrow;
    }
  }

  Future<void> checkSession() async {
    final supabaseUser = _authService.currentUser;
    if (supabaseUser == null) {
      state = const AuthState();
      return;
    }
    try {
      final appUser = await _authService.getAppUser(supabaseUser.id);
      if (appUser == null) {
        await _authService.signOut();
        state = const AuthState(error: 'User record not found. Contact admin.');
        return;
      }
      if (!appUser.isActive) {
        await _authService.signOut();
        state = const AuthState(
          error: 'This account is disabled. Contact an administrator.',
        );
        return;
      }
      if (appUser.isPendingApproval) {
        await _authService.signOut();
        state = AuthState(
          error: appUser.role == 'teacher' || appUser.requestedRole == 'teacher'
              ? 'Your teacher registration is pending approval by the School Administrator or Director. Please wait for activation before signing in.'
              : 'Your student registration is pending approval by your class Attendance Teacher (${appUser.attendanceClass ?? appUser.assignedClass ?? "assigned class"}) or Administrator. Please wait for activation before signing in.',
        );
        return;
      }
      if (appUser.isRejected) {
        await _authService.signOut();
        state = const AuthState(
          error:
              'Your registration request was declined. Please contact your school administrator.',
        );
        return;
      }
      state = AuthState(
        user: appUser,
        needsPasswordChange: appUser.mustChangePassword,
      );
    } catch (e) {
      state = AuthState(error: 'Could not restore your session: $e');
    }
  }
}
