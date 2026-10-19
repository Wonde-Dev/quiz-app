import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class StudentDashboardScreen extends ConsumerWidget {
  const StudentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    return DashboardShell(
      title: 'Student dashboard',
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : _StudentQuizList(studentId: user.id),
    );
  }
}

class _StudentQuizList extends StatefulWidget {
  const _StudentQuizList({required this.studentId});

  final String studentId;

  @override
  State<_StudentQuizList> createState() => _StudentQuizListState();
}

class _StudentQuizListState extends State<_StudentQuizList> {
  late Future<
    ({List<Map<String, dynamic>> quizzes, List<Map<String, dynamic>> grades})
  >
  _dashboard;

  @override
  void initState() {
    super.initState();
    _dashboard = _loadDashboard();
  }

  Future<
    ({List<Map<String, dynamic>> quizzes, List<Map<String, dynamic>> grades})
  >
  _loadDashboard() async {
    final client = Supabase.instance.client;
    final responses = await Future.wait([
      client
          .from('quizzes')
          .select('id, title, description, time_limit_minutes, total_points')
          .eq('is_published', true)
          .order('created_at', ascending: false),
      client
          .from('grades')
          .select('quiz_id, score, total_points, percentage, passed')
          .eq('student_id', widget.studentId)
          .order('submitted_at', ascending: false),
    ]);
    return (
      quizzes: List<Map<String, dynamic>>.from(responses[0]),
      grades: List<Map<String, dynamic>>.from(responses[1]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => setState(() => _dashboard = _loadDashboard()),
      child:
          FutureBuilder<
            ({
              List<Map<String, dynamic>> quizzes,
              List<Map<String, dynamic>> grades,
            })
          >(
            future: _dashboard,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      'Could not load quizzes and results: ${snapshot.error}',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () =>
                          setState(() => _dashboard = _loadDashboard()),
                      child: const Text('Try again'),
                    ),
                  ],
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final result = snapshot.data!;
              final quizTitles = {
                for (final quiz in result.quizzes)
                  quiz['id'] as String: quiz['title'] as String? ?? 'Quiz',
              };
              final gradesByQuiz = <String, Map<String, dynamic>>{};
              for (final grade in result.grades) {
                gradesByQuiz.putIfAbsent(
                  grade['quiz_id'] as String,
                  () => grade,
                );
              }
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'My results',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (result.grades.isEmpty)
                    const ListTile(title: Text('No quiz results yet.')),
                  for (final grade in result.grades)
                    ListTile(
                      leading: Icon(
                        grade['passed'] == true
                            ? Icons.check_circle_outline
                            : Icons.assignment_turned_in_outlined,
                      ),
                      title: Text(
                        quizTitles[grade['quiz_id']] ?? 'Quiz result',
                      ),
                      subtitle: Text(
                        '${grade['score']} / ${grade['total_points']} points · '
                        '${grade['percentage'] ?? 0}%',
                      ),
                    ),
                  const Divider(height: 32),
                  Text(
                    'Available quizzes',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (result.quizzes.isEmpty)
                    const ListTile(
                      title: Text('No published quizzes are available.'),
                    ),
                  for (final quiz in result.quizzes)
                    Card(
                      child: ListTile(
                        title: Text(quiz['title'] as String? ?? 'Quiz'),
                        subtitle: Text(
                          quiz['description'] as String? ?? 'Start this quiz',
                        ),
                        trailing: gradesByQuiz.containsKey(quiz['id'])
                            ? const Chip(label: Text('Submitted'))
                            : const Icon(Icons.play_arrow),
                        onTap: gradesByQuiz.containsKey(quiz['id'])
                            ? null
                            : () => context.push('/student/quiz/${quiz['id']}'),
                      ),
                    ),
                ],
              );
            },
          ),
    );
  }
}
