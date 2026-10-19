import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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

class _QuizAttemptScreenState extends State<QuizAttemptScreen> {
  final _service = QuizAttemptService();
  late Future<QuizAttemptData> _attempt;
  final Map<String, dynamic> _answers = {};
  Timer? _timer;
  QuizAttemptData? _data;
  int _currentIndex = 0;
  int? _secondsRemaining;
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _attempt = _service.start(widget.quizId);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer(QuizAttemptData data) {
    if (_data != null) return;
    _data = data;
    final minutes = data.quiz.timeLimitMinutes;
    if (minutes == null || minutes <= 0) return;
    _secondsRemaining = minutes * 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _secondsRemaining == null) return;
      if (_secondsRemaining! <= 1) {
        timer.cancel();
        unawaited(_submit());
      } else {
        setState(() => _secondsRemaining = _secondsRemaining! - 1);
      }
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting || _data == null) return;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    _timer?.cancel();
    try {
      final result = await _service.submit(widget.quizId, _answers);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) => QuizResultScreen(
            grade: result.grade,
            quizTitle: _data!.quiz.title,
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
          _startTimer(data);
          final question = data.questions[_currentIndex];
          return SecureScreenWrapper(
            onAutoSubmit: () => unawaited(_submit()),
            child: Scaffold(
              appBar: AppBar(
                title: Text(data.quiz.title),
                automaticallyImplyLeading: false,
                actions: [
                  if (_secondsRemaining != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        child: Text(
                          _formatTime(_secondsRemaining!),
                          style: Theme.of(context).textTheme.titleMedium,
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
                  ),
                  if (data.quiz.description?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 16),
                    Text(
                      data.quiz.description!.trim(),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'Question ${_currentIndex + 1} of ${data.questions.length}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  CopyPasteBlocker(
                    child: Text(
                      question.text,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (question.type == 'short_answer')
                    TextFormField(
                      key: ValueKey(question.id),
                      initialValue: _answers[question.id] as String? ?? '',
                      decoration: const InputDecoration(
                        labelText: 'Fill in the blank',
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (value) => _answers[question.id] = value,
                    )
                  else
                    RadioGroup<String>(
                      groupValue: _answers[question.id] as String?,
                      onChanged: (value) {
                        if (_isSubmitting) return;
                        setState(() => _answers[question.id] = value);
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
                  if (_submitError != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _submitError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      if (_currentIndex > 0)
                        OutlinedButton(
                          onPressed: _isSubmitting
                              ? null
                              : () => setState(() => _currentIndex--),
                          child: const Text('Previous'),
                        ),
                      const Spacer(),
                      if (_currentIndex < data.questions.length - 1)
                        FilledButton(
                          onPressed: _isSubmitting
                              ? null
                              : () => setState(() => _currentIndex++),
                          child: const Text('Next'),
                        )
                      else
                        FilledButton(
                          onPressed: _isSubmitting ? null : _submit,
                          child: _isSubmitting
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
    );
  }
}
