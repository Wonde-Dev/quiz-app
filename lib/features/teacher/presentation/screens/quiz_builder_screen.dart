import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';

class QuizBuilderScreen extends ConsumerStatefulWidget {
  const QuizBuilderScreen({super.key});

  @override
  ConsumerState<QuizBuilderScreen> createState() => _QuizBuilderScreenState();
}

class _QuizBuilderScreenState extends ConsumerState<QuizBuilderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _questionController = TextEditingController();
  final _correctAnswerController = TextEditingController();
  final _explanationController = TextEditingController();
  final _optionControllers = List.generate(4, (_) => TextEditingController());
  final List<Map<String, dynamic>> _questions = [];
  List<Map<String, dynamic>> _schools = [];
  List<Map<String, dynamic>> _sections = [];
  List<Map<String, dynamic>> _assignedCourses = [];
  String _role = AppRoles.teacher;
  String? _selectedSchoolId;
  String? _selectedGradeId;
  String? _selectedSectionId;
  String? _selectedCourseId;
  bool _loadingTargets = true;
  int _correctOption = 0;
  String _questionType = 'multiple_choice';
  bool _isSaving = false;
  String? _savedQuizId;
  bool _questionsSaved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTargets();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _questionController.dispose();
    _correctAnswerController.dispose();
    _explanationController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addQuestion() {
    final questionText = _questionController.text.trim();
    final hasMissingChoice =
        _questionType == 'multiple_choice' &&
        _optionControllers.any((controller) => controller.text.trim().isEmpty);
    final hasMissingAnswer =
        _questionType == 'short_answer' &&
        _correctAnswerController.text.trim().isEmpty;
    if (questionText.isEmpty || hasMissingChoice || hasMissingAnswer) {
      setState(() {
        _error = switch (_questionType) {
          'short_answer' => 'Enter a question and its correct answer.',
          'true_false' => 'Enter a true-or-false question.',
          _ => 'Enter a question and all four answer options.',
        };
      });
      return;
    }
    final isChoiceQuestion =
        _questionType == 'multiple_choice' || _questionType == 'true_false';
    final optionTexts = _questionType == 'true_false'
        ? const ['True', 'False']
        : _optionControllers
              .map((controller) => controller.text.trim())
              .toList();
    setState(() {
      _error = null;
      _questions.add({
        'text': questionText,
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
        'correct_answer': _questionType == 'short_answer'
            ? _correctAnswerController.text.trim()
            : null,
        'explanation': _explanationController.text.trim().isEmpty
            ? null
            : _explanationController.text.trim(),
      });
      _questionController.clear();
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
    final assignedCourse = _assignedCourses
        .where((course) => course['id'] == _selectedCourseId)
        .firstOrNull;
    if (_role == AppRoles.teacher && assignedCourse == null) {
      setState(() => _error = 'Choose one of your assigned subjects.');
      return;
    }
    if (_role == AppRoles.admin && _selectedSectionId == null) {
      setState(() => _error = 'Choose a grade and section for this quiz.');
      return;
    }
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
      if (_savedQuizId == null) {
        final user = client.auth.currentUser;
        if (user == null) throw StateError('Sign in again to create a quiz.');
        final quiz = await client
            .from('quizzes')
            .insert({
              'teacher_id': user.id,
              'course_id': assignedCourse?['id'],
              'section_id': assignedCourse?['section_id'] ?? _selectedSectionId,
              'title': _titleController.text.trim(),
              'description': _descriptionController.text.trim(),
              'total_points': _questions.length,
              'is_published': false,
            })
            .select('id')
            .single();
        _savedQuizId = quiz['id'] as String;
      }
      if (!_questionsSaved) {
        await client
            .from('questions')
            .insert(
              _questions
                  .map((question) => {...question, 'quiz_id': _savedQuizId})
                  .toList(),
            );
        _questionsSaved = true;
      }
      await client
          .from('quizzes')
          .update({'is_published': true})
          .eq('id', _savedQuizId!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quiz published for students')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Quiz was not published: $error');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _loadTargets() async {
    try {
      final user = ref.read(authStateProvider).user;
      if (user == null) throw StateError('Sign in again to create a quiz.');
      _role = user.role;
      if (_role == AppRoles.teacher) {
        await _loadAssignedCourses(user.id);
      } else if (_role == AppRoles.admin) {
        final rows = await Supabase.instance.client
            .from('schools')
            .select('id, name')
            .order('name');
        _schools = List<Map<String, dynamic>>.from(rows);
        final schoolId = _schools.isEmpty
            ? null
            : _schools.first['id'] as String;
        _selectedSchoolId = schoolId;
        if (schoolId == null) {
          throw StateError('Add a school before creating a quiz.');
        }
        await _loadSections(schoolId);
      } else {
        throw StateError('Your account cannot create quizzes.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not load class sections: $error');
      }
    } finally {
      if (mounted) setState(() => _loadingTargets = false);
    }
  }

  Future<void> _loadAssignedCourses(String teacherId) async {
    final client = Supabase.instance.client;
    final rows = await client
        .from('courses')
        .select('id, name, subject, section_id')
        .eq('teacher_id', teacherId)
        .not('section_id', 'is', null)
        .order('subject');
    final courses = List<Map<String, dynamic>>.from(rows);
    if (courses.isEmpty) {
      if (mounted) setState(() => _assignedCourses = []);
      return;
    }
    final sectionIds = courses
        .map((course) => course['section_id'] as String)
        .toSet()
        .toList();
    final sectionRows = await client
        .from('sections')
        .select('id, name, grade_id, school_grades!inner(name)')
        .inFilter('id', sectionIds);
    final sectionsById = {
      for (final section in List<Map<String, dynamic>>.from(sectionRows))
        section['id'] as String: section,
    };
    final assignments = courses
        .where((course) => sectionsById.containsKey(course['section_id']))
        .map((course) {
          final section =
              sectionsById[course['section_id']] as Map<String, dynamic>;
          final grade = section['school_grades'] as Map<String, dynamic>;
          return {
            ...course,
            'class_label':
                '${course['subject'] ?? course['name']} · '
                '${grade['name']} ${section['name']}',
          };
        })
        .toList();
    if (!mounted) return;
    setState(() {
      _assignedCourses = assignments;
      _selectedCourseId = assignments
          .map((course) => course['id'] as String)
          .firstOrNull;
    });
  }

  Future<void> _loadSections(String schoolId) async {
    final rows = await Supabase.instance.client
        .from('sections')
        .select('id, name, grade_id, school_grades!inner(id, name)')
        .eq('school_id', schoolId)
        .order('name');
    final sections = List<Map<String, dynamic>>.from(rows);
    final gradeIds = sections
        .map((section) => section['grade_id'] as String)
        .toSet();
    if (!mounted) return;
    setState(() {
      _sections = sections;
      _selectedGradeId = gradeIds.firstOrNull;
      _selectedSectionId = sections
          .where((section) => section['grade_id'] == _selectedGradeId)
          .map((section) => section['id'] as String)
          .firstOrNull;
    });
  }

  List<Map<String, dynamic>> get _grades {
    final byId = <String, Map<String, dynamic>>{};
    for (final section in _sections) {
      byId[section['grade_id'] as String] =
          section['school_grades'] as Map<String, dynamic>;
    }
    return byId.entries
        .map((entry) => {'id': entry.key, ...entry.value})
        .toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
  }

  List<Map<String, dynamic>> get _sectionsForSelectedGrade => _sections
      .where((section) => section['grade_id'] == _selectedGradeId)
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create a quiz')),
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
                      TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          labelText: 'Quiz title',
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
                          labelText: 'Description',
                        ),
                        maxLines: 2,
                        readOnly: _questionsSaved,
                      ),
                    ],
                  ),
                ),
                if (_role == AppRoles.admin) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey(_selectedSchoolId),
                    initialValue: _selectedSchoolId,
                    decoration: const InputDecoration(labelText: 'School'),
                    items: [
                      for (final school in _schools)
                        DropdownMenuItem(
                          value: school['id'] as String,
                          child: Text(school['name'] as String? ?? 'School'),
                        ),
                    ],
                    onChanged: _isSaving
                        ? null
                        : (schoolId) async {
                            if (schoolId == null) return;
                            setState(() {
                              _selectedSchoolId = schoolId;
                              _sections = [];
                              _selectedGradeId = null;
                              _selectedSectionId = null;
                              _loadingTargets = true;
                              _error = null;
                            });
                            try {
                              await _loadSections(schoolId);
                            } catch (error) {
                              if (mounted) {
                                setState(
                                  () => _error =
                                      'Could not load class sections: $error',
                                );
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _loadingTargets = false);
                              }
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                ],
                if (_role == AppRoles.teacher) ...[
                  if (_assignedCourses.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No subject or class is assigned to your account yet. Ask an administrator to assign your teaching subject and section.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: ValueKey('course-$_selectedCourseId'),
                      initialValue: _selectedCourseId,
                      decoration: const InputDecoration(
                        labelText: 'Assigned subject and class',
                        prefixIcon: Icon(Icons.menu_book_outlined),
                      ),
                      items: [
                        for (final course in _assignedCourses)
                          DropdownMenuItem(
                            value: course['id'] as String,
                            child: Text(course['class_label'] as String),
                          ),
                      ],
                      onChanged: _isSaving
                          ? null
                          : (courseId) =>
                                setState(() => _selectedCourseId = courseId),
                      validator: (value) => value == null
                          ? 'Choose an assigned subject and class'
                          : null,
                    ),
                ] else ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey('grade-$_selectedGradeId'),
                    initialValue: _selectedGradeId,
                    decoration: const InputDecoration(labelText: 'Grade'),
                    items: [
                      for (final grade in _grades)
                        DropdownMenuItem(
                          value: grade['id'] as String,
                          child: Text(grade['name'] as String),
                        ),
                    ],
                    onChanged: _isSaving || _grades.isEmpty
                        ? null
                        : (gradeId) {
                            if (gradeId == null) return;
                            setState(() {
                              _selectedGradeId = gradeId;
                              _selectedSectionId = _sections
                                  .where(
                                    (section) => section['grade_id'] == gradeId,
                                  )
                                  .map((section) => section['id'] as String)
                                  .firstOrNull;
                            });
                          },
                    validator: (value) =>
                        value == null ? 'Choose a grade' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('section-$_selectedSectionId'),
                    initialValue:
                        _sectionsForSelectedGrade.any(
                          (section) => section['id'] == _selectedSectionId,
                        )
                        ? _selectedSectionId
                        : null,
                    decoration: const InputDecoration(labelText: 'Section'),
                    items: [
                      for (final section in _sectionsForSelectedGrade)
                        DropdownMenuItem(
                          value: section['id'] as String,
                          child: Text(section['name'] as String),
                        ),
                    ],
                    onChanged: _isSaving
                        ? null
                        : (sectionId) =>
                              setState(() => _selectedSectionId = sectionId),
                    validator: (value) =>
                        value == null ? 'Choose a section' : null,
                  ),
                ],
                const SizedBox(height: 28),
                Text(
                  'Questions (${_questions.length})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (var index = 0; index < _questions.length; index++)
                  ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(_questions[index]['text'] as String),
                    subtitle: Text(
                      '${_questionTypeLabel(_questions[index]['type'] as String)} · 1 point'
                      '${(_questions[index]['explanation'] as String?)?.isNotEmpty == true ? ' · explanation added' : ''}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove question',
                      onPressed: _isSaving || _questionsSaved
                          ? null
                          : () => setState(() => _questions.removeAt(index)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                const Divider(height: 32),
                if (_questionsSaved)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Questions are saved. Retry publishing to finish.',
                    ),
                  ),
                TextField(
                  controller: _questionController,
                  decoration: const InputDecoration(labelText: 'Question'),
                  textCapitalization: TextCapitalization.sentences,
                  readOnly: _questionsSaved,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _questionType,
                  decoration: const InputDecoration(labelText: 'Question type'),
                  items: const [
                    DropdownMenuItem(
                      value: 'multiple_choice',
                      child: Text('Multiple choice'),
                    ),
                    DropdownMenuItem(
                      value: 'true_false',
                      child: Text('True or false'),
                    ),
                    DropdownMenuItem(
                      value: 'short_answer',
                      child: Text('Fill in the blank'),
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
                if (_questionType == 'short_answer')
                  TextField(
                    controller: _correctAnswerController,
                    decoration: const InputDecoration(
                      labelText: 'Correct answer',
                      hintText: 'The answer students should enter',
                    ),
                    readOnly: _questionsSaved,
                  )
                else
                  RadioGroup<int>(
                    groupValue: _correctOption,
                    onChanged: (value) {
                      if (value != null && !_questionsSaved) {
                        setState(() => _correctOption = value);
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
                          Row(
                            children: [
                              Radio<int>(value: index),
                              Expanded(
                                child: _questionType == 'true_false'
                                    ? Text(index == 0 ? 'True' : 'False')
                                    : TextField(
                                        controller: _optionControllers[index],
                                        readOnly: _questionsSaved,
                                        decoration: InputDecoration(
                                          labelText: 'Option ${index + 1}',
                                        ),
                                      ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                TextField(
                  controller: _explanationController,
                  decoration: const InputDecoration(
                    labelText: 'Answer explanation (optional)',
                    hintText: 'Explain why the correct answer is right',
                  ),
                  maxLines: 2,
                  readOnly: _questionsSaved,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _isSaving || _questionsSaved
                        ? null
                        : _addQuestion,
                    icon: const Icon(Icons.add),
                    label: const Text('Add question'),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _isSaving ? null : _saveQuiz,
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Publish quiz'),
                ),
              ],
            ),
    );
  }

  String _questionTypeLabel(String type) => switch (type) {
    'true_false' => 'True or false',
    'short_answer' => 'Fill in the blank',
    _ => 'Multiple choice',
  };
}
