import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/services/audit_log_service.dart';
import 'package:quiz_app/core/services/quiz_attempt_service.dart';
import 'package:quiz_app/core/services/security/copy_paste_blocker.dart';
import 'package:quiz_app/shared/widgets/secure_screen_wrapper.dart';
import 'package:quiz_app/features/quiz/presentation/screens/quiz_result_screen.dart';

class QuizAttemptScreen extends StatefulWidget {
  const QuizAttemptScreen({required this.quizId, super.key});

  final String quizId;

  @override
  State<QuizAttemptScreen> createState() => _QuizAttemptScreenState();
}

class _QuizAttemptScreenState extends State<QuizAttemptScreen>
    with WidgetsBindingObserver {
  final _service = QuizAttemptService();
  late Future<QuizAttemptData> _attempt;
  final Map<String, dynamic> _answers = {};
  final Set<int> _flaggedQuestions = {};
  bool _warnedAt5Minutes = false;
  Timer? _timer;
  QuizAttemptData? _data;
  int _currentIndex = 0;
  int? _secondsRemaining;
  bool _isSubmitting = false;
  String? _submitError;
  int _appSwitchViolations = 0;
  bool _showingViolationDialog = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attempt = _service.start(widget.quizId);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isSubmitting || _data == null) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _appSwitchViolations++;
      unawaited(
        AuditLogService().logForCurrentUser(
          action: 'anti_cheat_app_switch_detected',
          details: {
            'quiz_id': widget.quizId,
            'strike': _appSwitchViolations,
            'lifecycle_state': state.name,
          },
        ),
      );

      if (_appSwitchViolations >= 2) {
        if (!_isSubmitting) {
          unawaited(
            _submit(
              autoSubmittedReason:
                  'Exam automatically submitted due to repeated app/tab switching violations.',
            ),
          );
        }
      } else {
        _showAppSwitchWarning();
      }
    }
  }

  void _showAppSwitchWarning() {
    if (_showingViolationDialog || !mounted) return;
    _showingViolationDialog = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(
          Icons.warning_amber_rounded,
          size: 48,
          color: Colors.red,
        ),
        title: const Text(
          'Anti-Cheat Warning',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
        ),
        content: Text(
          'Leaving this screen to switch apps, browser tabs, or use external AI tools is strictly forbidden!\n\n'
          'Violation Strike: $_appSwitchViolations of 2.\n\n'
          'If you switch away again, your exam will be automatically submitted immediately.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.of(ctx).pop();
              _showingViolationDialog = false;
            },
            child: const Text('I Understand — Return to Exam'),
          ),
        ],
      ),
    );
  }

  void _startTimer(QuizAttemptData data) {
    if (_data != null) return;
    _data = data;
    final minutes = (data.quiz.timeLimitMinutes != null &&
            data.quiz.timeLimitMinutes! > 0)
        ? data.quiz.timeLimitMinutes!
        : 30;
    _secondsRemaining = minutes * 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _secondsRemaining == null) return;
      if (_secondsRemaining! <= 1) {
        timer.cancel();
        if (!_isSubmitting) {
          unawaited(_submit(autoSubmittedReason: 'Time has expired. Exam auto-submitted.'));
        }
      } else {
        setState(() {
          _secondsRemaining = _secondsRemaining! - 1;
          if (_secondsRemaining == 300 && !_warnedAt5Minutes) {
            _warnedAt5Minutes = true;
            _showFiveMinuteWarning();
          }
        });
      }
    });
  }

  void _showFiveMinuteWarning() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.alarm_on_rounded, color: Colors.white),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '5 minutes remaining! Please review and finalize your answers.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool _isQuestionAnswered(String questionId) {
    final val = _answers[questionId];
    if (val == null) return false;
    if (val is String && val.trim().isEmpty) return false;
    return true;
  }

  void _openQuestionNavigator(QuizAttemptData data) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final total = data.questions.length;
        final answeredCount = data.questions.where((q) => _isQuestionAnswered(q.id)).length;
        final flaggedCount = _flaggedQuestions.length;
        final unansweredCount = total - answeredCount;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Question Navigator',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _navigatorLegend(
                      color: const Color(0xFF10B981),
                      label: 'Answered ($answeredCount)',
                    ),
                    _navigatorLegend(
                      color: Colors.amber,
                      label: 'Flagged ($flaggedCount)',
                    ),
                    _navigatorLegend(
                      color: Colors.grey.shade400,
                      label: 'Unanswered ($unansweredCount)',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.45,
                  ),
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.1,
                    ),
                    itemCount: total,
                    itemBuilder: (context, idx) {
                      final isAnswered = _isQuestionAnswered(data.questions[idx].id);
                      final isFlagged = _flaggedQuestions.contains(idx);
                      final isCurrent = idx == _currentIndex;

                      Color bgColor = Colors.grey.shade100;
                      Color textColor = Colors.black87;
                      Color borderColor = Colors.transparent;

                      if (isAnswered) {
                        bgColor = const Color(0xFF10B981).withValues(alpha: 0.18);
                        textColor = const Color(0xFF047857);
                      }
                      if (isFlagged) {
                        bgColor = Colors.amber.withValues(alpha: 0.2);
                        textColor = Colors.amber.shade900;
                      }
                      if (isCurrent) {
                        borderColor = Theme.of(context).colorScheme.primary;
                      }

                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.pop(ctx);
                          setState(() => _currentIndex = idx);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isCurrent ? borderColor : Colors.grey.shade300,
                              width: isCurrent ? 2 : 1,
                            ),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Text(
                                '${idx + 1}',
                                style: TextStyle(
                                  fontWeight: isCurrent ? FontWeight.w900 : FontWeight.bold,
                                  fontSize: 15,
                                  color: textColor,
                                ),
                              ),
                              if (isFlagged)
                                const Positioned(
                                  top: 3,
                                  right: 3,
                                  child: Icon(Icons.flag_rounded, size: 12, color: Colors.amber),
                                ),
                              if (isAnswered && !isFlagged)
                                const Positioned(
                                  top: 3,
                                  right: 3,
                                  child: Icon(Icons.check_rounded, size: 12, color: Color(0xFF059669)),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _confirmAndSubmit();
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Finish & Submit Exam'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _navigatorLegend({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Future<void> _confirmAndSubmit() async {
    if (_isSubmitting || _data == null) return;
    final total = _data!.questions.length;
    final answered = _answers.values.where((v) {
      if (v == null) return false;
      if (v is String && v.trim().isEmpty) return false;
      return true;
    }).length;

    final shouldSubmit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.help_outline_rounded, size: 36),
        title: const Text('Submit exam?'),
        content: Text(
          'You have answered $answered of $total questions.\n\n'
          'Are you sure you want to finish and submit your answers?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Review answers'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Submit now'),
          ),
        ],
      ),
    );

    if (shouldSubmit == true) {
      await _submit();
    }
  }

  Future<void> _submit({String? autoSubmittedReason}) async {
    if (_isSubmitting || _data == null) return;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    _timer?.cancel();
    try {
      final result = await _service.submit(widget.quizId, _answers);
      if (!mounted) return;
      if (autoSubmittedReason != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(autoSubmittedReason),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) => QuizResultScreen(
            grade: result.grade,
            quizTitle: _data!.quiz.title,
            questions: _data!.questions,
            studentAnswers: _answers,
            feedback: result.feedback,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _submitError = 'Could not submit quiz: $error';
        });
      }
    }
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _isSubmitting || _data == null) return;
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(
              Icons.exit_to_app_rounded,
              size: 40,
              color: Colors.orange,
            ),
            title: const Text('Exit & Submit Exam?'),
            content: const Text(
              'Leaving this exam now will immediately submit your current answers as-is.\n\n'
              'Anti-Cheat Protection: You cannot return to or retake this quiz once you leave.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Continue Exam'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Submit & Exit'),
              ),
            ],
          ),
        );
        if (shouldExit == true) {
          await _submit(
            autoSubmittedReason: 'Student chose to exit exam prematurely.',
          );
        }
      },
      child: SelectionContainer.disabled(
        child: FutureBuilder<QuizAttemptData>(
        future: _attempt,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(title: const Text('Quiz unavailable')),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Could not start this quiz: ${snapshot.error}'),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => context.go('/student/dashboard'),
                        child: const Text('Back'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final data = snapshot.data!;
          if (data.questions.isEmpty) {
            return Scaffold(
              appBar: AppBar(
                title: Text(data.quiz.title),
                automaticallyImplyLeading: false,
              ),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.quiz_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        'No questions found in this quiz',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'This quiz does not have any questions available yet or questions are being set up. Please contact your instructor.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => context.go('/student/dashboard'),
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text('Back to Dashboard'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          _startTimer(data);
          final question = data.questions[_currentIndex];
          return SecureScreenWrapper(
            onAutoSubmit: () => unawaited(_submit()),
            onScreenshotLog: (event) {
              unawaited(AuditLogService().logForCurrentUser(
                action: 'screen_capture_blocked',
                details: {'quiz_id': widget.quizId, 'event': event},
              ));
            },
            child: Scaffold(
              appBar: AppBar(
                title: Text(data.quiz.title),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.grid_view_rounded),
                    tooltip: 'Exam Question Navigator',
                    onPressed: () => _openQuestionNavigator(data),
                  ),
                  if (_secondsRemaining != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: (_secondsRemaining! < 180)
                                ? Colors.red.withValues(alpha: 0.15)
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                size: 18,
                                color: (_secondsRemaining! < 180)
                                    ? Colors.red
                                    : Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _formatTime(_secondsRemaining!),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: (_secondsRemaining! < 180)
                                          ? Colors.red
                                          : null,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  LinearProgressIndicator(
                    value: (_currentIndex + 1) / data.questions.length,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  Builder(
                    builder: (context) {
                      final desc = data.quiz.description?.trim() ?? '';
                      final pdfRegex = RegExp(r'\[Attached Exam PDF:\s*([^\]]+)\]\(([^)]+)\)');
                      final match = pdfRegex.firstMatch(desc);
                      final cleanDesc = desc.replaceAll(pdfRegex, '').trim();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (cleanDesc.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              cleanDesc,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                          if (match != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFBBF7D0)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.picture_as_pdf_rounded,
                                    color: Color(0xFF10B981),
                                    size: 24,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          match.group(1) ?? 'Attached Exam Question Paper',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const Text(
                                          'Official Worksheet / Exam Paper attached by teacher',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF047857),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  FilledButton.tonal(
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(0, 34),
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                    ),
                                    onPressed: () {
                                      final url = match.group(2);
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Exam Paper PDF'),
                                          content: Text(
                                            'Exam worksheet document:\n${match.group(1)}\n\nURL: $url',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(ctx),
                                              child: const Text('Close'),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                    child: const Text('View PDF'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Question ${_currentIndex + 1} of ${data.questions.length}',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              _flaggedQuestions.contains(_currentIndex)
                                  ? Icons.flag_rounded
                                  : Icons.flag_outlined,
                              color: _flaggedQuestions.contains(_currentIndex)
                                  ? Colors.amber.shade700
                                  : Colors.grey,
                              size: 20,
                            ),
                            tooltip: _flaggedQuestions.contains(_currentIndex)
                                ? 'Flagged for review (Tap to unflag)'
                                : 'Flag for review',
                            onPressed: () {
                              setState(() {
                                if (_flaggedQuestions.contains(_currentIndex)) {
                                  _flaggedQuestions.remove(_currentIndex);
                                } else {
                                  _flaggedQuestions.add(_currentIndex);
                                }
                              });
                            },
                          ),
                        ],
                      ),
                      Text(
                        question.type == 'short_answer' || question.type == 'description'
                            ? 'Descriptive / Short answer'
                            : question.type == 'fill_in_blank' || question.type == 'blank_space'
                                ? 'Fill in the Blank'
                                : question.type == 'true_false'
                                    ? 'True / False'
                                    : 'Multiple choice',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CopyPasteBlocker(
                    child: Text(
                      question.cleanText,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  if (question.imageUrl != null && question.imageUrl!.isNotEmpty)
                    _buildQuestionDiagramWidget(question.imageUrl!),
                  const SizedBox(height: 20),
                  if (question.type == 'short_answer' ||
                      question.type == 'description' ||
                      question.type == 'fill_in_blank' ||
                      question.type == 'blank_space')
                    _DescriptionQuestionInput(
                      key: ValueKey(question.id),
                      questionId: question.id,
                      initialAnswer: _answers[question.id],
                      onAnswerChanged: (newAnswer) {
                        _answers[question.id] = newAnswer;
                      },
                    )
                  else ...[
                    RadioGroup<String>(
                      groupValue: _selectedOptionFor(_answers[question.id]),
                      onChanged: (value) {
                        if (_isSubmitting) return;
                        final currentRaw = _answers[question.id];
                        String? img;
                        if (currentRaw is String && currentRaw.trim().startsWith('{')) {
                          try {
                            final parsed = jsonDecode(currentRaw) as Map<String, dynamic>;
                            img = parsed['image_url'] as String?;
                          } catch (_) {}
                        } else if (currentRaw is Map) {
                          img = currentRaw['image_url']?.toString();
                        }
                        if (img != null && img.isNotEmpty) {
                          setState(() => _answers[question.id] = jsonEncode({
                            'option_id': value,
                            'image_url': img,
                          }));
                        } else {
                          setState(() => _answers[question.id] = value);
                        }
                      },
                      child: Column(
                        children: [
                          for (final option in question.options)
                            RadioListTile<String>(
                              title: Text(option.text),
                              value: option.id,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ChoiceWorkAttachment(
                      key: ValueKey('work_${question.id}'),
                      questionId: question.id,
                      currentAnswer: _answers[question.id],
                      onAnswerChanged: (newAnswer) {
                        setState(() => _answers[question.id] = newAnswer);
                      },
                    ),
                  ],
                  if (_submitError != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _submitError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      if (_currentIndex > 0)
                        OutlinedButton.icon(
                          onPressed: _isSubmitting
                              ? null
                              : () => setState(() => _currentIndex--),
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text('Previous'),
                        ),
                      const Spacer(),
                      if (_currentIndex < data.questions.length - 1)
                        FilledButton.icon(
                          onPressed: _isSubmitting
                              ? null
                              : () => setState(() => _currentIndex++),
                          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                          label: const Text('Next'),
                        )
                      else
                        FilledButton.icon(
                          onPressed: _isSubmitting ? null : _confirmAndSubmit,
                          icon: const Icon(Icons.check_circle_outline, size: 20),
                          label: _isSubmitting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Submit quiz'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

  String? _selectedOptionFor(dynamic raw) {
    if (raw is String) {
      if (raw.trim().startsWith('{') && raw.trim().endsWith('}')) {
        try {
          final parsed = jsonDecode(raw) as Map<String, dynamic>;
          return parsed['option_id'] as String? ?? parsed['selected'] as String?;
        } catch (_) {
          return raw;
        }
      }
      return raw;
    } else if (raw is Map) {
      return raw['option_id'] as String? ?? raw['selected'] as String?;
    }
    return null;
  }

  Widget _buildQuestionDiagramWidget(String imageUrl) {
    return Container(
      margin: const EdgeInsets.only(top: 14, bottom: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.insert_chart_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Question Reference Diagram / Graph',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => _showDiagramPreview(imageUrl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: _buildCommonImage(imageUrl),
            ),
          ),
        ],
      ),
    );
  }

  void _showDiagramPreview(String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBar(
              title: const Text('Diagram / Graph Reference'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: InteractiveViewer(
                  maxScale: 4.0,
                  child: _buildCommonImage(url),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommonImage(String url) {
    if (url.startsWith('data:image')) {
      final parts = url.split(',');
      if (parts.length > 1) {
        return Image.memory(
          base64Decode(parts[1]),
          fit: BoxFit.contain,
        );
      }
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Could not load image reference.')),
      ),
    );
  }
}

/// An interactive, accessible input widget for descriptive / short answer questions
/// that supports both written explanations and attached images (drawings, photos, diagrams).
class _DescriptionQuestionInput extends StatefulWidget {
  const _DescriptionQuestionInput({
    required this.questionId,
    required this.initialAnswer,
    required this.onAnswerChanged,
    super.key,
  });

  final String questionId;
  final dynamic initialAnswer;
  final ValueChanged<String> onAnswerChanged;

  @override
  State<_DescriptionQuestionInput> createState() =>
      _DescriptionQuestionInputState();
}

class _DescriptionQuestionInputState extends State<_DescriptionQuestionInput> {
  late final TextEditingController _textController;
  String? _imageUrl;
  bool _uploading = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    String initText = '';
    String? initImage;

    final raw = widget.initialAnswer;
    if (raw is String && raw.isNotEmpty) {
      if (raw.trim().startsWith('{') && raw.trim().endsWith('}')) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          initText = map['text'] as String? ?? '';
          initImage = map['image_url'] as String?;
        } catch (_) {
          initText = raw;
        }
      } else {
        initText = raw;
      }
    } else if (raw is Map) {
      initText = raw['text']?.toString() ?? '';
      initImage = raw['image_url']?.toString();
    }

    _textController = TextEditingController(text: initText);
    _imageUrl = initImage;
    _textController.addListener(_notifyChange);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _notifyChange() {
    final text = _textController.text;
    if (_imageUrl != null && _imageUrl!.isNotEmpty) {
      widget.onAnswerChanged(
        jsonEncode({'text': text, 'image_url': _imageUrl}),
      );
    } else {
      widget.onAnswerChanged(text);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (image == null) return;

      setState(() => _uploading = true);
      final bytes = await image.readAsBytes();
      final ext = image.name.split('.').last.toLowerCase();
      final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';

      String url = '';
      try {
        final client = Supabase.instance.client;
        final userId = client.auth.currentUser?.id ?? 'guest';
        final path =
            'quiz-attachments/$userId/${widget.questionId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
        await client.storage.from('profile-photos').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: mimeType, upsert: true),
            );
        url = client.storage.from('profile-photos').getPublicUrl(path);
      } catch (_) {
        // Resilient fallback to Data URI
        url = 'data:$mimeType;base64,${base64Encode(bytes)}';
      }

      if (!mounted) return;
      setState(() {
        _imageUrl = url;
        _uploading = false;
      });
      _notifyChange();
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not attach image: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _enterImageUrl() async {
    final urlController = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter image link'),
        content: TextField(
          controller: urlController,
          decoration: const InputDecoration(
            labelText: 'Image URL (http:// or https://)',
            hintText: 'https://example.com/diagram.png',
            prefixIcon: Icon(Icons.link_rounded),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(urlController.text.trim()),
            child: const Text('Attach'),
          ),
        ],
      ),
    );

    if (url != null && url.isNotEmpty && mounted) {
      setState(() => _imageUrl = url);
      _notifyChange();
    }
  }

  void _removeImage() {
    setState(() => _imageUrl = null);
    _notifyChange();
  }

  void _showFullImage(BuildContext context) {
    if (_imageUrl == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBar(
              title: const Text('Attached Image Preview'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: InteractiveViewer(
                  maxScale: 4.0,
                  child: _buildImageWidget(_imageUrl!),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageWidget(String url) {
    if (url.startsWith('data:image')) {
      final parts = url.split(',');
      if (parts.length > 1) {
        return Image.memory(
          base64Decode(parts[1]),
          fit: BoxFit.contain,
        );
      }
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Could not load image.')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _textController,
          minLines: 3,
          maxLines: 7,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Your Explanation / Answer',
            hintText: 'Type your explanation, steps, or answer here...',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 14),

        // Image attachment section
        if (_uploading) ...[
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Attaching image...'),
                ],
              ),
            ),
          ),
        ] else if (_imageUrl != null && _imageUrl!.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Image attached to this question',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove attached image',
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red, size: 20),
                      onPressed: _removeImage,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => _showFullImage(context),
                  borderRadius: BorderRadius.circular(8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 140,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildImageWidget(_imageUrl!),
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.zoom_in_rounded,
                                      color: Colors.white, size: 14),
                                  SizedBox(width: 4),
                                  Text(
                                    'Tap to expand',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
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
              ],
            ),
          ),
        ] else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.photo_camera_rounded, size: 18),
                label: const Text('Take photo'),
                onPressed: () => _pickImage(ImageSource.camera),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.photo_library_rounded, size: 18),
                label: const Text('Upload image'),
                onPressed: () => _pickImage(ImageSource.gallery),
              ),
              TextButton.icon(
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('Image link'),
                onPressed: _enterImageUrl,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Attach a photo of handwritten calculations, drawing, or diagram if needed.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Allows attaching handwritten calculations, graphs, or diagrams to multiple choice
/// and true/false questions as requested.
class _ChoiceWorkAttachment extends StatefulWidget {
  const _ChoiceWorkAttachment({
    required this.questionId,
    required this.currentAnswer,
    required this.onAnswerChanged,
    super.key,
  });

  final String questionId;
  final dynamic currentAnswer;
  final ValueChanged<dynamic> onAnswerChanged;

  @override
  State<_ChoiceWorkAttachment> createState() => _ChoiceWorkAttachmentState();
}

class _ChoiceWorkAttachmentState extends State<_ChoiceWorkAttachment> {
  String? _imageUrl;
  bool _uploading = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _extractImage();
  }

  @override
  void didUpdateWidget(covariant _ChoiceWorkAttachment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentAnswer != oldWidget.currentAnswer) {
      _extractImage();
    }
  }

  void _extractImage() {
    final raw = widget.currentAnswer;
    if (raw is String && raw.trim().startsWith('{') && raw.trim().endsWith('}')) {
      try {
        final parsed = jsonDecode(raw) as Map<String, dynamic>;
        _imageUrl = parsed['image_url'] as String?;
      } catch (_) {}
    } else if (raw is Map) {
      _imageUrl = raw['image_url']?.toString();
    }
  }

  String? _currentOptionId() {
    final raw = widget.currentAnswer;
    if (raw is String) {
      if (raw.trim().startsWith('{') && raw.trim().endsWith('}')) {
        try {
          final parsed = jsonDecode(raw) as Map<String, dynamic>;
          return parsed['option_id'] as String? ?? parsed['selected'] as String?;
        } catch (_) {
          return raw;
        }
      }
      return raw;
    } else if (raw is Map) {
      return raw['option_id'] as String? ?? raw['selected'] as String?;
    }
    return null;
  }

  void _setImage(String? url) {
    setState(() => _imageUrl = url);
    final opt = _currentOptionId();
    if (url != null && url.isNotEmpty) {
      final map = <String, dynamic>{'image_url': url};
      if (opt != null) map['option_id'] = opt;
      widget.onAnswerChanged(jsonEncode(map));
    } else {
      widget.onAnswerChanged(opt);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (image == null) return;
      setState(() => _uploading = true);
      final bytes = await image.readAsBytes();
      final ext = image.name.split('.').last.toLowerCase();
      final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';

      String url = '';
      try {
        final client = Supabase.instance.client;
        final userId = client.auth.currentUser?.id ?? 'guest';
        final path =
            'quiz-attachments/$userId/${widget.questionId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
        await client.storage.from('profile-photos').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: mimeType, upsert: true),
            );
        url = client.storage.from('profile-photos').getPublicUrl(path);
      } catch (_) {
        url = 'data:$mimeType;base64,${base64Encode(bytes)}';
      }

      if (!mounted) return;
      setState(() => _uploading = false);
      _setImage(url);
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not attach image: $e')),
        );
      }
    }
  }

  Future<void> _enterImageUrl() async {
    final urlController = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter image link'),
        content: TextField(
          controller: urlController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Image URL (http:// or https://)',
            hintText: 'https://example.com/calculation.png',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(urlController.text.trim()),
            child: const Text('Attach'),
          ),
        ],
      ),
    );
    if (url != null && url.isNotEmpty) {
      _setImage(url);
    }
  }

  Widget _buildImageWidget(String url) {
    if (url.startsWith('data:image')) {
      final parts = url.split(',');
      if (parts.length > 1) {
        return Image.memory(
          base64Decode(parts[1]),
          fit: BoxFit.contain,
        );
      }
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Could not load image.')),
      ),
    );
  }

  void _showFullImage(BuildContext context) {
    if (_imageUrl == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBar(
              title: const Text('Attached Work Preview'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: InteractiveViewer(
                  maxScale: 4.0,
                  child: _buildImageWidget(_imageUrl!),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_uploading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Attaching calculation / diagram...'),
              ],
            ),
          )
        else if (_imageUrl != null && _imageUrl!.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Calculation / Diagram work attached',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: 'Remove attached work',
                      onPressed: () => _setImage(null),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _showFullImage(context),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: 140,
                      width: double.infinity,
                      color: Colors.black12,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          _buildImageWidget(_imageUrl!),
                          Positioned(
                            bottom: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.zoom_in, color: Colors.white, size: 14),
                                  SizedBox(width: 4),
                                  Text(
                                    'View Full',
                                    style: TextStyle(color: Colors.white, fontSize: 11),
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
              ],
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.camera_alt_outlined, size: 16),
                label: const Text('Take photo of work'),
                onPressed: () => _pickImage(ImageSource.camera),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.photo_library_outlined, size: 16),
                label: const Text('Upload calculation/graph'),
                onPressed: () => _pickImage(ImageSource.gallery),
              ),
              TextButton.icon(
                icon: const Icon(Icons.link_rounded, size: 16),
                label: const Text('Image link'),
                onPressed: _enterImageUrl,
              ),
            ],
          ),
      ],
    );
  }
}

