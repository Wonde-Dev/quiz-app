import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/utils/role_username.dart';

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

    // 1. Try edge function first
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'reset-student-password',
        body: {'accountIds': accountIds},
      );
      final data = response.data;
      if (data is Map<String, dynamic> && data['results'] is List) {
        final results = (data['results'] as List)
            .map((item) => PasswordResetResult.fromMap(
                Map<String, dynamic>.from(item as Map)))
            .toList();
        final failures = ((data['failures'] as List?) ?? [])
            .map((item) => PasswordResetFailure.fromMap(
                Map<String, dynamic>.from(item as Map)))
            .toList();
        final activityWarnings =
            ((data['activityWarnings'] as List?) ?? []).cast<String>();
        return PasswordResetBatchResult(
          results: results,
          failures: failures,
          activityWarnings: activityWarnings,
        );
      }
    } catch (e) {
      debugPrint('reset-student-password edge function fallback note: $e');
    }

    // 2. Direct database RPC / fallback for all selected accounts
    final client = Supabase.instance.client;
    final results = <PasswordResetResult>[];
    final failures = <PasswordResetFailure>[];

    for (final id in accountIds) {
      try {
        final row = await client
            .from('users')
            .select('id, username, full_name, role')
            .eq('id', id)
            .maybeSingle();

        final username = row?['username'] as String? ?? id;
        final fullName = row?['full_name'] as String? ?? '';
        final role = row?['role'] as String? ?? 'student';
        final newPassword = defaultRolePassword(
          usernameOrFullName: username.isNotEmpty ? username : fullName,
          role: role,
        );

        bool updatedInAuth = false;
        try {
          await client.rpc('reset_user_password_admin', params: {
            'p_user_id': id,
            'p_password': newPassword,
          });
          updatedInAuth = true;
        } catch (rpcErr) {
          debugPrint('reset_user_password_admin RPC error: $rpcErr');
          failures.add(PasswordResetFailure(
            accountId: id,
            message: rpcErr.toString(),
          ));
          continue;
        }

        if (updatedInAuth) {
          results.add(PasswordResetResult(
            accountId: id,
            username: username,
            temporaryPassword: newPassword,
          ));
        }
      } catch (err) {
        failures.add(PasswordResetFailure(
          accountId: id,
          message: err.toString(),
        ));
      }
    }

    return PasswordResetBatchResult(
      results: results,
      failures: failures,
      activityWarnings: const [],
    );
  }

  Future<PasswordResetBatchResult> resetStudents(List<String> studentIds) =>
      resetAccounts(studentIds);

  Future<PasswordResetResult> resetPasswordDirect({
    required String accountId,
    required String username,
    required String role,
  }) async {
    final batch = await resetAccounts([accountId]);
    if (batch.results.isNotEmpty) {
      return batch.results.first;
    }
    final failureMsg = batch.failures.isNotEmpty
        ? batch.failures.first.message
        : 'Failed to reset password';
    throw Exception(failureMsg);
  }
}
