import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
          Text(
            'Create quizzes and manage student passwords.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Create a quiz'),
              subtitle: const Text('Write questions and publish an exam'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/teacher/quizzes/new'),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: const Text('Review quiz results'),
              subtitle: const Text('See students’ submitted scores'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/teacher/results'),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Manage students'),
              subtitle: const Text(
                'Register students, remove accounts, and reset passwords',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/teacher/students'),
            ),
          ),
        ],
      ),
    );
  }
}
