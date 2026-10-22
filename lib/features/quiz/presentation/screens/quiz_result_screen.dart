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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final percent = grade.percentage ?? grade.percent.round();
    final passed = grade.passed;
    final statusColor = passed ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exam Result & Score'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              children: [
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      width: 1.2,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Status Icon & Badge
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: statusColor.withValues(alpha: 0.12),
                            border: Border.all(color: statusColor, width: 2),
                          ),
                          child: Icon(
                            passed ? Icons.check_circle_rounded : Icons.cancel_outlined,
                            size: 46,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          quizTitle,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),

                        // Score percentage container
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                '$percent%',
                                style: theme.textTheme.displayMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: statusColor,
                                  letterSpacing: -1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Score: ${grade.score} out of ${grade.totalPoints} points',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  passed ? 'EXAM PASSED' : 'NEEDS IMPROVEMENT',
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Performance breakdown chips
                        if (feedback.isNotEmpty) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Chip(
                                avatar: const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF10B981)),
                                label: Text(
                                  '${feedback.where((item) => item['isCorrect'] == true).length} Correct',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Chip(
                                avatar: const Icon(Icons.close_rounded, size: 16, color: Color(0xFFEF4444)),
                                label: Text(
                                  '${feedback.where((item) => item['isCorrect'] != true).length} Incorrect',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ],

                        // Answer Explanations
                        if (feedback.any(
                          (item) =>
                              (item['explanation'] as String?)?.isNotEmpty == true,
                        )) ...[
                          const Divider(height: 36),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: [
                                const Icon(Icons.menu_book_rounded, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Question Explanations',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          for (final item in feedback)
                            if ((item['explanation'] as String?)?.isNotEmpty == true)
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      item['isCorrect'] == true
                                          ? Icons.check_circle_outline
                                          : Icons.info_outline_rounded,
                                      size: 18,
                                      color: item['isCorrect'] == true
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFFF59E0B),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['question'] as String? ?? 'Question',
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            item['explanation'] as String,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                        ],

                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () => context.go('/student/dashboard'),
                            icon: const Icon(Icons.dashboard_rounded, size: 18),
                            label: const Text('Back to Dashboard'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
