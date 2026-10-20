import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class QuizResultsScreen extends ConsumerStatefulWidget {
  const QuizResultsScreen({super.key});

  @override
  ConsumerState<QuizResultsScreen> createState() => _QuizResultsScreenState();
}

class _QuizResultsScreenState extends ConsumerState<QuizResultsScreen> {
  late Future<List<Map<String, dynamic>>> _resultsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _selectedQuizFilter = 'all';
  String _selectedStatusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _resultsFuture = _loadResults();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadResults() async {
    final client = Supabase.instance.client;
    final currentUser = ref.read(authStateProvider).user;
    final isAdmin = currentUser?.role == AppRoles.admin;

    var query = client.from('grades').select(
          'id, score, total_points, incorrect_answers, percentage, passed, submitted_at, student_id, quiz_id, '
          'student:users!grades_student_id_fkey(id, full_name, username, email), '
          'quiz:quizzes!grades_quiz_id_fkey(id, title, description, teacher_id, total_points)',
        );

    // If teacher, only load their own quizzes
    if (!isAdmin && currentUser != null) {
      // Filter quizzes by teacher_id
      final teacherQuizzes = await client
          .from('quizzes')
          .select('id')
          .eq('teacher_id', currentUser.id);
      final quizIds = List<Map<String, dynamic>>.from(teacherQuizzes)
          .map((q) => q['id'] as String)
          .toList();
      if (quizIds.isNotEmpty) {
        query = query.inFilter('quiz_id', quizIds);
      }
    }

    final rows = await query.order('submitted_at', ascending: false).limit(250);
    return List<Map<String, dynamic>>.from(rows);
  }

