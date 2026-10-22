import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class QuizBuilderScreen extends ConsumerStatefulWidget {
  const QuizBuilderScreen({super.key});

  @override
  ConsumerState<QuizBuilderScreen> createState() => _QuizBuilderScreenState();
}

class _QuizBuilderScreenState extends ConsumerState<QuizBuilderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _subjectController = TextEditingController(text: 'General');
  final _timeLimitController = TextEditingController(text: '30');
  final _questionController = TextEditingController();
  final _correctAnswerController = TextEditingController();
  final _explanationController = TextEditingController();
  final _diagramUrlController = TextEditingController();
  final _customSectionController = TextEditingController();
  final _optionControllers = List.generate(4, (_) => TextEditingController());

  final List<Map<String, dynamic>> _questions = [];
  List<Map<String, dynamic>> _schools = [];
  List<Map<String, dynamic>> _existingGrades = [];
  List<Map<String, dynamic>> _existingSections = [];
  List<Map<String, dynamic>> _assignedCourses = [];

  String _role = AppRoles.teacher;
  String? _selectedSchoolId;
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
      _role = user.role;

      final client = Supabase.instance.client;

      if (_role == AppRoles.admin) {
        final rows = await client
            .from('schools')
            .select('id, name')
            .order('name');
        _schools = List<Map<String, dynamic>>.from(rows);
        if (_schools.isNotEmpty) {
          _selectedSchoolId = _schools.first['id'] as String;
          await _loadSchoolMetadata(_selectedSchoolId!);
        }
      } else {
        _selectedSchoolId = user.schoolId;
        if (_selectedSchoolId != null) {
          await _loadSchoolMetadata(_selectedSchoolId!);
        }
        await _loadTeacherCourses(user.id);
      }
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
    final effectiveCorrectAnswer = _questionType == 'short_answer'
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

      // 4. Create Quiz with targeted grade and class
      if (_savedQuizId == null) {
        final quizPayload = {
          'teacher_id': user.id,
          'course_id': courseId,
          'section_id': sectionId,
          'target_grade': _selectedGradeName,
          'target_section': effectiveSectionName,
          'title': _titleController.text.trim(),
          'description': _descriptionController.text.trim(),
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

    return DashboardShell(
      title: 'Prepare a quiz',
      body: _loadingTargets
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
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

                              if (_role == AppRoles.admin &&
                                  _schools.isNotEmpty) ...[
                                DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: _selectedSchoolId,
                                  decoration: const InputDecoration(
                                    labelText: 'School',
                                    prefixIcon: Icon(Icons.school_outlined),
                                  ),
                                  items: [
                                    for (final school in _schools)
                                      DropdownMenuItem(
                                        value: school['id'] as String,
                                        child: Text(
                                          school['name'] as String? ?? 'School',
                                        ),
                                      ),
                                  ],
                                  onChanged: _isSaving
                                      ? null
                                      : (schoolId) {
                                          if (schoolId == null) return;
                                          setState(
                                            () => _selectedSchoolId = schoolId,
                                          );
                                          _loadSchoolMetadata(schoolId);
                                        },
                                ),
                                const SizedBox(height: 12),
                              ],

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
                                decoration: const InputDecoration(
                                  labelText: 'Question Diagram / Graph / Reference URL (optional)',
                                  prefixIcon: Icon(Icons.insert_chart_outlined),
                                  hintText: 'https://... image link or graph',
                                ),
                                readOnly: _questionsSaved,
                              ),
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
                                    child: Text('Multiple Choice (4 options)'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'true_false',
                                    child: Text('True or False'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'short_answer',
                                    child: Text(
                                      'Descriptive / Short Answer (allows text & image)',
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

                              if (_questionType == 'short_answer') ...[
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
    'short_answer' => 'Description / Short answer',
    _ => 'Multiple choice',
  };
}
