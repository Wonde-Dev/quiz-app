import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class FunctionsScreen extends ConsumerWidget {
  const FunctionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = ref.watch(authStateProvider).user;
    final role = user?.role ?? AppRoles.student;

    final (roleTitle, roleSubtitle) = switch (role) {
      AppRoles.admin => (
          'Admin System Functions',
          'Manage users, review registrations, allocate classes, and inspect audit logs.'
        ),
      AppRoles.teacher => (
          'Teacher Academic Functions',
          'Prepare quizzes, evaluate student results, manage rosters, and reset passwords.'
        ),
      _ => (
          'Student Academic Functions',
          'Take exams, review completed results, check grades, and manage your account.'
        ),
    };

    return DashboardShell(
      title: 'Functions & Tools',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Header Card with Functions Illustration
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFF10B981).withValues(alpha: 0.35),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.16),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.4)
                      : const Color(0xFF0F172A).withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Illustration Background
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/functions.jpeg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: const Color(0xFF064E3B),
                    ),
                  ),
                ),
                // Gradient Tint for High Contrast
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark
                            ? [
                                const Color(0xF5064E3B),
                                const Color(0xF80F172A),
                                const Color(0xF0022C22),
                              ]
                            : [
                                const Color(0xEE064E3B),
                                const Color(0xEA0F172A),
                                const Color(0xDC047857),
                              ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Icon(
                          Icons.grid_view_rounded,
                          color: Color(0xFF34D399),
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'SYSTEM CAPABILITIES',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              roleTitle,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              roleSubtitle,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFE2E8F0),
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'Available Tools & Actions',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),

          if (role == AppRoles.admin) ...[
            _FunctionTile(
              icon: Icons.person_add_alt_1_rounded,
              color: const Color(0xFF10B981),
              title: 'Register New User (Admin, Teacher, Student)',
              subtitle: 'Directly create and activate Administrator, Teacher, or Student accounts.',
              onTap: () => context.push('/admin/register-user'),
            ),
            _FunctionTile(
              icon: Icons.how_to_reg_rounded,
              color: const Color(0xFF059669),
              title: 'Review Registration Requests',
              subtitle: 'Approve or decline pending student and faculty registration requests.',
              onTap: () => context.push('/admin/approvals'),
            ),
            _FunctionTile(
              icon: Icons.co_present_rounded,
              color: const Color(0xFF059669),
              title: 'Faculty Directory & Passwords',
              subtitle: 'View teachers, assign subjects, reset passwords, or remove faculty.',
              onTap: () => context.push('/admin/teachers'),
            ),
            _FunctionTile(
              icon: Icons.people_outline_rounded,
              color: const Color(0xFF0D9488),
              title: 'Register & Manage Students',
              subtitle: 'Create student accounts, view enrolled rosters, or delete accounts.',
              onTap: () => context.push('/teacher/students'),
            ),
            _FunctionTile(
              icon: Icons.lock_reset_rounded,
              color: const Color(0xFFF59E0B),
              title: 'Reset User Passwords',
              subtitle: 'Issue secure temporary passwords for faculty and students.',
              onTap: () => context.push('/teacher/reset-passwords'),
            ),
            _FunctionTile(
              icon: Icons.class_outlined,
              color: const Color(0xFF6366F1),
              title: 'Class & Section Allocations',
              subtitle: 'Configure school grades, classroom sections, and course allocations.',
              onTap: () => context.push('/admin/classes'),
            ),
            _FunctionTile(
              icon: Icons.history_rounded,
              color: const Color(0xFF0F172A),
              title: 'Audit Surveillance & System Logs',
              subtitle: 'Inspect chronological system activity, exam events, and logins.',
              onTap: () => context.push('/admin/audit-logs'),
            ),
          ] else if (role == AppRoles.teacher) ...[
            _FunctionTile(
              icon: Icons.add_circle_outline_rounded,
              color: const Color(0xFF10B981),
              title: 'Prepare & Publish a Quiz',
              subtitle: 'Build exams targeted by grade and section with time limits & diagrams.',
              onTap: () => context.push('/teacher/quizzes/new'),
            ),
            _FunctionTile(
              icon: Icons.upload_file_rounded,
              color: const Color(0xFF0284C7),
              title: 'Class Worksheets & Exam PDFs',
              subtitle: 'Upload and distribute worksheets, test question papers, and study PDFs for your classes.',
              onTap: () => context.push('/resources'),
            ),
            _FunctionTile(
              icon: Icons.fact_check_rounded,
              color: const Color(0xFF059669),
              title: 'Evaluate Quizzes & Results',
              subtitle: 'Review student attempts question-by-question, evaluate work, and adjust scores.',
              onTap: () => context.push('/teacher/results'),
            ),
            _FunctionTile(
              icon: Icons.people_outline_rounded,
              color: const Color(0xFF0D9488),
              title: 'Register Class Students',
              subtitle: 'Enroll students in your sections and provide initial credentials.',
              onTap: () => context.push('/teacher/students'),
            ),
            _FunctionTile(
              icon: Icons.lock_reset_rounded,
              color: const Color(0xFFF59E0B),
              title: 'Reset Student Passwords',
              subtitle: 'One-tap password resets for students enrolled in your courses.',
              onTap: () => context.push('/teacher/reset-passwords'),
            ),
          ] else ...[
            // Student
            _FunctionTile(
              icon: Icons.quiz_rounded,
              color: const Color(0xFF10B981),
              title: 'Available Quizzes & Exams',
              subtitle: 'Access upcoming assessments and exams prepared for your grade & class.',
              onTap: () => context.go('/student/dashboard'),
            ),
            _FunctionTile(
              icon: Icons.picture_as_pdf_rounded,
              color: const Color(0xFF0284C7),
              title: 'My Class Worksheets & PDFs',
              subtitle: 'Download and study official worksheets and exam papers uploaded by your teachers.',
              onTap: () => context.push('/resources'),
            ),
            _FunctionTile(
              icon: Icons.insights_rounded,
              color: const Color(0xFF059669),
              title: 'My Exam Results & History',
              subtitle: 'Inspect past quiz scores, feedback, percentages, and performance graphs.',
              onTap: () => context.push('/activity'),
            ),
            _FunctionTile(
              icon: Icons.person_rounded,
              color: const Color(0xFF0D9488),
              title: 'My Profile & Credentials',
              subtitle: 'Update your profile photo, change password, and view school info.',
              onTap: () => context.push('/profile'),
            ),
            _FunctionTile(
              icon: Icons.info_outline_rounded,
              color: const Color(0xFF0F172A),
              title: 'About Ciro Schools Portal',
              subtitle: 'Review institutional integrity rules, anti-cheat security, and release notes.',
              onTap: () => context.push('/about'),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _FunctionTile extends StatelessWidget {
  const _FunctionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

