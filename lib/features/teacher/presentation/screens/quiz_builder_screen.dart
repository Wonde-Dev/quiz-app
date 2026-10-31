import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/utils/exam_script_parser.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class QuizBuilderScreen extends ConsumerStatefulWidget {
  const QuizBuilderScreen({super.key});

  @override
  ConsumerState<QuizBuilderScreen> createState() => _QuizBuilderScreenState();
}

class _QuizBuilderScreenState extends ConsumerState<QuizBuilderScreen> {
  static const String _ciroSchoolId = '00000000-0000-4000-8000-000000000001';
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _subjectController = TextEditingController(text: 'General');
  final _timeLimitController = TextEditingController(text: '30');
  final _scriptController = TextEditingController();
  final _keyController = TextEditingController();
  bool _showKeyField = false;
  final _questionController = TextEditingController();
  final _correctAnswerController = TextEditingController();
  final _explanationController = TextEditingController();
  final _diagramUrlController = TextEditingController();
  final _customSectionController = TextEditingController();
  final _optionControllers = List.generate(4, (_) => TextEditingController());

  PlatformFile? _attachedPdfFile;

  final List<Map<String, dynamic>> _questions = [];
  List<Map<String, dynamic>> _existingGrades = [];
  List<Map<String, dynamic>> _existingSections = [];
  List<Map<String, dynamic>> _assignedCourses = [];

  String? _selectedSchoolId = _ciroSchoolId;
  String _selectedGradeName = 'Grade 9';
  String _selectedSectionName = 'Section A';
  bool _useCustomSection = false;

  bool _loadingTargets = true;
  int _correctOption = 0;
  String _questionType = 'multiple_choice';
  bool _isSaving = false;
  String? _savedQuizId;
  bool _questionsSaved = false;
  String? _error;

  static const _standardGrades = [
    'Grade 9',
    'Grade 10',
    'Grade 11',
    'Grade 12',
  ];
  static const _standardSections = [
    'Section A',
    'Section B',
    'Section C',
    'Section D',
    'Section E',
    'Other / Custom',
  ];

  @override
  void initState() {
    super.initState();
    _loadTargets();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _subjectController.dispose();
    _timeLimitController.dispose();
    _scriptController.dispose();
    _keyController.dispose();
    _questionController.dispose();
    _correctAnswerController.dispose();
    _explanationController.dispose();
    _diagramUrlController.dispose();
    _customSectionController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadTargets() async {
    setState(() {
      _loadingTargets = true;
      _error = null;
    });

    try {
      final user = ref.read(authStateProvider).user;
      if (user == null) throw StateError('Sign in again to create a quiz.');
      if (user.role != AppRoles.teacher) {
        throw StateError('Quiz authoring is strictly restricted to teachers.');
      }

      _selectedSchoolId = _ciroSchoolId;
      await _loadSchoolMetadata(_ciroSchoolId);
      await _loadTeacherCourses(user.id);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not load classes: $error');
      }
    } finally {
      if (mounted) setState(() => _loadingTargets = false);
    }
  }

  Future<void> _loadSchoolMetadata(String schoolId) async {
    final client = Supabase.instance.client;
    try {
      final results = await Future.wait([
        client
            .from('school_grades')
            .select('id, name')
            .eq('school_id', schoolId)
            .order('name'),
        client
            .from('sections')
            .select('id, name, grade_id, school_grades(name)')
            .eq('school_id', schoolId)
            .order('name'),
      ]);

      if (!mounted) return;
      setState(() {
        _existingGrades = List<Map<String, dynamic>>.from(results[0]);
        _existingSections = List<Map<String, dynamic>>.from(results[1]);
      });
    } catch (e) {
      debugPrint('Metadata loading note: $e');
    }
  }

