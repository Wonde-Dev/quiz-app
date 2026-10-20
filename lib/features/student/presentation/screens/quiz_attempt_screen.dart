import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
                  if (data.quiz.description?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 16),
                    Text(
                      data.quiz.description!.trim(),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Question ${_currentIndex + 1} of ${data.questions.length}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        question.type == 'short_answer'
                            ? 'Descriptive / Short answer'
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
                      question.text,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (question.type == 'short_answer')
                    _DescriptionQuestionInput(
                      key: ValueKey(question.id),
                      questionId: question.id,
                      initialAnswer: _answers[question.id],
                      onAnswerChanged: (newAnswer) {
                        _answers[question.id] = newAnswer;
                      },
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

