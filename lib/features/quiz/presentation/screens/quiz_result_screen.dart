import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/shared/models/grade.dart';

class QuizResultScreen extends StatelessWidget {
  const QuizResultScreen({
    required this.grade,
    required this.quizTitle,
    this.feedback = const [],
    super.key,
  });

  final Grade grade;
  final String quizTitle;
  final List<Map<String, dynamic>> feedback;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiz result'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      grade.passed
                          ? Icons.check_circle_outline
                          : Icons.assignment_turned_in_outlined,
                      size: 64,
                      color: grade.passed
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      quizTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${grade.score} / ${grade.totalPoints}',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text('${grade.percentage ?? grade.percent.round()}%'),
                    if (feedback.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Chip(
                        avatar: const Icon(Icons.close_outlined, size: 18),
                        label: Text(
                          '${feedback.where((item) => item['isCorrect'] != true).length} incorrect '
                          'of ${feedback.length} questions',
                        ),
                      ),
                    ],
                    if (feedback.any(
                      (item) =>
                          (item['explanation'] as String?)?.isNotEmpty == true,
                    )) ...[
                      const Divider(height: 32),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Answer explanations',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final item in feedback)
                        if ((item['explanation'] as String?)?.isNotEmpty ==
                            true)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              item['isCorrect'] == true
                                  ? Icons.check_circle_outline
                                  : Icons.info_outline,
                            ),
                            title: Text(item['question'] as String? ?? ''),
                            subtitle: Text(item['explanation'] as String),
                          ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => context.go('/student/dashboard'),
                      child: const Text('Back to dashboard'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
