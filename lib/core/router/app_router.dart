import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/features/admin/presentation/screens/admin_dashboard_screen.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/features/auth/presentation/screens/force_change_password_screen.dart';
import 'package:quiz_app/features/auth/presentation/screens/login_screen.dart';
import 'package:quiz_app/features/auth/presentation/screens/onboarding_screen.dart';
import 'package:quiz_app/features/auth/presentation/screens/splash_screen.dart';
import 'package:quiz_app/features/auth/presentation/screens/account_status_screen.dart';
import 'package:quiz_app/features/admin/presentation/screens/account_approvals_screen.dart';
import 'package:quiz_app/features/admin/presentation/screens/admin_register_user_screen.dart';
import 'package:quiz_app/features/admin/presentation/screens/course_assignment_screen.dart';
import 'package:quiz_app/features/admin/presentation/screens/audit_log_screen.dart';
import 'package:quiz_app/features/admin/presentation/screens/teacher_management_screen.dart';
import 'package:quiz_app/features/admin/presentation/screens/school_management_screen.dart';
import 'package:quiz_app/features/about/presentation/screens/about_screen.dart';
import 'package:quiz_app/features/functions/presentation/screens/functions_screen.dart';
import 'package:quiz_app/features/profile/presentation/screens/profile_screen.dart';
import 'package:quiz_app/features/profile/presentation/screens/activity_screen.dart';
import 'package:quiz_app/features/student/presentation/screens/resources_screen.dart';
import 'package:quiz_app/features/student/presentation/screens/student_dashboard_screen.dart';
import 'package:quiz_app/features/student/presentation/screens/quiz_attempt_screen.dart';
import 'package:quiz_app/features/teacher/presentation/screens/teacher_dashboard_screen.dart';
import 'package:quiz_app/features/teacher/presentation/screens/student_management_screen.dart';
import 'package:quiz_app/features/teacher/presentation/screens/quiz_builder_screen.dart';
import 'package:quiz_app/features/teacher/presentation/screens/quiz_results_screen.dart';
import 'package:quiz_app/features/teacher/presentation/screens/reset_password_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authRefresh = ValueNotifier<int>(0);
  ref.listen(authStateProvider, (previous, next) {
    authRefresh.value++;
  });
  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: authRefresh,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final user = authState.user;
      final location = state.matchedLocation;

      if (location == '/splash' || location == '/onboarding') return null;

      if (user == null) {
        return location == '/login' ||
                location.startsWith('/login/') ||
                location == '/register' ||
                location.startsWith('/register/') ||
                location == '/onboarding'
            ? null
            : '/login';
      }
      if (authState.needsPasswordChange) {
        return location == '/change-password' ? null : '/change-password';
      }
      if (location == '/account-status' ||
          location == '/about' ||
          location == '/functions' ||
          location == '/resources' ||
          location == '/onboarding') {
        return null;
      }
      if (location == '/login' ||
          location.startsWith('/login/') ||
          location == '/register' ||
          location.startsWith('/register/') ||
          location == '/change-password') {
        return switch (user.role) {
          AppRoles.admin || AppRoles.subadmin || AppRoles.director || 'director' => '/admin/dashboard',
          AppRoles.teacher => '/teacher/dashboard',
          AppRoles.student => '/student/dashboard',
          _ => '/login',
        };
      }

      // Quiz creation is strictly reserved for teachers:
      if (location == '/teacher/quizzes/new' && user.role != AppRoles.teacher) {
        return (user.role == AppRoles.admin || AppRoles.isDirector(user.role))
            ? '/admin/dashboard'
            : '/student/dashboard';
      }

      // Route protection for School Director:
      if (AppRoles.isDirector(user.role)) {
        if (location == '/admin/audit-logs') {
          return '/admin/dashboard';
        }
        if (location == '/teacher/students' ||
            location == '/admin/classes' ||
            location == '/teacher/reset-passwords') {
          return '/admin/teachers';
        }
        if (location == '/admin/schools' ||
            location.startsWith('/teacher') ||
            location.startsWith('/student')) {
          return '/admin/dashboard';
        }
        return null;
      }

      if (user.role == AppRoles.admin) return null;

      // Attendance teachers have authority to review approvals and register students for their assigned class
      if (user.role == AppRoles.teacher && user.isAttendanceTeacher) {
        if (location == '/admin/approvals' || location == '/admin/register-user') {
          return null;
        }
      }

      if (location.startsWith('/admin') ||
          (user.role == AppRoles.student && location.startsWith('/teacher')) ||
          (user.role == AppRoles.teacher && location.startsWith('/student'))) {
        return switch (user.role) {
          AppRoles.teacher => '/teacher/dashboard',
          AppRoles.student => '/student/dashboard',
          _ => '/login',
        };
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const LoginScreen(registrationPage: true),
      ),
      GoRoute(
        path: '/register/:role',
        redirect: (context, state) => '/register',
        builder: (context, state) => const LoginScreen(registrationPage: true),
      ),
      GoRoute(
        path: '/login/:role',
        redirect: (context, state) => '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/change-password',
        builder: (context, state) => const ForceChangePasswordScreen(),
      ),
      GoRoute(
        path: '/account-status',
        builder: (context, state) => const AccountStatusScreen(),
      ),
      GoRoute(
        path: '/admin/dashboard',
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '/admin/register-user',
        builder: (context, state) => const AdminRegisterUserScreen(),
      ),
      GoRoute(
        path: '/admin/approvals',
        builder: (context, state) => const AccountApprovalsScreen(),
      ),
      GoRoute(
        path: '/admin/classes',
        builder: (context, state) => const CourseAssignmentScreen(),
      ),
      GoRoute(
        path: '/admin/audit-logs',
        builder: (context, state) => const AuditLogScreen(),
      ),
      GoRoute(
        path: '/admin/teachers',
        builder: (context, state) => const TeacherManagementScreen(),
      ),
      GoRoute(
        path: '/admin/schools',
        builder: (context, state) => const SchoolManagementScreen(),
      ),
      GoRoute(
        path: '/teacher/dashboard',
        builder: (context, state) => const TeacherDashboardScreen(),
      ),
      GoRoute(
        path: '/teacher/students',
        builder: (context, state) => const StudentManagementScreen(),
      ),
      GoRoute(
        path: '/teacher/reset-passwords',
        builder: (context, state) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: '/teacher/quizzes/new',
        builder: (context, state) => const QuizBuilderScreen(),
      ),
      GoRoute(
        path: '/teacher/results',
        builder: (context, state) => const QuizResultsScreen(),
      ),
      GoRoute(
        path: '/student/dashboard',
        builder: (context, state) => const StudentDashboardScreen(),
      ),
      GoRoute(
        path: '/student/quiz/:quizId',
        builder: (context, state) =>
            QuizAttemptScreen(quizId: state.pathParameters['quizId']!),
      ),
      GoRoute(
        path: '/about',
        builder: (context, state) => const AboutScreen(),
      ),
      GoRoute(
        path: '/resources',
        builder: (context, state) => const ResourcesScreen(),
      ),
      GoRoute(
        path: '/functions',
        builder: (context, state) => const FunctionsScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/activity',
        builder: (context, state) => const ActivityScreen(),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    authRefresh.dispose();
  });
  return router;
});