  Future<void> _loadTeacherCourses(String teacherId) async {
    final client = Supabase.instance.client;
    try {
      final rows = await client
          .from('courses')
          .select('id, name, subject, section_id')
          .eq('teacher_id', teacherId);
      if (mounted) {
        _assignedCourses = List<Map<String, dynamic>>.from(rows);
        if (_assignedCourses.isNotEmpty) {
          final firstSubject = _assignedCourses.first['subject'] as String?;
          if (firstSubject != null && firstSubject.isNotEmpty) {
            _subjectController.text = firstSubject;
          }
        }
      }
    } catch (e) {
      debugPrint('Course loading note: $e');
    }
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _attachedPdfFile = result.files.first);
    }
  }

  Future<void> _pickQuestionImage() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Attach Question Diagram or Image',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo with Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;
    try {
      final img = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (img == null) return;

      final bytes = await img.readAsBytes();
      final ext = img.name.split('.').last.toLowerCase();
      final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';

      String url = '';
      try {
        final client = Supabase.instance.client;
        final userId = client.auth.currentUser?.id ?? 'teacher';
        final path =
            'question-images/$userId/${DateTime.now().millisecondsSinceEpoch}_${img.name}';
        await client.storage.from('course-materials').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: mimeType, upsert: true),
            );
        url = client.storage.from('course-materials').getPublicUrl(path);
      } catch (_) {
        url = 'data:$mimeType;base64,${base64Encode(bytes)}';
      }

      setState(() {
        _diagramUrlController.text = url;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not attach image: $e')),
        );
      }
    }
  }

  Future<void> _openScriptImporterModal() async {
    final scriptController = TextEditingController();
    final keyController = TextEditingController();
    bool showKeyField = false;
    List<ParsedQuestion> parsedPreview = [];
    String? parseError;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return DraggableScrollableSheet(
            initialChildSize: 0.88,
            minChildSize: 0.5,
            maxChildSize: 0.96,
            builder: (_, scrollController) => Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: ListView(
                controller: scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF6366F1), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Smart Question Script Importer',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                            ),
                            Text(
                              'Paste your exam script. Auto-detects Multiple Choice, True/False, Blank Space & Description.',
                              style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.lightbulb_outline_rounded, size: 16),
                        label: const Text('Load Sample', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          setModalState(() {
                            scriptController.text = ExamScriptParser.sampleScript.trim();
                            parsedPreview = ExamScriptParser.parse(scriptController.text);
                            parseError = null;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: scriptController,
                    maxLines: 8,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Exam Questions Script (Copy & Paste here)',
                      hintText: '1. Which organelle is powerhouse of cell?\nA. Nucleus\nB. Mitochondria\nAnswer: B\n\n2. Photosynthesis occurs in animals. (True/False)\nAnswer: False',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onChanged: (text) {
                      setModalState(() {
                        if (text.trim().isNotEmpty) {
                          parsedPreview = ExamScriptParser.parse(
                            text,
                            answerKeyScript: showKeyField ? keyController.text : null,
                          );
                          parseError = parsedPreview.isEmpty ? 'No recognized questions found. Check numbering.' : null;
                        } else {
                          parsedPreview = [];
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      TextButton.icon(
                        icon: Icon(showKeyField ? Icons.remove_circle_outline : Icons.add_circle_outline, size: 16),
                        label: Text(showKeyField ? 'Hide Separate Answer Key' : 'Paste Separate Answer Key Script (Optional)'),
                        onPressed: () => setModalState(() => showKeyField = !showKeyField),
                      ),
                    ],
                  ),

                  if (showKeyField) ...[
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: keyController,
                      maxLines: 4,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Answer Key Script (Optional)',
                        hintText: '1. B\n2. False\n3. 0\n4. Photosynthesis is...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onChanged: (val) {
                        setModalState(() {
                          parsedPreview = ExamScriptParser.parse(
                            scriptController.text,
                            answerKeyScript: val,
                          );
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 14),

                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.flash_on_rounded, size: 18),
                    label: const Text('Parse Script & Validate Questions'),
                    onPressed: () {
                      setModalState(() {
                        parsedPreview = ExamScriptParser.parse(
                          scriptController.text,
                          answerKeyScript: showKeyField ? keyController.text : null,
                        );
                        parseError = parsedPreview.isEmpty ? 'No questions could be extracted. Please check the script format.' : null;
                      });
                    },
                  ),
                  if (parseError != null) ...[
                    const SizedBox(height: 8),
                    Text(parseError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                  const SizedBox(height: 16),

                  if (parsedPreview.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
                              const SizedBox(width: 8),
                              Text(
                                '${parsedPreview.length} Questions Ready to Import',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _scriptTypeBadge(
                                'Multiple Choice (${parsedPreview.where((q) => q.type == 'multiple_choice').length})',
                                const Color(0xFF3B82F6),
                              ),
                              _scriptTypeBadge(
                                'True/False (${parsedPreview.where((q) => q.type == 'true_false').length})',
                                const Color(0xFF10B981),
                              ),
                              _scriptTypeBadge(
                                'Blank Space (${parsedPreview.where((q) => q.type == 'fill_in_blank').length})',
                                const Color(0xFFF59E0B),
                              ),
                              _scriptTypeBadge(
                                'Description (${parsedPreview.where((q) => q.type == 'short_answer').length})',
                                const Color(0xFF8B5CF6),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    const Text('Parsed Questions Preview:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    for (int i = 0; i < parsedPreview.length; i++) ...[
                      _buildParsedQuestionTile(i + 1, parsedPreview[i], isDark),
                      const SizedBox(height: 8),
                    ],

                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.add_task_rounded, size: 20),
                      label: Text('Import All ${parsedPreview.length} Questions to Quiz'),
                      onPressed: () {
                        setState(() {
                          for (int i = 0; i < parsedPreview.length; i++) {
                            _questions.add(parsedPreview[i].toMap(_questions.length));
                          }
                        });
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Successfully imported ${parsedPreview.length} questions into quiz!'),
                            backgroundColor: const Color(0xFF10B981),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _scriptTypeBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildParsedQuestionTile(int index, ParsedQuestion q, bool isDark) {
    final typeColor = switch (q.type) {
      'true_false' => const Color(0xFF10B981),
      'fill_in_blank' => const Color(0xFFF59E0B),
      'short_answer' => const Color(0xFF8B5CF6),
      _ => const Color(0xFF3B82F6),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Q$index.',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(width: 8),
              _scriptTypeBadge(_questionTypeLabel(q.type), typeColor),
              if (q.imageUrl != null) ...[
                const SizedBox(width: 6),
                const Icon(Icons.image_outlined, size: 14, color: Color(0xFF10B981)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(q.text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          if (q.options.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final opt in q.options)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Row(
                  children: [
                    Icon(
                      opt['is_correct'] == true ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                      size: 13,
                      color: opt['is_correct'] == true ? const Color(0xFF10B981) : Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${(opt['id'] as String).toUpperCase()}. ${opt['text']}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: opt['is_correct'] == true ? FontWeight.bold : FontWeight.normal,
                        color: opt['is_correct'] == true ? const Color(0xFF10B981) : null,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (q.correctAnswer != null && q.correctAnswer!.isNotEmpty && q.type != 'multiple_choice') ...[
            const SizedBox(height: 4),
            Text(
              'Answer Key: ${q.correctAnswer}',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
            ),
          ],
        ],
      ),
    );
  }

  void _addQuestion() {
    final questionText = _questionController.text.trim();
    final diagramUrl = _diagramUrlController.text.trim();
    final effectiveText = diagramUrl.isNotEmpty
        ? '$questionText\n[diagram: $diagramUrl]'
        : questionText;
    final hasMissingChoice =
        _questionType == 'multiple_choice' &&
        _optionControllers.any((c) => c.text.trim().isEmpty);

    if (questionText.isEmpty || hasMissingChoice) {
      setState(() {
        _error = switch (_questionType) {
          'true_false' => 'Enter a true-or-false question statement.',
          'fill_in_blank' => 'Enter a question statement with blanks (e.g. ______)',
          'short_answer' => 'Enter a descriptive question prompt.',
          _ => 'Enter a question and all four answer choices.',
        };
      });
      return;
    }

    final isChoiceQuestion =
        _questionType == 'multiple_choice' || _questionType == 'true_false';
    final optionTexts = _questionType == 'true_false'
        ? const ['True', 'False']
        : _optionControllers.map((c) => c.text.trim()).toList();

    final expectedAnswer = _correctAnswerController.text.trim();
    final effectiveCorrectAnswer = (_questionType == 'short_answer' ||
            _questionType == 'fill_in_blank' ||
            _questionType == 'blank_space' ||
            _questionType == 'description')
        ? (expectedAnswer.isNotEmpty
              ? expectedAnswer
              : 'Teacher manual evaluation')
        : null;

    setState(() {
      _error = null;
      _questions.add({
        'text': effectiveText,
        'type': _questionType,
        'points': 1,
        'order': _questions.length,
        'options': isChoiceQuestion
            ? List.generate(
                optionTexts.length,
                (index) => {
                  'id': String.fromCharCode(97 + index),
                  'text': optionTexts[index],
                  'is_correct': index == _correctOption,
                },
              )
            : <Map<String, dynamic>>[],
        'correct_answer': effectiveCorrectAnswer,
        'explanation': _explanationController.text.trim().isEmpty
            ? null
            : _explanationController.text.trim(),
        'image_url': diagramUrl.isNotEmpty ? diagramUrl : null,
      });

      _questionController.clear();
      _diagramUrlController.clear();
      _correctAnswerController.clear();
      _explanationController.clear();
      for (final controller in _optionControllers) {
        controller.clear();
      }
      _correctOption = 0;
      _questionType = 'multiple_choice';
    });
  }

  Future<void> _saveQuiz() async {
    if (!_formKey.currentState!.validate()) return;

    if (_questions.isEmpty) {
      setState(() => _error = 'Add at least one question before publishing.');
      return;
    }

    setState(() {
      _error = null;
      _isSaving = true;
    });

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) throw StateError('Please sign in again to publish.');

      final effectiveSectionName = _useCustomSection
          ? _customSectionController.text.trim()
          : _selectedSectionName;

      if (effectiveSectionName.isEmpty) {
        throw StateError('Please choose or enter a section name.');
      }

      final schoolId = _selectedSchoolId;
      String? gradeId;
      String? sectionId;
      String? courseId;

      if (schoolId != null) {
        // 1. Resolve Grade
        final matchingGrade = _existingGrades.firstWhere(
          (g) =>
              (g['name'] as String).toLowerCase() ==
              _selectedGradeName.toLowerCase(),
          orElse: () => {},
        );

        if (matchingGrade.isNotEmpty && matchingGrade['id'] != null) {
          gradeId = matchingGrade['id'] as String;
        } else {
          try {
            final newGrade = await client
                .from('school_grades')
                .upsert({
                  'school_id': schoolId,
                  'name': _selectedGradeName,
                }, onConflict: 'school_id, name')
                .select('id')
                .single();
            gradeId = newGrade['id'] as String;
          } catch (e) {
            debugPrint('Grade resolution note: $e');
          }
        }

        // 2. Resolve Section matching BOTH grade_id and section name
        final matchingSection = _existingSections.firstWhere(
          (s) {
            final matchesName = (s['name'] as String).trim().toLowerCase() ==
                effectiveSectionName.toLowerCase();
            final matchesGrade = gradeId != null ? s['grade_id'] == gradeId : true;
            return matchesName && matchesGrade;
          },
          orElse: () => {},
        );

        if (matchingSection.isNotEmpty && matchingSection['id'] != null) {
          sectionId = matchingSection['id'] as String;
        } else {
          try {
            final newSection = await client
                .from('sections')
                .insert({
                  'school_id': schoolId,
                  'grade_id': gradeId,
                  'name': effectiveSectionName,
                  'grade': _selectedGradeName.replaceAll(RegExp(r'[^0-9]'), ''),
                })
                .select('id')
                .single();
            sectionId = newSection['id'] as String;
          } catch (e) {
            debugPrint('Section resolution note: $e');
            // Try matching section again with grade awareness
            final fallback = _existingSections.firstWhere(
              (s) =>
                  (s['name'] as String).trim().toLowerCase() ==
                      effectiveSectionName.toLowerCase() &&
                  (gradeId == null || s['grade_id'] == gradeId),
              orElse: () =>
                  _existingSections.isNotEmpty ? _existingSections.first : {},
            );
            if (fallback.isNotEmpty) {
              sectionId = fallback['id'] as String;
            }
          }
        }

        // 3. Resolve Course for teacher
        final matchingCourse = _assignedCourses.firstWhere(
          (c) => c['section_id'] == sectionId,
          orElse: () => {},
        );

        if (matchingCourse.isNotEmpty && matchingCourse['id'] != null) {
          courseId = matchingCourse['id'] as String;
        } else {
          try {
            final newCourse = await client
                .from('courses')
                .insert({
                  'school_id': schoolId,
                  'teacher_id': user.id,
                  'section_id': sectionId,
                  'name':
                      '${_subjectController.text.trim()} · $_selectedGradeName $effectiveSectionName',
                  'subject': _subjectController.text.trim(),
                })
                .select('id')
                .single();
            courseId = newCourse['id'] as String;
          } catch (e) {
            debugPrint('Course auto-link note: $e');
            if (_assignedCourses.isNotEmpty) {
              courseId = _assignedCourses.first['id'] as String;
            }
          }
        }
      }

      final timeLimit = int.tryParse(_timeLimitController.text.trim()) ?? 30;

      String effectiveDesc = _descriptionController.text.trim();
      if (_attachedPdfFile != null && _attachedPdfFile!.bytes != null) {
        try {
          final cleanName = _attachedPdfFile!.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
          final storagePath = 'quizzes/${user.id}/${DateTime.now().millisecondsSinceEpoch}_$cleanName';
          await client.storage.from('course-materials').uploadBinary(
                storagePath,
                _attachedPdfFile!.bytes!,
                fileOptions: const FileOptions(contentType: 'application/pdf', upsert: true),
              );
          final pdfUrl = client.storage.from('course-materials').getPublicUrl(storagePath);
          effectiveDesc = effectiveDesc.isNotEmpty
              ? '$effectiveDesc\n[Attached Exam PDF: ${_attachedPdfFile!.name}]($pdfUrl)'
              : '[Attached Exam PDF: ${_attachedPdfFile!.name}]($pdfUrl)';
        } catch (e) {
          debugPrint('PDF attach note: $e');
        }
      }

      // 4. Create Quiz with targeted grade and class
      if (_savedQuizId == null) {
        final quizPayload = {
          'teacher_id': user.id,
          'course_id': courseId,
          'section_id': sectionId,
          'target_grade': _selectedGradeName,
          'target_section': effectiveSectionName,
          'title': _titleController.text.trim(),
          'description': effectiveDesc,
          'time_limit_minutes': timeLimit,
          'total_points': _questions.length,
          'is_published': false,
        };

        Map<String, dynamic> quiz;
        try {
          quiz = await client
              .from('quizzes')
              .insert(quizPayload)
              .select('id')
              .single();
        } catch (_) {
          // Fallback if target_grade / target_section columns are not yet applied
          quizPayload.remove('target_grade');
          quizPayload.remove('target_section');
          quiz = await client
              .from('quizzes')
              .insert(quizPayload)
              .select('id')
              .single();
        }
        _savedQuizId = quiz['id'] as String;
      }

      // 5. Insert Questions
      if (!_questionsSaved && _savedQuizId != null) {
        await client
            .from('questions')
            .insert(
              _questions.map((q) => {...q, 'quiz_id': _savedQuizId}).toList(),
            );
        _questionsSaved = true;
      }

      // 6. Publish Quiz
      await client
          .from('quizzes')
          .update({'is_published': true})
          .eq('id', _savedQuizId!);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Quiz published successfully! Students can now take it.',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not publish quiz: $error');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentUser = ref.watch(authStateProvider).user;

    // Faculty Exclusive Guard: Quizzes are prepared exclusively by Teachers
    if (currentUser?.role == AppRoles.admin || AppRoles.isDirector(currentUser?.role)) {
      return DashboardShell(
        title: 'Quiz Oversight',
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.school_rounded, color: Color(0xFF10B981), size: 40),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Faculty Preparation Exclusive',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'At Ciro High School, quizzes and exams are prepared exclusively by Faculty Teachers for their assigned grades and sections.\n\nAdministrators and School Directors oversee published quizzes from the Moderation Panel on the Dashboard.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF64748B), height: 1.45, fontSize: 13),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Return to Dashboard'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return DashboardShell(
      title: 'Prepare an exam or quiz',
      body: _loadingTargets
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // FAST EXAM SETUP HERO CARD (Teacher Script & Time Limit)
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      colors: isDark
                          ? [const Color(0xFF1E1B4B), const Color(0xFF312E81)]
                          : [const Color(0xFF4338CA), const Color(0xFF6366F1)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '⚡ Fast Exam Setup from Script & Time',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Give your exam script & time limit — the app formats questions, choices, answers, and points automatically!',
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.white.withValues(alpha: 0.18),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.lightbulb_outline_rounded, size: 15, color: Colors.amberAccent),
                              label: const Text('Sample', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: () {
                                setState(() {
                                  _scriptController.text = ExamScriptParser.sampleScript.trim();
                                  if (_titleController.text.trim().isEmpty) {
                                    _titleController.text = 'Biology Semester Examination';
                                  }
                                  if (_subjectController.text.trim().isEmpty || _subjectController.text == 'General') {
                                    _subjectController.text = 'Biology';
                                  }
                                  _timeLimitController.text = '45';
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Loaded sample exam script! Tap "Set Up Exam Questions" below.'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Quick Input Row: Exam Time & Subject
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                                ),
                                child: TextFormField(
                                  controller: _timeLimitController,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  decoration: const InputDecoration(
                                    labelText: 'Exam Time (Minutes)',
                                    labelStyle: TextStyle(color: Colors.white70, fontSize: 12),
                                    prefixIcon: Icon(Icons.timer_outlined, color: Colors.white, size: 20),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 4,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                                ),
                                child: TextFormField(
                                  controller: _subjectController,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  decoration: const InputDecoration(
                                    labelText: 'Subject',
                                    labelStyle: TextStyle(color: Colors.white70, fontSize: 12),
                                    prefixIcon: Icon(Icons.menu_book_outlined, color: Colors.white, size: 20),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Script Text Area
                        Container(
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: TextFormField(
                            controller: _scriptController,
                            maxLines: 7,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                            decoration: InputDecoration(
                              hintText: '1. Which organelle is powerhouse of cell?\nA. Nucleus\nB. Mitochondria\nAnswer: B\n\n2. Pure water freezes at ______ degrees Celsius.\nAnswer: 0',
                              hintStyle: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                              ),
                              border: InputBorder.none,
                              labelText: 'Paste Questions Script (Choose, True/False, Blank Space, Description)',
                              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              alignLabelWithHint: true,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Separate Answer Key Script (Optional)
                        Row(
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => setState(() => _showKeyField = !_showKeyField),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _showKeyField ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded,
                                      size: 15,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _showKeyField ? 'Hide Separate Answer Key' : 'Paste Separate Answer Key Script (Optional)',
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                        if (_showKeyField) ...[
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F172A) : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            child: TextFormField(
                              controller: _keyController,
                              maxLines: 3,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                              decoration: const InputDecoration(
                                hintText: '1. B\n2. False\n3. 0\n4. Description answer...',
                                border: InputBorder.none,
                                labelText: 'Separate Answer Key Script',
                                labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                alignLabelWithHint: true,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),

                        // Parse Button
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  elevation: 2,
                                ),
                                icon: const Icon(Icons.flash_on_rounded, size: 20),
                                label: const Text(
                                  '⚡ Set Up Exam Questions from Script',
                                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                                ),
                                onPressed: () {
                                  final text = _scriptController.text.trim();
                                  if (text.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Please paste your exam questions script first, or tap "Sample".'),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                    return;
                                  }

                                  final parsed = ExamScriptParser.parse(
                                    text,
                                    answerKeyScript: _showKeyField ? _keyController.text : null,
                                  );

                                  if (parsed.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Could not recognize questions. Check question numbering (1., 2., etc.).'),
                                        backgroundColor: Colors.red,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                    return;
                                  }

                                  setState(() {
                                    _questions.clear();
                                    for (int i = 0; i < parsed.length; i++) {
                                      _questions.add(parsed[i].toMap(_questions.length));
                                    }

                                    if (_titleController.text.trim().isEmpty) {
                                      _titleController.text = '$_selectedGradeName ${_subjectController.text.trim().isNotEmpty ? _subjectController.text.trim() : "Exam"} ($_selectedSectionName)';
                                    }
                                  });

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('⚡ Successfully formatted and loaded ${parsed.length} questions into exam! Preview below and tap Publish.'),
                                      backgroundColor: const Color(0xFF10B981),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Section 1: Quiz Details Card
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Quiz Details',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _titleController,
                                decoration: const InputDecoration(
                                  labelText: 'Quiz Title',
                                  prefixIcon: Icon(Icons.title_rounded),
                                ),
                                readOnly: _questionsSaved,
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                    ? 'Enter a title'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _descriptionController,
                                decoration: const InputDecoration(
                                  labelText: 'Description / Instructions',
                                  prefixIcon: Icon(Icons.description_outlined),
                                ),
                                maxLines: 2,
                                readOnly: _questionsSaved,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _subjectController,
                                      decoration: const InputDecoration(
                                        labelText: 'Subject',
                                        prefixIcon: Icon(Icons.subject_rounded),
                                      ),
                                      readOnly: _questionsSaved,
                                      validator: (value) =>
                                          value == null || value.trim().isEmpty
                                          ? 'Enter subject'
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _timeLimitController,
                                      decoration: const InputDecoration(
                                        labelText: 'Time limit (min)',
                                        prefixIcon: Icon(Icons.timer_outlined),
                                      ),
                                      keyboardType: TextInputType.number,
                                      readOnly: _questionsSaved,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // PDF Exam / Worksheet Attachment Box
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0xFFCBD5E1)),
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
                                            _attachedPdfFile == null
                                                ? 'Attach Exam / Worksheet PDF (Optional)'
                                                : _attachedPdfFile!.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            _attachedPdfFile == null
                                                ? 'Students can view official exam papers during the quiz'
                                                : '${(_attachedPdfFile!.size / 1024).toStringAsFixed(1)} KB · Attached',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF64748B),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_attachedPdfFile != null)
                                      IconButton(
                                        tooltip: 'Remove PDF',
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          size: 18,
                                          color: Colors.red,
                                        ),
                                        onPressed: _questionsSaved
                                            ? null
                                            : () => setState(() => _attachedPdfFile = null),
                                      )
                                    else
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        icon: const Icon(Icons.attach_file_rounded, size: 14),
                                        label: const Text('Attach PDF', style: TextStyle(fontSize: 12)),
                                        onPressed: _questionsSaved ? null : _pickPdf,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Section 2: Target Audience Card (Grade 9-12 & Section A/B/C/etc.)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Class Assignment (Grade & Section)',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Select the target grade from 9 to 12 and section for this quiz.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Grade Picker
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _selectedGradeName,
                                decoration: const InputDecoration(
                                  labelText: 'Choose Grade (Grade 9 - 12)',
                                  prefixIcon: Icon(Icons.grade_outlined),
                                ),
                                items: [
                                  for (final grade in _standardGrades)
                                    DropdownMenuItem(
                                      value: grade,
                                      child: Text(grade),
                                    ),
                                  for (final g in _existingGrades)
                                    if (!_standardGrades.contains(g['name']))
                                      DropdownMenuItem(
                                        value: g['name'] as String,
                                        child: Text(g['name'] as String),
                                      ),
                                ],
                                onChanged: _isSaving
                                    ? null
                                    : (grade) {
                                        if (grade != null) {
                                          setState(
                                            () => _selectedGradeName = grade,
                                          );
                                        }
                                      },
                              ),
                              const SizedBox(height: 12),

                              // Section Picker
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _selectedSectionName,
                                decoration: const InputDecoration(
                                  labelText: 'Choose Section (A, B, C, etc.)',
                                  prefixIcon: Icon(Icons.group_work_outlined),
                                ),
                                items: [
                                  for (final section in _standardSections)
                                    DropdownMenuItem(
                                      value: section,
                                      child: Text(section),
                                    ),
                                  for (final s in _existingSections)
                                    if (!_standardSections.contains(s['name']))
                                      DropdownMenuItem(
                                        value: s['name'] as String,
                                        child: Text(s['name'] as String),
                                      ),
                                ],
                                onChanged: _isSaving
                                    ? null
                                    : (section) {
                                        if (section == null) return;
                                        setState(() {
                                          _selectedSectionName = section;
                                          _useCustomSection =
                                              section == 'Other / Custom';
                                        });
                                      },
                              ),

                              if (_useCustomSection) ...[
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _customSectionController,
                                  decoration: const InputDecoration(
                                    labelText:
                                        'Custom Section Name (e.g. Section F)',
                                    hintText: 'Enter section letter or name',
                                    prefixIcon: Icon(Icons.edit_note_rounded),
                                  ),
                                  textCapitalization: TextCapitalization.words,
                                  validator: (v) =>
                                      _useCustomSection &&
                                          (v == null || v.trim().isEmpty)
                                      ? 'Enter a section name'
                                      : null,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Smart Script Importer Callout Banner
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4F46E5), Color(0xFF6366F1), Color(0xFF4338CA)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Copy & Paste Exam Script',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Paste multiple questions at once. Automatically detects Choose, True/False, Blank Space & Description.',
                                    style: TextStyle(color: Color(0xFFE0E7FF), fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF4338CA),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              ),
                              onPressed: _openScriptImporterModal,
                              child: const Text('Import Script', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Section 3: Questions list
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Questions (${_questions.length})',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_questions.isNotEmpty)
                            Text(
                              '${_questions.length} points total',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      if (_questions.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.quiz_outlined,
                                    size: 44,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No questions added yet. Use the question builder below to add questions.',
                                    textAlign: TextAlign.center,
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
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _questions.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final q = _questions[index];
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      theme.colorScheme.primaryContainer,
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      color:
                                          theme.colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  q['text'] as String,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${_questionTypeLabel(q['type'] as String)} · 1 pt'
                                  '${(q['explanation'] as String?)?.isNotEmpty == true ? ' · with explanation' : ''}',
                                ),
                                trailing: IconButton(
                                  tooltip: 'Remove',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  onPressed: _isSaving || _questionsSaved
                                      ? null
                                      : () => setState(
                                          () => _questions.removeAt(index),
                                        ),
                                ),
                              ),
                            );
                          },
                        ),

                      const SizedBox(height: 24),

                      // Section 4: Add New Question Card
                      Card(
                        color: theme.colorScheme.surfaceContainerLow,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Add Question',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _questionController,
                                decoration: const InputDecoration(
                                  labelText: 'Question Text',
                                  prefixIcon: Icon(Icons.help_outline_rounded),
                                ),
                                textCapitalization:
                                    TextCapitalization.sentences,
                                readOnly: _questionsSaved,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _diagramUrlController,
                                decoration: InputDecoration(
                                  labelText: 'Question Diagram / Graph / Reference URL (optional)',
                                  prefixIcon: const Icon(Icons.insert_chart_outlined),
                                  hintText: 'https://... image link or graph',
                                  suffixIcon: IconButton(
                                    tooltip: 'Attach Diagram from Camera or Gallery',
                                    icon: const Icon(Icons.add_a_photo_outlined, color: Color(0xFF10B981)),
                                    onPressed: _questionsSaved ? null : _pickQuestionImage,
                                  ),
                                ),
                                readOnly: _questionsSaved,
                                onChanged: (_) => setState(() {}),
                              ),
                              if (_diagramUrlController.text.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: _diagramUrlController.text.startsWith('data:')
                                          ? Image.memory(
                                              base64Decode(_diagramUrlController.text.split(',').last),
                                              height: 54,
                                              width: 74,
                                              fit: BoxFit.cover,
                                            )
                                          : Image.network(
                                              _diagramUrlController.text,
                                              height: 54,
                                              width: 74,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 30),
                                            ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Text(
                                        '✓ Image/Diagram attached to question',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Remove image',
                                      icon: const Icon(Icons.close_rounded, size: 18, color: Colors.red),
                                      onPressed: _questionsSaved ? null : () => setState(() => _diagramUrlController.clear()),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _questionType,
                                decoration: const InputDecoration(
                                  labelText: 'Question Type',
                                  prefixIcon: Icon(Icons.category_outlined),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'multiple_choice',
                                    child: Text('Multiple Choice (Choose A, B, C, D)'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'true_false',
                                    child: Text('True or False'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'fill_in_blank',
                                    child: Text('Blank Space (Fill in the Blank)'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'short_answer',
                                    child: Text(
                                      'Descriptive / Short Answer (allows text & photo)',
                                    ),
                                  ),
                                ],
                                onChanged: _questionsSaved
                                    ? null
                                    : (value) {
                                        if (value != null) {
                                          setState(() {
                                            _questionType = value;
                                            _correctOption = 0;
                                          });
                                        }
                                      },
                              ),
                              const SizedBox(height: 14),

                              if (_questionType == 'fill_in_blank') ...[
                                TextFormField(
                                  controller: _correctAnswerController,
                                  decoration: const InputDecoration(
                                    labelText: 'Expected Blank Answer *',
                                    hintText: 'e.g. Mitochondria, 100, Photosynthesis',
                                    helperText: 'The student\'s answer will be compared directly against this key.',
                                    prefixIcon: Icon(
                                      Icons.check_circle_outline,
                                    ),
                                  ),
                                  readOnly: _questionsSaved,
                                ),
                              ] else if (_questionType == 'short_answer') ...[
                                TextFormField(
                                  controller: _correctAnswerController,
                                  decoration: const InputDecoration(
                                    labelText: 'Expected Answer / Model solution (optional)',
                                    hintText: 'Enter sample answer or leave blank for manual grading',
                                    helperText: 'Students will be able to type written explanations and attach photos/diagrams.',
                                    prefixIcon: Icon(
                                      Icons.check_circle_outline,
                                    ),
                                  ),
                                  readOnly: _questionsSaved,
                                ),
                              ] else ...[
                                Text(
                                  'Mark the correct choice:',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                RadioGroup<int>(
                                  groupValue: _correctOption,
                                  onChanged: (v) {
                                    if (!_questionsSaved && v != null) {
                                      setState(() => _correctOption = v);
                                    }
                                  },
                                  child: Column(
                                    children: [
                                      for (
                                        var index = 0;
                                        index <
                                            (_questionType == 'true_false'
                                                ? 2
                                                : _optionControllers.length);
                                        index++
                                      )
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: Row(
                                            children: [
                                              Radio<int>(value: index),
                                              Expanded(
                                                child:
                                                    _questionType ==
                                                        'true_false'
                                                    ? Text(
                                                        index == 0
                                                            ? 'True'
                                                            : 'False',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      )
                                                    : TextFormField(
                                                        controller:
                                                            _optionControllers[index],
                                                        readOnly:
                                                            _questionsSaved,
                                                        decoration: InputDecoration(
                                                          labelText:
                                                              'Option ${String.fromCharCode(65 + index)}',
                                                          isDense: true,
                                                        ),
                                                      ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _explanationController,
                                decoration: const InputDecoration(
                                  labelText: 'Explanation (Optional)',
                                  hintText: 'Explains why this answer is correct after submission',
                                  prefixIcon: Icon(
                                    Icons.lightbulb_outline_rounded,
                                  ),
                                ),
                                maxLines: 2,
                                readOnly: _questionsSaved,
                              ),
                              const SizedBox(height: 14),

                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton.tonalIcon(
                                  onPressed: _isSaving || _questionsSaved
                                      ? null
                                      : _addQuestion,
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('Add to Quiz'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: theme.colorScheme.onErrorContainer,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: theme.colorScheme.onErrorContainer,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _isSaving ? null : _saveQuiz,
                        icon: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.publish_rounded),
                        label: Text(
                          _isSaving ? 'Publishing quiz...' : 'Publish Quiz',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  String _questionTypeLabel(String type) => switch (type) {
    'true_false' => 'True or false',
    'fill_in_blank' || 'blank_space' => 'Blank Space',
    'short_answer' || 'description' => 'Description / Short answer',
    _ => 'Multiple choice',
  };
}
