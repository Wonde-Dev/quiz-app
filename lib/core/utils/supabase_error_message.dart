import 'package:supabase_flutter/supabase_flutter.dart';

String supabaseErrorMessage(Object error, {required String action}) {
  if (error is PostgrestException) {
    final code = error.code;
    final detail = error.details?.toString().trim();
    final hint = error.hint?.trim();
    if (code == '23505') {
      return 'That value is already in use. Try a different username or email.';
    }
    if (code == '23503') {
      return 'A selected school, grade, or section no longer exists. Refresh the choices and try again.';
    }
    if (code == '42501') {
      return 'The database denied this action. Apply the latest Supabase migrations and check the account role.';
    }
    if (code == 'PGRST116') {
      return 'A required database record was not found. Refresh the page and check that the latest migrations are applied.';
    }
    return '$action failed: ${error.message}'
        '${code == null ? '' : ' (database code $code)'}'
        '${detail == null || detail.isEmpty ? '' : '\n$detail'}'
        '${hint == null || hint.isEmpty ? '' : '\nHint: $hint'}';
  }
  if (error is AuthException) {
    final message = error.message;
    if (message.toLowerCase().contains('database error saving new user')) {
      return 'Supabase could not save this account. The username or email may already be used, or the latest username-format migration may not be applied.';
    }
    return '$action failed: $message';
  }
  if (error is FunctionException) {
    final status = error.status;
    final details = error.details?.toString() ?? '';
    if (status == 404 || details.contains('NOT_FOUND') || details.contains('not found')) {
      return '$action failed: The Supabase Edge Function was not found on your project (404).\n'
          'Please deploy it using the Supabase CLI:\n'
          '  supabase functions deploy manage-account';
    }
    return '$action failed: ${error.details ?? error.reasonPhrase ?? error}';
  }
  final errorStr = error.toString();
  if (errorStr.contains('Requested function was not found') ||
      errorStr.contains('code: NOT_FOUND')) {
    return '$action failed: The Supabase Edge Function was not found on your project (404).\n'
        'Please deploy it using the Supabase CLI:\n'
        '  supabase functions deploy manage-account';
  }
  return '$action failed: $error';
}
