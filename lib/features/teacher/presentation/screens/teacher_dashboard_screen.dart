import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/shared/widgets/dashboard_action_grid.dart';
import 'package:quiz_app/shared/widgets/dashboard_welcome_banner.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class TeacherDashboardScreen extends StatelessWidget {
  const TeacherDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DashboardShell(
      title: 'Teacher dashboard',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const DashboardWelcomeBanner(
            subtitle:
                'Create engaging quizzes and help every student make progress.',
          ),
          const SizedBox(height: 24),
          DashboardActionGrid(
            items: [
              DashboardActionItem(
                icon: Icons.add_circle_outline,
                title: 'Prepare a quiz',
                subtitle: 'Write questions and publish an exam',
                onTap: () => context.push('/teacher/quizzes/new'),
              ),
              DashboardActionItem(
                icon: Icons.person_add_alt_1_rounded,
                title: 'Register students',
                subtitle: 'Add students and reset forgotten passwords',
                onTap: () => context.push('/teacher/students'),
              ),
              DashboardActionItem(
                icon: Icons.fact_check_outlined,
                title: 'Quiz results',
                subtitle: 'Review student submissions',
                onTap: () => context.push('/teacher/results'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
