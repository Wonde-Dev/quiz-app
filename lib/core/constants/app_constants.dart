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
  static const admin = 'admin'; // Super Administrator
  static const subadmin = 'subadmin'; // Sub-Admin / Director
  static const teacher = 'teacher';
  static const student = 'student';

  static bool isAdmin(String? role) => role == admin || role == subadmin;
  static bool isTeacher(String? role) => role == teacher;
  static bool isStudent(String? role) => role == student;
}

/// Supabase configuration.
class SupabaseConstants {
  static const supabaseUrl = 'https://vsknxaxrwvpdevocnojn.supabase.co';
  static const supabaseAnonKey = 'sb_publishable_IQKJm6Hy0H8JnUeqjxD1iA_yDpIt6b2';
}