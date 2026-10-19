import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class QuizResultsScreen extends StatefulWidget {
  const QuizResultsScreen({super.key});

  @override
  State<QuizResultsScreen> createState() => _QuizResultsScreenState();
}

class _QuizResultsScreenState extends State<QuizResultsScreen> {
  late Future<List<Map<String, dynamic>>> _results;

  @override
  void initState() {
    super.initState();
    _results = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await Supabase.instance.client
        .from('grades')
        .select(
          'id, score, total_points, incorrect_answers, percentage, passed, submitted_at, '
          'student:users!grades_student_id_fkey(full_name, username), '
          'quiz:quizzes!grades_quiz_id_fkey(title)',
        )
        .order('submitted_at', ascending: false)
        .limit(200);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Widget build(BuildContext context) {
    return DashboardShell(
      title: 'Quiz results',
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _results,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Could not load quiz results: ${snapshot.error}'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => setState(() => _results = _load()),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final results = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => setState(() => _results = _load()),
            child: results.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      const Center(
                        child: Text('No submitted quiz results yet.'),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        'Student submissions and automatic scores',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      for (final result in results) _ResultCard(result: result),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final student = result['student'] as Map<String, dynamic>?;
    final quiz = result['quiz'] as Map<String, dynamic>?;
    final studentName =
        student?['full_name'] as String? ??
        student?['username'] as String? ??
        'Student';
    final quizTitle = quiz?['title'] as String? ?? 'Quiz';
    final passed = result['passed'] == true;

    return Card(
      child: ListTile(
        leading: Icon(
          passed ? Icons.check_circle_outline : Icons.assignment_outlined,
          color: passed ? Theme.of(context).colorScheme.primary : null,
        ),
        title: Text('$studentName · $quizTitle'),
        subtitle: Text(
          '${result['score']} / ${result['total_points']} points'
          '${result['incorrect_answers'] == null ? '' : ' · ${result['incorrect_answers']} incorrect'}'
          ' · ${result['percentage'] ?? 0}%'
          ' · ${DateTime.tryParse(result['submitted_at'] as String? ?? '')?.toLocal() ?? 'Submitted'}',
        ),
        isThreeLine: true,
        trailing: Chip(label: Text(passed ? 'Passed' : 'Not passed')),
      ),
    );
  }
}
