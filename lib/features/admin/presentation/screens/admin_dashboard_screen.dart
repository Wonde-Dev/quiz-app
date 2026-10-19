import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
          Text(
            'Your school, at a glance. Manage accounts, quizzes, and classroom access.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          Text(
            'School management',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          _AdminAction(
            icon: Icons.verified_user_outlined,
            title: 'Review teacher and admin requests',
            onTap: () => context.push('/admin/approvals'),
          ),
          _AdminAction(
            icon: Icons.quiz_outlined,
            title: 'Create a quiz',
            onTap: () => context.push('/teacher/quizzes/new'),
          ),
          _AdminAction(
            icon: Icons.people_outline,
            title: 'Manage accounts',
            onTap: () => context.push('/teacher/students'),
          ),
          _AdminAction(
            icon: Icons.fact_check_outlined,
            title: 'Review quiz results',
            onTap: () => context.push('/teacher/results'),
          ),
          _AdminAction(
            icon: Icons.class_outlined,
            title: 'Manage classes and teacher assignments',
            onTap: () => context.push('/admin/classes'),
          ),
        ],
      ),
    );
  }
}

class _AdminAction extends StatelessWidget {
  const _AdminAction({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
