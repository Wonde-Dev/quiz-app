import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/features/admin/presentation/screens/admin_dashboard_screen.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/features/auth/presentation/screens/force_change_password_screen.dart';
import 'package:quiz_app/features/auth/presentation/screens/login_screen.dart';
import 'package:quiz_app/features/auth/presentation/screens/account_status_screen.dart';
import 'package:quiz_app/features/admin/presentation/screens/account_approvals_screen.dart';
import 'package:quiz_app/features/admin/presentation/screens/course_assignment_screen.dart';
import 'package:quiz_app/features/profile/presentation/screens/profile_screen.dart';
import 'package:quiz_app/features/profile/presentation/screens/activity_screen.dart';
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
    initialLocation: '/login',
    refreshListenable: authRefresh,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final user = authState.user;
      final location = state.matchedLocation;

      if (user == null) {
        return location == '/login' ||
                location.startsWith('/login/') ||
                location == '/register' ||
                location.startsWith('/register/')
            ? null
            : '/login';
      }
      if (authState.needsPasswordChange) {
        return location == '/change-password' ? null : '/change-password';
      }
      if (location == '/account-status') {
        return switch (user.role) {
          AppRoles.admin => '/admin/dashboard',
          AppRoles.teacher => '/teacher/dashboard',
          AppRoles.student => '/student/dashboard',
          _ => '/login',
        };
      }
      if (location == '/login' ||
          location.startsWith('/login/') ||
          location == '/register' ||
          location.startsWith('/register/') ||
          location == '/change-password') {
        return switch (user.role) {
          AppRoles.admin => '/admin/dashboard',
          AppRoles.teacher => '/teacher/dashboard',
          AppRoles.student => '/student/dashboard',
          _ => '/login',
        };
      }

      if (user.role == AppRoles.admin) return null;
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
        path: '/admin/approvals',
        builder: (context, state) => const AccountApprovalsScreen(),
      ),
      GoRoute(
        path: '/admin/classes',
        builder: (context, state) => const CourseAssignmentScreen(),
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