  void _openEvaluationDetails(
    Map<String, dynamic> result,
    VoidCallback onUpdated,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EvaluationDetailsSheet(
        result: result,
        onEvaluationChanged: () {
          setState(() {
            _resultsFuture = _loadResults();
          });
          onUpdated();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DashboardShell(
      title: 'Quiz evaluation & results',
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _resultsFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Could not load quiz results: ${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => setState(() {
                        _resultsFuture = _loadResults();
                      }),
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

          final allResults = snapshot.data!;

          // Collect unique quiz titles for filter dropdown
          final quizTitles = <String>{};
          for (final r in allResults) {
            final q = r['quiz'] as Map<String, dynamic>?;
            if (q != null && q['title'] is String) {
              quizTitles.add(q['title'] as String);
            }
          }

          // Apply filters
          final query = _searchController.text.trim().toLowerCase();
          final filtered = allResults.where((r) {
            final student = r['student'] as Map<String, dynamic>?;
            final quiz = r['quiz'] as Map<String, dynamic>?;
            final studentName =
                (student?['full_name'] as String? ?? '').toLowerCase();
            final username =
                (student?['username'] as String? ?? '').toLowerCase();
            final quizTitle = (quiz?['title'] as String? ?? '');

            if (_selectedQuizFilter != 'all' &&
                quizTitle != _selectedQuizFilter) {
              return false;
            }

            if (_selectedStatusFilter == 'passed' && r['passed'] != true) {
              return false;
            }
            if (_selectedStatusFilter == 'failed' && r['passed'] == true) {
              return false;
            }

            if (query.isNotEmpty) {
              return studentName.contains(query) ||
                  username.contains(query) ||
                  quizTitle.toLowerCase().contains(query);
            }

            return true;
          }).toList();

          // Calculate overview metrics
          final totalCount = allResults.length;
          final passCount =
              allResults.where((r) => r['passed'] == true).length;
          final passRate =
              totalCount > 0 ? (passCount / totalCount * 100).round() : 0;
          final avgScore = totalCount > 0
              ? (allResults.fold<num>(
                          0, (sum, r) => sum + (r['percentage'] as num? ?? 0)) /
                      totalCount)
                  .round()
              : 0;

          return RefreshIndicator(
            onRefresh: () async => setState(() {
              _resultsFuture = _loadResults();
            }),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Top stats overview
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        title: 'Submissions',
                        value: '$totalCount',
                        icon: Icons.people_alt_outlined,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        title: 'Average Score',
                        value: '$avgScore%',
                        icon: Icons.speed_rounded,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        title: 'Pass Rate',
                        value: '$passRate%',
                        icon: Icons.check_circle_outline_rounded,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Search & Filter Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search by student name or quiz...',
                            prefixIcon: const Icon(Icons.search_rounded),
                            isDense: true,
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                                  )
                                : null,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedQuizFilter,
                                decoration: const InputDecoration(
                                  labelText: 'Filter by Quiz',
                                  isDense: true,
                                ),
                                isExpanded: true,
                                items: [
                                  const DropdownMenuItem(
                                    value: 'all',
                                    child: Text('All Quizzes'),
                                  ),
                                  for (final title in quizTitles)
                                    DropdownMenuItem(
                                      value: title,
                                      child: Text(
                                        title,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _selectedQuizFilter = val);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedStatusFilter,
                                decoration: const InputDecoration(
                                  labelText: 'Status',
                                  isDense: true,
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'all',
                                    child: Text('All Statuses'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'passed',
                                    child: Text('Passed Only'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'failed',
                                    child: Text('Not Passed'),
                                  ),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _selectedStatusFilter = val);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Submissions List
                if (filtered.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.fact_check_outlined,
                              size: 48,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              allResults.isEmpty
                                  ? 'No student submissions yet.'
                                  : 'No results match your search and filter.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  for (final result in filtered)
                    _ResultCard(
                      result: result,
                      onTap: () => _openEvaluationDetails(result, () {
                        setState(() {});
                      }),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.onTap});

  final Map<String, dynamic> result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final student = result['student'] as Map<String, dynamic>?;
    final quiz = result['quiz'] as Map<String, dynamic>?;
    final studentName = student?['full_name'] as String? ??
        student?['username'] as String? ??
        'Student';
    final username = student?['username'] as String? ?? '';
    final quizTitle = quiz?['title'] as String? ?? 'Quiz';
    final passed = result['passed'] == true;
    final score = result['score'] ?? 0;
    final total = result['total_points'] ?? 0;
    final percentage = result['percentage'] ?? 0;

    final dateStr = DateTime.tryParse(result['submitted_at'] as String? ?? '')
            ?.toLocal()
            .toString()
            .split('.')
            .first ??
        'Submitted';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: passed
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.orange.withValues(alpha: 0.15),
                    child: Icon(
                      passed ? Icons.check_circle : Icons.rule_rounded,
                      color: passed ? Colors.green.shade700 : Colors.orange.shade800,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          studentName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        if (username.isNotEmpty)
                          Text(
                            '@$username',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: passed
                          ? Colors.green.withValues(alpha: 0.12)
                          : Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: passed ? Colors.green : Colors.red,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      passed ? 'Passed' : 'Failed',
                      style: TextStyle(
                        color: passed ? Colors.green.shade800 : Colors.red.shade800,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          quizTitle,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Score: $score / $total ($percentage%) · $dateStr',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: onTap,
                    icon: const Icon(Icons.assignment_turned_in_outlined, size: 16),
                    label: const Text('Evaluate'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EvaluationDetailsSheet extends StatefulWidget {
  const _EvaluationDetailsSheet({
    required this.result,
    required this.onEvaluationChanged,
  });

  final Map<String, dynamic> result;
  final VoidCallback onEvaluationChanged;

  @override
  State<_EvaluationDetailsSheet> createState() =>
      _EvaluationDetailsSheetState();
}

class _EvaluationDetailsSheetState extends State<_EvaluationDetailsSheet> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _answers = [];
  late int _score;
  late int _totalPoints;
  late int _percentage;
  late bool _passed;

  @override
  void initState() {
    super.initState();
    _score = widget.result['score'] ?? 0;
    _totalPoints = widget.result['total_points'] ?? 0;
    _percentage = widget.result['percentage'] ?? 0;
    _passed = widget.result['passed'] == true;
    _loadAnswers();
  }

  Future<void> _loadAnswers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final studentId = widget.result['student_id'] as String;
      final quizId = widget.result['quiz_id'] as String;

      // Find attempt id
      final attempts = await client
          .from('quiz_attempts')
          .select('id')
          .eq('student_id', studentId)
          .eq('quiz_id', quizId)
          .order('started_at', ascending: false)
          .limit(1);

      if (attempts.isEmpty) {
        // Fallback: load quiz questions directly
        final questions = await client
            .from('questions')
            .select('id, text, type, points, options, correct_answer, explanation')
            .eq('quiz_id', quizId)
            .order('order');

        if (!mounted) return;
        setState(() {
          _answers = List<Map<String, dynamic>>.from(questions).map((q) {
            return {
              'question_text': q['text'],
              'question_type': q['type'],
              'correct_answer': q['correct_answer'],
              'explanation': q['explanation'],
              'options': q['options'],
              'answer_text': 'Completed',
              'is_correct': true,
              'can_override': false,
            };
          }).toList();
          _loading = false;
        });
        return;
      }

      final attemptId = attempts.first['id'] as String;
      final answersRaw = await client
          .from('answers')
          .select(
            'id, question_id, answer_text, is_correct, '
            'question:questions(id, text, type, points, options, correct_answer, explanation)',
          )
          .eq('attempt_id', attemptId);

      if (!mounted) return;
      setState(() {
        _answers = List<Map<String, dynamic>>.from(answersRaw);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load student answers: $e';
        _loading = false;
      });
    }
  }

  Future<void> _toggleCorrect(Map<String, dynamic> answer, bool newCorrect) async {
    final answerId = answer['id'] as String?;
    if (answerId == null) return;

    try {
      final client = Supabase.instance.client;
      await client
          .from('answers')
          .update({'is_correct': newCorrect})
          .eq('id', answerId);

      setState(() {
        answer['is_correct'] = newCorrect;
        final correctCount = _answers.where((a) => a['is_correct'] == true).length;
        _score = correctCount;
        if (_totalPoints > 0) {
          _percentage = ((_score / _totalPoints) * 100).round();
          _passed = _percentage >= 50;
        }
      });

      // Update grade record in database
      final gradeId = widget.result['id'] as String;
      await client.from('grades').update({
        'score': _score,
        'percentage': _percentage,
        'passed': _passed,
        'incorrect_answers': _totalPoints - _score,
        'graded_at': DateTime.now().toIso8601String(),
      }).eq('id', gradeId);

      widget.onEvaluationChanged();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Marked question as ${newCorrect ? 'Correct' : 'Incorrect'}. Score updated.'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update evaluation: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final student = widget.result['student'] as Map<String, dynamic>?;
    final quiz = widget.result['quiz'] as Map<String, dynamic>?;
    final studentName = student?['full_name'] as String? ?? 'Student';
    final quizTitle = quiz?['title'] as String? ?? 'Quiz';

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Evaluation: $studentName',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        quizTitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _passed
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$_score / $_totalPoints ($_percentage%)',
                    style: TextStyle(
                      color: _passed ? Colors.green.shade800 : Colors.red.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _answers.isEmpty
                        ? const Center(
                            child: Text('No question answer breakdown available.'),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _answers.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 12),
                            itemBuilder: (ctx, i) {
                              final item = _answers[i];
                              final question =
                                  item['question'] as Map<String, dynamic>?;
                              final qText = question?['text'] as String? ??
                                  item['question_text'] as String? ??
                                  'Question ${i + 1}';
                              final qType = question?['type'] as String? ??
                                  item['question_type'] as String? ??
                                  'multiple_choice';
                              final sAnswer = item['answer_text'] as String? ??
                                  '(no answer provided)';
                              final isCorrect = item['is_correct'] == true;
                              final cAnswer = question?['correct_answer'] as String? ??
                                  item['correct_answer'] as String? ??
                                  '';
                              final explanation = question?['explanation'] as String? ??
                                  item['explanation'] as String? ??
                                  '';

                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          CircleAvatar(
                                            radius: 14,
                                            backgroundColor: isCorrect
                                                ? Colors.green.withValues(alpha: 0.2)
                                                : Colors.red.withValues(alpha: 0.2),
                                            child: Icon(
                                              isCorrect
                                                  ? Icons.check
                                                  : Icons.close,
                                              size: 16,
                                              color: isCorrect
                                                  ? Colors.green.shade800
                                                  : Colors.red.shade800,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Q${i + 1}: $qText',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  qType == 'short_answer'
                                                      ? 'Short answer / Fill in the blank'
                                                      : qType == 'true_false'
                                                          ? 'True / False'
                                                          : 'Multiple choice',
                                                  style: theme.textTheme.bodySmall?.copyWith(
                                                    color: theme.colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: isCorrect
                                              ? Colors.green.withValues(alpha: 0.08)
                                              : Colors.red.withValues(alpha: 0.08),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Student Answer: $sAnswer',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color: isCorrect
                                                    ? Colors.green.shade900
                                                    : Colors.red.shade900,
                                              ),
                                            ),
                                            if (cAnswer.isNotEmpty && !isCorrect) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                'Correct Answer: $cAnswer',
                                                style: TextStyle(
                                                  color: Colors.green.shade800,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      if (explanation.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          'Explanation: $explanation',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.onSurfaceVariant,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                      if (item['id'] != null) ...[
                                        const SizedBox(height: 12),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            Text(
                                              'Teacher grading:',
                                              style: theme.textTheme.bodySmall,
                                            ),
                                            const SizedBox(width: 8),
                                            OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: isCorrect
                                                    ? Colors.green
                                                    : null,
                                                side: BorderSide(
                                                  color: isCorrect
                                                      ? Colors.green
                                                      : Colors.grey.shade400,
                                                ),
                                              ),
                                              icon: const Icon(
                                                Icons.thumb_up_alt_outlined,
                                                size: 16,
                                              ),
                                              label: const Text('Correct'),
                                              onPressed: isCorrect
                                                  ? null
                                                  : () => _toggleCorrect(item, true),
                                            ),
                                            const SizedBox(width: 8),
                                            OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: !isCorrect
                                                    ? Colors.red
                                                    : null,
                                                side: BorderSide(
                                                  color: !isCorrect
                                                      ? Colors.red
                                                      : Colors.grey.shade400,
                                                ),
                                              ),
                                              icon: const Icon(
                                                Icons.thumb_down_alt_outlined,
                                                size: 16,
                                              ),
                                              label: const Text('Incorrect'),
                                              onPressed: !isCorrect
                                                  ? null
                                                  : () => _toggleCorrect(item, false),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
