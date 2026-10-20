import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/shared/widgets/dashboard_action_grid.dart';
import 'package:quiz_app/shared/widgets/dashboard_welcome_banner.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DashboardShell(
      title: 'Administrator',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const DashboardWelcomeBanner(
            subtitle: 'Your school, at a glance. Keep classrooms, people, and quizzes connected.',
          ),
          const SizedBox(height: 24),
          Text(
            'School management',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          DashboardActionGrid(
            items: [
              DashboardActionItem(
                icon: Icons.person_add_alt_1_rounded,
                title: 'Register users',
                subtitle: 'Create student or teacher accounts',
                onTap: () => context.push('/teacher/students'),
              ),
              DashboardActionItem(
                icon: Icons.verified_user_outlined,
                title: 'Review requests',
                subtitle: 'Review teacher role requests',
                onTap: () => context.push('/admin/approvals'),
              ),
              DashboardActionItem(
                icon: Icons.quiz_outlined,
                title: 'Create a quiz',
                subtitle: 'Prepare and publish a quiz',
                onTap: () => context.push('/teacher/quizzes/new'),
              ),
              DashboardActionItem(
                icon: Icons.fact_check_outlined,
                title: 'Quiz results',
                subtitle: 'Review student submissions',
                onTap: () => context.push('/teacher/results'),
              ),
              DashboardActionItem(
                icon: Icons.class_outlined,
                title: 'Classes',
                subtitle: 'Manage classes and teacher assignments',
                onTap: () => context.push('/admin/classes'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
