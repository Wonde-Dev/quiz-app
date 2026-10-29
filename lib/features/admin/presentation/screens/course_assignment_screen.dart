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
  static const String _ciroSchoolId = '00000000-0000-4000-8000-000000000001';

  final _sectionController = TextEditingController();
  final _subjectController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _sections;
  late Future<List<Map<String, dynamic>>> _teachers;
  late Future<List<Map<String, dynamic>>> _assignments;

  String? _teacherId;
  String? _selectedSectionId;
  String _grade = '9';
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>>? _loadedSections;

  @override
  void initState() {
    super.initState();
    _sections = _loadSections();
    _teachers = _loadTeachers();
    _assignments = _loadAssignments();
  }

  @override
  void dispose() {
    _sectionController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadTeachers() async {
    final rows = await Supabase.instance.client
        .from('users')
        .select('id, full_name, username, assigned_subject')
        .eq('role', 'teacher')
        .neq('is_active', false)
        .order('full_name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> _loadAssignments() async {
    final client = Supabase.instance.client;
    try {
      final rows = await client
          .from('teacher_courses')
          .select('id, teacher_id, section_id, subject, sections(id, name, grade), users(id, full_name, username)')
          .order('assigned_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(rows);
      return list.map((item) {
        final teacher = item['users'] as Map<String, dynamic>?;
        final section = item['sections'] as Map<String, dynamic>?;
        final teacherName = teacher?['full_name'] as String? ?? teacher?['username'] as String? ?? 'Teacher';
        final grade = section?['grade']?.toString() ?? 'Grade 9';
        final secName = section?['name']?.toString() ?? 'A';
        final classLabel = secName.length > 1 ? secName : '$grade Class $secName';

        return {
          'id': item['id'],
          'teacher_id': item['teacher_id'],
          'section_id': item['section_id'],
          'subject': item['subject'] ?? 'General',
          'teacher_name': teacherName,
          'class_label': classLabel,
          'grade': grade,
        };
      }).toList();
    } catch (e) {
      debugPrint('Error loading assignments from teacher_courses: $e');
      // Fallback to courses table
      final rows = await client
          .from('courses')
          .select('id, teacher_id, section_id, subject, name')
          .order('subject');
      final courses = List<Map<String, dynamic>>.from(rows);
      return courses.map((c) => {
        'id': c['id'],
        'teacher_id': c['teacher_id'],
        'section_id': c['section_id'],
        'subject': c['subject'] ?? 'General',
        'teacher_name': 'Teacher',
        'class_label': c['name'] ?? 'Class',
        'grade': 'Grade',
      }).toList();
    }
  }

  Future<List<Map<String, dynamic>>> _loadSections() async {
    final rows = await Supabase.instance.client
        .from('sections')
        .select('id, name, grade, school_id')
        .eq('school_id', _ciroSchoolId)
        .order('name');
    final list = List<Map<String, dynamic>>.from(rows);
    _loadedSections = list;
    return list;
  }

  Future<void> _addSection() async {
    final name = _sectionController.text.trim().toUpperCase();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a section name (e.g. A, B, C).');
      return;
    }
    if (name.length > 10) {
      setState(() => _error = 'Section name can be at most 10 characters.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final gradeRow = await client
          .from('school_grades')
          .upsert({
            'school_id': _ciroSchoolId,
            'name': 'Grade $_grade',
          }, onConflict: 'school_id,name')
          .select('id')
          .single();

      await client.from('sections').insert({
        'school_id': _ciroSchoolId,
        'grade_id': gradeRow['id'],
        'name': name,
        'grade': 'Grade $_grade',
      });

      _sectionController.clear();
      if (mounted) {
        setState(() {
          _sections = _loadSections();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Section $name added for Grade $_grade.'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
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
    final teacherId = _teacherId;
    final sectionId = _selectedSectionId;
    final subject = _subjectController.text.trim();

    if (teacherId == null || sectionId == null) {
      setState(() => _error = 'Choose a faculty teacher, grade, and section.');
      return;
    }
    if (subject.isEmpty || subject.length > 80) {
      setState(() => _error = 'Enter a subject name (up to 80 characters).');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      // 1. Try dedicated RPC
      try {
        await client.rpc('assign_teacher_to_class', params: {
          'p_teacher_id': teacherId,
          'p_section_id': sectionId,
          'p_subject': subject,
        });
      } catch (_) {
        await client.from('teacher_courses').insert({
          'teacher_id': teacherId,
          'section_id': sectionId,
          'subject': subject,
        });
      }

      // 2. Also keep courses table in sync
      try {
        final secRow = _sectionsForGrade.firstWhere(
          (s) => s['id'] == sectionId,
          orElse: () => {'name': ''},
        );
        final secName = secRow['name'] ?? '';
        await client.from('courses').insert({
          'school_id': _ciroSchoolId,
          'teacher_id': teacherId,
          'section_id': sectionId,
          'name': '$subject · Grade $_grade $secName',
          'subject': subject,
        });
      } catch (_) {}

      if (mounted) {
        setState(() {
          _subjectController.clear();
          _assignments = _loadAssignments();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$subject assigned to the teacher for Grade $_grade.'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
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

  Future<void> _deleteAssignment(String id) async {
    try {
      await Supabase.instance.client.from('teacher_courses').delete().eq('id', id);
      try {
        await Supabase.instance.client.from('courses').delete().eq('id', id);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _assignments = _loadAssignments();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Class assignment removed.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error deleting assignment: $e');
    }
  }

  List<Map<String, dynamic>> get _sectionsForGrade =>
      _sectionsSnapshot.where((section) {
        final grade = section['grade']?.toString() ?? '';
        return grade == 'Grade $_grade' || grade.endsWith(_grade);
      }).toList();

  List<Map<String, dynamic>> get _sectionsSnapshot =>
      _loadedSections ?? const [];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DashboardShell(
      title: 'Class & Teacher Allocations',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.school_rounded, color: Color(0xFF10B981), size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ciro High School Academic Allocations',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Manage classroom sections and allocate teachers across multiple grades and subjects.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Form: Assign Teacher to Class
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.add_task_rounded, color: Color(0xFF10B981), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Assign Faculty to Class & Subject',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Teacher Picker
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _teachers,
                  builder: (context, teacherSnapshot) {
                    final teachers = teacherSnapshot.data ?? [];
                    return DropdownButtonFormField<String>(
                      initialValue: _teacherId,
                      decoration: const InputDecoration(
                        labelText: 'Faculty Teacher *',
                        prefixIcon: Icon(Icons.co_present_rounded),
                      ),
                      items: [
                        for (final teacher in teachers)
                          DropdownMenuItem(
                            value: teacher['id'] as String,
                            child: Text(
                              '${teacher['full_name'] ?? teacher['username']} (${teacher['assigned_subject'] ?? 'Faculty'})',
                            ),
                          ),
                      ],
                      onChanged: (teacherId) {
                        setState(() {
                          _teacherId = teacherId;
                          if (teacherId != null) {
                            final match = teachers.firstWhere(
                              (t) => t['id'] == teacherId,
                              orElse: () => {},
                            );
                            if (match['assigned_subject'] != null && _subjectController.text.isEmpty) {
                              _subjectController.text = match['assigned_subject'] as String;
                            }
                          }
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 12),

                // Grade & Section Row
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _grade,
                        decoration: const InputDecoration(
                          labelText: 'Grade Level',
                          prefixIcon: Icon(Icons.grade_rounded),
                        ),
                        items: const [
                          DropdownMenuItem(value: '9', child: Text('Grade 9')),
                          DropdownMenuItem(value: '10', child: Text('Grade 10')),
                          DropdownMenuItem(value: '11', child: Text('Grade 11')),
                          DropdownMenuItem(value: '12', child: Text('Grade 12')),
                        ],
                        onChanged: (grade) {
                          if (grade == null) return;
                          setState(() {
                            _grade = grade;
                            _selectedSectionId = null;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: _sections,
                        builder: (context, sectionSnapshot) {
                          final sections = _sectionsForGrade;
                          return DropdownButtonFormField<String>(
                            key: ValueKey('sec_${_grade}_$_selectedSectionId'),
                            initialValue: _selectedSectionId,
                            decoration: const InputDecoration(
                              labelText: 'Section / Class',
                              prefixIcon: Icon(Icons.meeting_room_outlined),
                            ),
                            items: [
                              for (final section in sections)
                                DropdownMenuItem(
                                  value: section['id'] as String,
                                  child: Text('Section ${section['name']}'),
                                ),
                            ],
                            onChanged: (sectionId) {
                              setState(() => _selectedSectionId = sectionId);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Subject Field
                TextField(
                  controller: _subjectController,
                  decoration: const InputDecoration(
                    labelText: 'Subject Name *',
                    hintText: 'e.g. Mathematics, Physics, Chemistry',
                    prefixIcon: Icon(Icons.menu_book_outlined),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.add_task_rounded, size: 18),
                    label: const Text('Assign Class to Teacher'),
                    onPressed: _saving ? null : _assignTeacher,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Add New Section Accordion / Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.add_circle_outline_rounded, color: Color(0xFF6366F1), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Create New Class Section',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _sectionController,
                        decoration: InputDecoration(
                          labelText: 'Section Letter (e.g. D, E)',
                          hintText: 'A, B, C...',
                          helperText: 'For Grade $_grade in Ciro High School',
                          prefixIcon: const Icon(Icons.border_color_outlined),
                        ),
                        textCapitalization: TextCapitalization.characters,
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Section'),
                      onPressed: _saving ? null : _addSection,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Current Assignments Roster
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Active Teaching Allocations',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: 'Refresh assignments',
                onPressed: () {
                  setState(() {
                    _assignments = _loadAssignments();
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 10),

          FutureBuilder<List<Map<String, dynamic>>>(
            future: _assignments,
            builder: (context, assignmentSnapshot) {
              if (assignmentSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
                );
              }
              final assignments = assignmentSnapshot.data ?? [];
              if (assignments.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Text(
                      'No classes assigned yet. Use the form above to allocate teachers.',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: assignments.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final assignment = assignments[index];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.co_present_rounded, color: Color(0xFF10B981), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${assignment['teacher_name']} · ${assignment['subject']}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                assignment['class_label'] as String,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                          tooltip: 'Remove allocation',
                          onPressed: () => _deleteAssignment(assignment['id'] as String),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
