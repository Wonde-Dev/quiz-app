import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/shared/models/grade.dart';
import 'package:quiz_app/shared/models/question.dart';

class QuizResultScreen extends StatelessWidget {
  const QuizResultScreen({
    required this.grade,
    required this.quizTitle,
    this.questions = const [],
    this.studentAnswers = const {},
    this.feedback = const [],
    super.key,
  });

  final Grade grade;
  final String quizTitle;
  final List<Question> questions;
  final Map<String, dynamic> studentAnswers;
  final List<Map<String, dynamic>> feedback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final percent = grade.percentage ?? grade.percent.round();
    final passed = grade.passed;
    final statusColor = passed ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    // Merge feedback and questions into a unified review item list
    final reviewItems = _buildReviewItems();

    final correctCount = reviewItems.where((r) => r.isCorrect).length;
    final incorrectCount = reviewItems.length - correctCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exam Result & Answer Review'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Score Summary Card
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
                            border: Border.all(color: statusColor, width: 2.5),
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
                          margin: const EdgeInsets.symmetric(vertical: 14),
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
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
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
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
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Correct / Incorrect Summary Chips
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFFA7F3D0)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF10B981)),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$correctCount Correct',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF047857),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFFFECACA)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.cancel_rounded, size: 16, color: Color(0xFFEF4444)),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$incorrectCount Incorrect',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFB91C1C),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Review Section Header
                Row(
                  children: [
                    const Icon(Icons.fact_check_rounded, color: Color(0xFF10B981), size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'Answer Evaluation & Review',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Green buttons indicate correct answers, while red buttons indicate incorrect choices.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 16),

                // List of Questions with Green / Red Buttons
                for (int i = 0; i < reviewItems.length; i++)
                  _QuestionReviewCard(
                    index: i + 1,
                    item: reviewItems[i],
                    isDark: isDark,
                  ),

                const SizedBox(height: 20),

                // Back to Dashboard
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => context.go('/student/dashboard'),
                  icon: const Icon(Icons.dashboard_rounded, size: 20),
                  label: const Text(
                    'Return to Student Dashboard',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_ReviewItem> _buildReviewItems() {
    final items = <_ReviewItem>[];

    // Priority: If questions list is available
    if (questions.isNotEmpty) {
      for (final q in questions) {
        final rawAns = studentAnswers[q.id];
        final fb = feedback.firstWhere(
          (f) => f['questionId'] == q.id || f['question'] == q.text,
          orElse: () => <String, dynamic>{},
        );

        bool isCorrect = fb['isCorrect'] == true;
        if (!fb.containsKey('isCorrect')) {
          if (q.type == 'multiple_choice' || q.type == 'true_false') {
            final correctOpt = q.options.where((o) => o.isCorrect).firstOrNull;
            isCorrect = correctOpt != null && _extractSelectedId(rawAns) == correctOpt.id;
          } else if (q.type == 'short_answer') {
            final text = _extractTextAnswer(rawAns);
            isCorrect = q.correctAnswer != null &&
                text.trim().toLowerCase() == q.correctAnswer!.trim().toLowerCase();
          }
        }

        items.add(_ReviewItem(
          id: q.id,
          questionText: q.cleanText,
          type: q.type,
          points: q.points,
          explanation: q.explanation ?? fb['explanation'] as String?,
          imageUrl: q.imageUrl,
          options: q.options.map((o) => _OptionReview(
            id: o.id,
            text: o.text,
            isCorrect: o.isCorrect,
          )).toList(),
          studentRawAnswer: rawAns,
          expectedAnswer: q.correctAnswer ?? fb['correctAnswerText']?.toString(),
          isCorrect: isCorrect,
        ));
      }
      return items;
    }

    // Fallback: Build from feedback array
    for (int i = 0; i < feedback.length; i++) {
      final fb = feedback[i];
      final optsRaw = fb['options'] as List?;
      final opts = <_OptionReview>[];
      if (optsRaw != null) {
        for (final o in optsRaw) {
          if (o is Map) {
            opts.add(_OptionReview(
              id: o['id']?.toString() ?? '',
              text: o['text']?.toString() ?? '',
              isCorrect: o['is_correct'] == true,
            ));
          }
        }
      }
      final rawAns = fb['selectedAnswer'] ?? studentAnswers[fb['questionId'] ?? ''];

      items.add(_ReviewItem(
        id: fb['questionId']?.toString() ?? '$i',
        questionText: fb['question']?.toString() ?? 'Question ${i + 1}',
        type: fb['type']?.toString() ?? (opts.isNotEmpty ? 'multiple_choice' : 'short_answer'),
        points: (fb['points'] as num?)?.toInt() ?? 1,
        explanation: fb['explanation']?.toString(),
        imageUrl: fb['imageUrl']?.toString(),
        options: opts,
        studentRawAnswer: rawAns,
        expectedAnswer: fb['correctAnswerText']?.toString() ?? fb['correctAnswer']?.toString(),
        isCorrect: fb['isCorrect'] == true,
      ));
    }

    return items;
  }

  static String _extractSelectedId(dynamic raw) {
    if (raw == null) return '';
    if (raw is String) {
      if (raw.trim().startsWith('{') && raw.trim().endsWith('}')) {
        try {
          final parsed = jsonDecode(raw) as Map<String, dynamic>;
          return parsed['option_id']?.toString() ??
              parsed['selected']?.toString() ??
              parsed['text']?.toString() ??
              raw;
        } catch (_) {
          return raw;
        }
      }
      return raw;
    }
    if (raw is Map) {
      return raw['option_id']?.toString() ??
          raw['selected']?.toString() ??
          raw['text']?.toString() ??
          '';
    }
    return raw.toString();
  }

  static String _extractTextAnswer(dynamic raw) {
    if (raw == null) return '';
    if (raw is String) {
      if (raw.trim().startsWith('{') && raw.trim().endsWith('}')) {
        try {
          final parsed = jsonDecode(raw) as Map<String, dynamic>;
          return parsed['text']?.toString() ?? raw;
        } catch (_) {
          return raw;
        }
      }
      return raw;
    }
    if (raw is Map && raw.containsKey('text')) {
      return raw['text']?.toString() ?? '';
    }
    return raw.toString();
  }
}

class _ReviewItem {
  final String id;
  final String questionText;
  final String type;
  final int points;
  final String? explanation;
  final String? imageUrl;
  final List<_OptionReview> options;
  final dynamic studentRawAnswer;
  final String? expectedAnswer;
  final bool isCorrect;

  const _ReviewItem({
    required this.id,
    required this.questionText,
    required this.type,
    required this.points,
    this.explanation,
    this.imageUrl,
    this.options = const [],
    this.studentRawAnswer,
    this.expectedAnswer,
    required this.isCorrect,
  });
}

class _OptionReview {
  final String id;
  final String text;
  final bool isCorrect;

  const _OptionReview({
    required this.id,
    required this.text,
    required this.isCorrect,
  });
}

class _QuestionReviewCard extends StatelessWidget {
  const _QuestionReviewCard({
    required this.index,
    required this.item,
    required this.isDark,
  });

  final int index;
  final _ReviewItem item;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final statusColor = item.isCorrect ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final selectedOptionId = QuizResultScreen._extractSelectedId(item.studentRawAnswer);
    final studentText = QuizResultScreen._extractTextAnswer(item.studentRawAnswer);
    final attachedImageUrl = _extractAttachedImage(item.studentRawAnswer);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: item.isCorrect
              ? const Color(0xFFA7F3D0)
              : const Color(0xFFFECACA),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Question Header (Question #, Result Badge, Points)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Q$index',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: item.isCorrect
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: item.isCorrect
                          ? const Color(0xFFA7F3D0)
                          : const Color(0xFFFECACA),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        size: 14,
                        color: statusColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.isCorrect ? 'Correct (+${item.points} pts)' : 'Incorrect (0 pts)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  '${item.points} pt${item.points == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Question Text
            Text(
              item.questionText,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            if (item.imageUrl != null && item.imageUrl!.isNotEmpty) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  item.imageUrl!,
                  height: 160,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Multiple Choice / True False: Render buttons with Green / Red styling
            if (item.options.isNotEmpty) ...[
              for (final opt in item.options)
                _buildOptionButton(
                  context: context,
                  option: opt,
                  isSelectedByStudent: selectedOptionId == opt.id || selectedOptionId == opt.text,
                  isOptionCorrect: opt.isCorrect,
                  isDark: isDark,
                ),
            ] else ...[
              // Descriptive / Short Answer
              _buildDescriptiveReview(
                context: context,
                studentText: studentText,
                expectedAnswer: item.expectedAnswer,
                attachedImageUrl: attachedImageUrl,
                isCorrect: item.isCorrect,
                isDark: isDark,
              ),
            ],

            // Explanation box if present
            if (item.explanation != null && item.explanation!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_outline_rounded, size: 16, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Explanation',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.explanation!,
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
          ],
        ),
      ),
    );
  }

  Widget _buildOptionButton({
    required BuildContext context,
    required _OptionReview option,
    required bool isSelectedByStudent,
    required bool isOptionCorrect,
    required bool isDark,
  }) {
    Color bgColor;
    Color borderColor;
    Color textColor;
    IconData? icon;
    String? badgeText;
    Color badgeColor = const Color(0xFF10B981);

    if (isSelectedByStudent && isOptionCorrect) {
      bgColor = isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5);
      borderColor = const Color(0xFF10B981);
      textColor = isDark ? Colors.white : const Color(0xFF065F46);
      icon = Icons.check_circle_rounded;
      badgeText = 'Your Answer · Correct';
      badgeColor = const Color(0xFF10B981);
    } else if (isSelectedByStudent && !isOptionCorrect) {
      bgColor = isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFEF2F2);
      borderColor = const Color(0xFFEF4444);
      textColor = isDark ? Colors.white : const Color(0xFF991B1B);
      icon = Icons.cancel_rounded;
      badgeText = 'Your Choice · Incorrect';
      badgeColor = const Color(0xFFEF4444);
    } else if (isOptionCorrect) {
      bgColor = isDark ? const Color(0xFF022C22) : const Color(0xFFF0FDF4);
      borderColor = const Color(0xFF34D399);
      textColor = isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857);
      icon = Icons.check_circle_outline_rounded;
      badgeText = 'Correct Answer';
      badgeColor = const Color(0xFF10B981);
    } else {
      bgColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
      borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
      textColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
      badgeColor = Colors.transparent;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: isSelectedByStudent || isOptionCorrect ? 1.8 : 1.0),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: badgeColor),
            const SizedBox(width: 10),
          ] else ...[
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 1.5),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              option.text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelectedByStudent || isOptionCorrect ? FontWeight.w700 : FontWeight.w500,
                color: textColor,
              ),
            ),
          ),
          if (badgeText != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: badgeColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDescriptiveReview({
    required BuildContext context,
    required String studentText,
    required String? expectedAnswer,
    required String? attachedImageUrl,
    required bool isCorrect,
    required bool isDark,
  }) {
    final statusColor = isCorrect ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Student Answer Box
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isCorrect
                ? (isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5))
                : (isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFEF2F2)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: statusColor, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    size: 18,
                    color: statusColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isCorrect ? 'Your Written Answer (Correct)' : 'Your Written Answer (Incorrect)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                studentText.trim().isEmpty ? 'No answer entered' : studentText,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              if (attachedImageUrl != null && attachedImageUrl.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  'Attached student work/diagram:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    attachedImageUrl,
                    height: 120,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Text('Attached image preview'),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Expected Answer Box if student got it wrong
        if (!isCorrect && expectedAnswer != null && expectedAnswer.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF022C22) : const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF10B981), width: 1.5),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle_outline_rounded, size: 18, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Expected / Correct Answer:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF047857),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        expectedAnswer,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String? _extractAttachedImage(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      if (raw.trim().startsWith('{') && raw.trim().endsWith('}')) {
        try {
          final parsed = jsonDecode(raw) as Map<String, dynamic>;
          return parsed['image_url'] as String?;
        } catch (_) {
          return null;
        }
      }
    }
    if (raw is Map) {
      return raw['image_url'] as String?;
    }
    return null;
  }
}
