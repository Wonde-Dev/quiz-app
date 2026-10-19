import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/utils/supabase_error_message.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class CourseAssignmentScreen extends StatefulWidget {
  const CourseAssignmentScreen({super.key});

  @override
  State<CourseAssignmentScreen> createState() => _CourseAssignmentScreenState();
}

class _CourseAssignmentScreenState extends State<CourseAssignmentScreen> {
  final _sectionController = TextEditingController();
  final _subjectController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _schools;
  late Future<List<Map<String, dynamic>>> _sections;
  late Future<List<Map<String, dynamic>>> _teachers;
  late Future<List<Map<String, dynamic>>> _assignments;
  String? _schoolId;
  String? _teacherId;
  String? _selectedSectionId;
  String _grade = '9';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _schools = _loadSchools();
    _sections = Future.value(const []);
    _teachers = Future.value(const []);
    _assignments = Future.value(const []);
  }

  @override
  void dispose() {
    _sectionController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadSchools() async {
    final rows = await Supabase.instance.client
        .from('schools')
        .select('id, name')
        .order('name');
    final schools = List<Map<String, dynamic>>.from(rows);
    if (schools.isNotEmpty && _schoolId == null) {
      _schoolId = schools.first['id'] as String;
      _sections = _loadSections(_schoolId!);
      _teachers = _loadTeachers(_schoolId!);
      _assignments = _loadAssignments(_schoolId!);
    }
    return schools;
  }

  Future<List<Map<String, dynamic>>> _loadTeachers(String schoolId) async {
    final rows = await Supabase.instance.client
        .from('users')
        .select('id, full_name, username')
        .eq('role', 'teacher')
        .eq('school_id', schoolId)
        .order('full_name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> _loadAssignments(String schoolId) async {
    final client = Supabase.instance.client;
    final rows = await client
        .from('courses')
        .select('id, teacher_id, section_id, subject, name')
        .eq('school_id', schoolId)
        .order('subject');
    final courses = List<Map<String, dynamic>>.from(rows);
    if (courses.isEmpty) return [];
    final teacherIds = courses
        .map((course) => course['teacher_id'])
        .whereType<String>()
        .toSet()
        .toList();
    final sectionIds = courses
        .map((course) => course['section_id'])
        .whereType<String>()
        .toSet()
        .toList();
    final teachers = teacherIds.isEmpty
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(
            await client
                .from('users')
                .select('id, full_name, username')
                .inFilter('id', teacherIds),
          );
    final sections = sectionIds.isEmpty
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(
            await client
                .from('sections')
                .select('id, name, school_grades!inner(name)')
                .inFilter('id', sectionIds),
          );
    final teacherById = {
      for (final teacher in teachers) teacher['id'] as String: teacher,
    };
    final sectionById = {
      for (final section in sections) section['id'] as String: section,
    };
    return courses.map((course) {
      final teacher = teacherById[course['teacher_id']];
      final section = sectionById[course['section_id']];
      final grade = section?['school_grades'] as Map<String, dynamic>?;
      return {
        ...course,
        'teacher_name':
            teacher?['full_name'] as String? ??
            teacher?['username'] as String? ??
            'Teacher',
        'class_label': section == null || grade == null
            ? 'Class unavailable'
            : '${grade['name']} ${section['name']}',
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _loadSections(String schoolId) async {
    final rows = await Supabase.instance.client
        .from('sections')
        .select('id, name, school_grades!inner(name)')
        .eq('school_id', schoolId)
        .order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _addSection() async {
    final schoolId = _schoolId;
    final name = _sectionController.text.trim().toUpperCase();
    if (schoolId == null || name.isEmpty) {
      setState(() => _error = 'Choose a school and enter a section name.');
      return;
    }
    if (name.length > 20) {
      setState(() => _error = 'Section names can be at most 20 characters.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final grade = await client
          .from('school_grades')
          .upsert({
            'school_id': schoolId,
            'name': 'Grade $_grade',
          }, onConflict: 'school_id,name')
          .select('id')
          .single();
      await client.from('sections').insert({
        'school_id': schoolId,
        'grade_id': grade['id'],
        'name': name,
        'grade': 'Grade $_grade',
      });
      _sectionController.clear();
      if (mounted) {
        setState(() {
          _sections = _loadSections(schoolId);
          _loadedSections = null;
        });
      }
    } catch (error) {
      if (mounted) {
        final message = error is PostgrestException && error.code == '23505'
            ? 'Section "$name" already exists for Grade $_grade.'
            : supabaseErrorMessage(error, action: 'Could not add section');
        setState(() => _error = message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _assignTeacher() async {
    final schoolId = _schoolId;
    final teacherId = _teacherId;
    final section = _sectionsForGrade
        .where((item) => item['id'] == _selectedSectionId)
        .firstOrNull;
    final subject = _subjectController.text.trim();
    if (schoolId == null || teacherId == null || section == null) {
      setState(() => _error = 'Choose a teacher, grade, and section.');
      return;
    }
    if (subject.isEmpty || subject.length > 80) {
      setState(() => _error = 'Enter a subject (up to 80 characters).');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final sectionName = section['name'] as String;
      await Supabase.instance.client.from('courses').insert({
        'school_id': schoolId,
        'teacher_id': teacherId,
        'section_id': section['id'],
        'name': '$subject · Grade $_grade $sectionName',
        'subject': subject,
      });
      if (mounted) {
        setState(() {
          _subjectController.clear();
          _assignments = _loadAssignments(schoolId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$subject assigned to the selected teacher and class.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = supabaseErrorMessage(
            error,
            action: 'Could not assign teacher',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<Map<String, dynamic>> get _sectionsForGrade =>
      _sectionsSnapshot.where((section) {
        final grade = section['school_grades'] as Map<String, dynamic>?;
        return grade?['name'] == 'Grade $_grade';
      }).toList();

  List<Map<String, dynamic>> get _sectionsSnapshot =>
      _loadedSections ?? const [];

  List<Map<String, dynamic>>? _loadedSections;

  @override
  Widget build(BuildContext context) {
    return DashboardShell(
      title: 'Classes and teacher assignments',
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _schools,
        builder: (context, schoolSnapshot) {
          if (schoolSnapshot.hasError) {
            return Center(
              child: Text('Could not load schools: ${schoolSnapshot.error}'),
            );
          }
          if (!schoolSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final schools = schoolSnapshot.data!;
          if (schools.isEmpty) {
            return const Center(child: Text('Create a school first.'));
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Create class sections for grades 9 through 12. Students and quizzes are assigned to a section.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                key: ValueKey(_schoolId),
                initialValue: _schoolId,
                decoration: const InputDecoration(labelText: 'School'),
                items: [
                  for (final school in schools)
                    DropdownMenuItem(
                      value: school['id'] as String,
                      child: Text(school['name'] as String? ?? 'School'),
                    ),
                ],
                onChanged: (schoolId) {
                  if (schoolId == null) return;
                  setState(() {
                    _schoolId = schoolId;
                    _sections = _loadSections(schoolId);
                    _teachers = _loadTeachers(schoolId);
                    _assignments = _loadAssignments(schoolId);
                    _teacherId = null;
                    _selectedSectionId = null;
                    _loadedSections = null;
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _grade,
                decoration: const InputDecoration(labelText: 'Grade'),
                items: [
                  for (var grade = 9; grade <= 12; grade++)
                    DropdownMenuItem(
                      value: '$grade',
                      child: Text('Grade $grade'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _grade = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sectionController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Section',
                  hintText: 'A, B, C, or another section name',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _addSection,
                icon: const Icon(Icons.add),
                label: const Text('Add section'),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assign a teacher',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Teachers can create quizzes only for subjects and class sections assigned here.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: _teachers,
                        builder: (context, teacherSnapshot) {
                          if (teacherSnapshot.hasError) {
                            return Text(
                              'Could not load teachers: ${teacherSnapshot.error}',
                            );
                          }
                          if (!teacherSnapshot.hasData) {
                            return const LinearProgressIndicator();
                          }
                          final teachers = teacherSnapshot.data!;
                          if (teachers.isEmpty) {
                            return const Text(
                              'Create a teacher account for this school before assigning subjects.',
                            );
                          }
                          return DropdownButtonFormField<String>(
                            key: ValueKey('$_schoolId-$_teacherId'),
                            initialValue: _teacherId,
                            decoration: const InputDecoration(
                              labelText: 'Teacher',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            items: [
                              for (final teacher in teachers)
                                DropdownMenuItem(
                                  value: teacher['id'] as String,
                                  child: Text(
                                    teacher['full_name'] as String? ??
                                        teacher['username'] as String? ??
                                        'Teacher',
                                  ),
                                ),
                            ],
                            onChanged: _saving
                                ? null
                                : (value) => setState(() => _teacherId = value),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _subjectController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Subject',
                          hintText: 'e.g. Biology',
                          prefixIcon: Icon(Icons.menu_book_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey('assignment-grade-$_grade'),
                        initialValue: _grade,
                        decoration: const InputDecoration(labelText: 'Grade'),
                        items: [
                          for (var grade = 9; grade <= 12; grade++)
                            DropdownMenuItem(
                              value: '$grade',
                              child: Text('Grade $grade'),
                            ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _grade = value);
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: _sections,
                        builder: (context, sectionSnapshot) {
                          if (sectionSnapshot.hasError) {
                            return Text(
                              'Could not load sections: ${sectionSnapshot.error}',
                            );
                          }
                          if (!sectionSnapshot.hasData) {
                            return const LinearProgressIndicator();
                          }
                          _loadedSections = sectionSnapshot.data!;
                          final sections = _sectionsForGrade;
                          return DropdownButtonFormField<String>(
                            key: ValueKey(
                              'assignment-$_grade-$_selectedSectionId',
                            ),
                            initialValue:
                                sections.any(
                                  (section) =>
                                      section['id'] == _selectedSectionId,
                                )
                                ? _selectedSectionId
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Section',
                            ),
                            items: [
                              for (final section in sections)
                                DropdownMenuItem(
                                  value: section['id'] as String,
                                  child: Text(section['name'] as String),
                                ),
                            ],
                            onChanged: _saving
                                ? null
                                : (value) => setState(
                                    () => _selectedSectionId = value,
                                  ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _saving ? null : _assignTeacher,
                        icon: const Icon(Icons.assignment_ind_outlined),
                        label: const Text('Assign subject and class'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Current teacher assignments',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _assignments,
                builder: (context, assignmentSnapshot) {
                  if (assignmentSnapshot.hasError) {
                    return Text(
                      'Could not load assignments: ${assignmentSnapshot.error}',
                    );
                  }
                  if (!assignmentSnapshot.hasData) {
                    return const LinearProgressIndicator();
                  }
                  final assignments = assignmentSnapshot.data!;
                  if (assignments.isEmpty) {
                    return const ListTile(
                      title: Text(
                        'No teaching assignments for this school yet.',
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final assignment in assignments)
                        Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.menu_book_outlined),
                            ),
                            title: Text(
                              assignment['subject'] as String? ??
                                  assignment['name'] as String? ??
                                  'Subject',
                            ),
                            subtitle: Text(
                              '${assignment['teacher_name']} · ${assignment['class_label']}',
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const Divider(height: 32),
              Text(
                'Available sections',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _sections,
                builder: (context, sectionSnapshot) {
                  if (sectionSnapshot.hasError) {
                    return Text(
                      'Could not load sections: ${sectionSnapshot.error}',
                    );
                  }
                  if (!sectionSnapshot.hasData) {
                    return const LinearProgressIndicator();
                  }
                  if (sectionSnapshot.data!.isEmpty) {
                    return const ListTile(
                      title: Text(
                        'No sections have been created for this school.',
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final section in sectionSnapshot.data!)
                        ListTile(
                          leading: const Icon(Icons.class_outlined),
                          title: Text(
                            '${(section['school_grades'] as Map<String, dynamic>)['name']} · ${section['name']}',
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
