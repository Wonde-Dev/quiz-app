/// Application-wide constants.
class AppConstants {
  static const appName = 'QuizApp';
  static const defaultPassingScorePercent = 60;
  static const maxWarningsBeforeAutoSubmit = 2;
  static const defaultTimePerQuestionSeconds = 60;
  static const maxQuestionsPerQuiz = 100;
  static const passwordMinLength = 6;
  static const clipboardClearDelayMs = 100;
}

/// Role constants used throughout the app.
class AppRoles {
  static const admin = 'admin';
  static const teacher = 'teacher';
  static const student = 'student';
}

/// Supabase configuration.
class SupabaseConstants {
  static const supabaseUrl = 'https://vsknxaxrwvpdevocnojn.supabase.co';
  static const supabaseAnonKey = 'sb_publishable_IQKJm6Hy0H8JnUeqjxD1iA_yDpIt6b2';
}