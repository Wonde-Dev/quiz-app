import 'package:supabase_flutter/supabase_flutter.dart';

class PasswordResetResult {
  const PasswordResetResult({
    required this.accountId,
    required this.username,
    required this.temporaryPassword,
  });

  final String accountId;
  final String username;
  final String temporaryPassword;

  factory PasswordResetResult.fromMap(Map<String, dynamic> map) {
    return PasswordResetResult(
      accountId: map['accountId'] as String? ?? map['studentId'] as String,
      username: map['username'] as String,
      temporaryPassword: map['temporaryPassword'] as String,
    );
  }
}

class PasswordResetFailure {
  const PasswordResetFailure({required this.accountId, required this.message});

  final String accountId;
  final String message;

  factory PasswordResetFailure.fromMap(Map<String, dynamic> map) {
    return PasswordResetFailure(
      accountId: map['accountId'] as String? ?? map['studentId'] as String,
      message: map['error'] as String,
    );
  }
}

class PasswordResetBatchResult {
  const PasswordResetBatchResult({
    required this.results,
    required this.failures,
    this.activityWarnings = const [],
  });

  final List<PasswordResetResult> results;
  final List<PasswordResetFailure> failures;
  final List<String> activityWarnings;
}

class StudentPasswordResetService {
  Future<PasswordResetBatchResult> resetAccounts(
    List<String> accountIds,
  ) async {
    if (accountIds.isEmpty) {
      throw ArgumentError.value(
        accountIds,
        'accountIds',
        'Select at least one account',
      );
    }
    final response = await Supabase.instance.client.functions.invoke(
      'reset-student-password',
      body: {'accountIds': accountIds},
    );
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const FormatException(
        'Password reset function returned an invalid response',
      );
    }
    final results = data['results'];
    final failures = data['failures'];
    final activityWarnings = data['activityWarnings'] ?? const [];
    if (results is! List ||
        failures is! List ||
        activityWarnings is! List ||
        activityWarnings.any((warning) => warning is! String)) {
      throw const FormatException(
        'Password reset function returned an invalid result',
      );
    }
    return PasswordResetBatchResult(
      results: results.map((item) {
        if (item is! Map) {
          throw const FormatException(
            'Password reset function returned an invalid student result',
          );
        }
        return PasswordResetResult.fromMap(Map<String, dynamic>.from(item));
      }).toList(),
      failures: failures.map((item) {
        if (item is! Map) {
          throw const FormatException(
            'Password reset function returned an invalid failure result',
          );
        }
        return PasswordResetFailure.fromMap(Map<String, dynamic>.from(item));
      }).toList(),
      activityWarnings: activityWarnings.cast<String>(),
    );
  }

  Future<PasswordResetBatchResult> resetStudents(List<String> studentIds) =>
      resetAccounts(studentIds);
}
