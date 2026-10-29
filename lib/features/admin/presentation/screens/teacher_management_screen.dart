import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/services/student_password_reset_service.dart';
import 'package:quiz_app/shared/widgets/animated_press_button.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class TeacherManagementScreen extends ConsumerStatefulWidget {
  const TeacherManagementScreen({super.key});

  @override
  ConsumerState<TeacherManagementScreen> createState() =>
      _TeacherManagementScreenState();
}

class _TeacherManagementScreenState
    extends ConsumerState<TeacherManagementScreen> {
  static const String _ciroSchoolId = '00000000-0000-4000-8000-000000000001';

  final _searchController = TextEditingController();
  final _resetService = StudentPasswordResetService();
  late Future<List<Map<String, dynamic>>> _teachersFuture;
  List<Map<String, dynamic>> _sections = [];
  bool _isResetting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _teachersFuture = _loadTeachers();
    _loadSections();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSections() async {
    try {
      final rows = await Supabase.instance.client
          .from('sections')
          .select('id, name, grade, school_id')
          .eq('school_id', _ciroSchoolId);
      if (mounted) {
        setState(() {
          _sections = List<Map<String, dynamic>>.from(rows);
        });
      }
    } catch (e) {
      debugPrint('Error loading sections for assignment: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _loadTeachers() async {
    final client = Supabase.instance.client;

    try {
      final results = await Future.wait<dynamic>([
        client
            .from('users')
            .select(
              'id, full_name, username, email, school_id, approval_status, is_active, created_at, '
              'is_attendance_teacher, attendance_grade, attendance_class, assigned_grade, assigned_class, assigned_subject, requested_subject, schools(name)',
            )
            .eq('role', AppRoles.teacher)
            .neq('is_active', false)
            .order('full_name', ascending: true),
        client
            .from('teacher_courses')
            .select('id, teacher_id, section_id, subject, sections(id, name, grade)')
            .order('assigned_at', ascending: false),
      ]);

      final teachers = List<Map<String, dynamic>>.from(results[0] as List);
      final teacherCourses = List<Map<String, dynamic>>.from(results[1] as List);

      for (final t in teachers) {
        final assigned = teacherCourses
            .where((tc) => tc['teacher_id'] == t['id'])
            .toList();
        t['teaching_classes'] = assigned;
      }

      return teachers;
    } catch (e) {
      debugPrint('Error loading teachers: $e');
      rethrow;
    }
  }

  Future<void> _manageTeacherClasses(Map<String, dynamic> teacher) async {
    final teacherId = teacher['id'] as String;
    final teacherName = teacher['full_name'] as String? ?? teacher['username'] as String? ?? 'Faculty Member';
    final primarySubject = teacher['assigned_subject'] as String? ?? teacher['requested_subject'] as String? ?? 'General';

    String selectedGrade = 'Grade 9';
    String selectedClass = '9A';
    final subjectController = TextEditingController(text: primarySubject);
    List<Map<String, dynamic>> currentAssignments = List<Map<String, dynamic>>.from(
      teacher['teaching_classes'] ?? [],
    );

    final grades = ['Grade 9', 'Grade 10', 'Grade 11', 'Grade 12'];

    List<String> getClassesForGrade(String grade) {
      final numPart = grade.replaceAll(RegExp(r'[^0-9]'), '');
      return ['${numPart}A', '${numPart}B', '${numPart}C', '${numPart}D', '${numPart}E'];
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
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
                      Row(
                        children: [
                          const Icon(Icons.class_rounded, color: Color(0xFF10B981), size: 24),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Class Assignments',
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                              ),
                              Text(
                                'Faculty: $teacherName',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Teachers can be assigned to teach different subjects across multiple grades and classes in Ciro High School.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 16),

                  // Current Assignments list
                  const Text(
                    'CURRENT ASSIGNED CLASSES',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.6),
                  ),
                  const SizedBox(height: 8),

                  if (currentAssignments.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, size: 18, color: Color(0xFF94A3B8)),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'No classes assigned yet. Use the form below to allocate teaching classes.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: currentAssignments.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, idx) {
                        final item = currentAssignments[idx];
                        final secMap = item['sections'] as Map<String, dynamic>?;
                        final secGrade = secMap?['grade']?.toString() ?? 'Grade';
                        final secName = secMap?['name']?.toString() ?? '';
                        final sub = item['subject']?.toString() ?? 'General';
                        final classLabel = secName.isNotEmpty
                            ? (secName.length > 1 ? secName : '$secGrade Class $secName')
                            : 'Assigned Class';

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.menu_book_rounded, color: Color(0xFF10B981), size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$sub · $classLabel',
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                                    ),
                                    Text(
                                      secGrade,
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                                tooltip: 'Remove class assignment',
                                onPressed: () async {
                                  try {
                                    await Supabase.instance.client
                                        .from('teacher_courses')
                                        .delete()
                                        .eq('id', item['id']);

                                    setSheetState(() {
                                      currentAssignments.removeAt(idx);
                                    });
                                    setState(() {
                                      _teachersFuture = _loadTeachers();
                                    });
                                  } catch (e) {
                                    debugPrint('Error removing class assignment: $e');
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 10),

                  // Add New Class Allocation Section
                  const Text(
                    '+ ASSIGN ANOTHER GRADE & CLASS',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF047857), letterSpacing: 0.6),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedGrade,
                          decoration: const InputDecoration(
                            labelText: 'Grade Level',
                            prefixIcon: Icon(Icons.grade_rounded),
                          ),
                          items: grades.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setSheetState(() {
                                selectedGrade = val;
                                final classes = getClassesForGrade(val);
                                if (!classes.contains(selectedClass)) {
                                  selectedClass = classes.first;
                                }
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('sec_${selectedGrade}_$selectedClass'),
                          initialValue: selectedClass,
                          decoration: const InputDecoration(
                            labelText: 'Class / Section',
                            prefixIcon: Icon(Icons.meeting_room_outlined),
                          ),
                          items: getClassesForGrade(selectedGrade)
                              .map((c) => DropdownMenuItem(value: c, child: Text('Class $c')))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setSheetState(() => selectedClass = val);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: subjectController,
                    decoration: const InputDecoration(
                      labelText: 'Teaching Subject for this Class *',
                      hintText: 'e.g. Mathematics, Physics, Chemistry',
                      prefixIcon: Icon(Icons.book_outlined),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),

                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.add_task_rounded, size: 18),
                    label: const Text('Add Class Assignment'),
                    onPressed: () async {
                      final subject = subjectController.text.trim();
                      if (subject.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a subject.')),
                        );
                        return;
                      }

                      // Resolve section_id from _sections
                      final letterOnly = selectedClass.replaceAll(RegExp(r'^[0-9]+'), '');
                      String? resolvedSectionId;
                      for (final s in _sections) {
                        final sGrade = s['grade']?.toString() ?? '';
                        final sName = s['name']?.toString() ?? '';
                        if (sGrade.toLowerCase() == selectedGrade.toLowerCase() &&
                            (sName.toLowerCase() == selectedClass.toLowerCase() ||
                             sName.toLowerCase() == letterOnly.toLowerCase())) {
                          resolvedSectionId = s['id'] as String;
                          break;
                        }
                      }
                      if (resolvedSectionId == null && _sections.isNotEmpty) {
                        resolvedSectionId = _sections.first['id'] as String;
                      }

                      try {
                        final client = Supabase.instance.client;
                        try {
                          await client.rpc('assign_teacher_to_class', params: {
                            'p_teacher_id': teacherId,
                            'p_section_id': resolvedSectionId,
                            'p_subject': subject,
                          });
                        } catch (_) {
                          await client.from('teacher_courses').insert({
                            'teacher_id': teacherId,
                            'section_id': resolvedSectionId,
                            'subject': subject,
                          });
                        }

                        // Also update courses table for backwards compatibility
                        try {
                          await client.from('courses').insert({
                            'school_id': _ciroSchoolId,
                            'teacher_id': teacherId,
                            'section_id': resolvedSectionId,
                            'name': '$subject · $selectedGrade Class $selectedClass',
                            'subject': subject,
                          });
                        } catch (_) {}

                        // Refresh local list
                        final newTcRows = await client
                            .from('teacher_courses')
                            .select('id, teacher_id, section_id, subject, sections(id, name, grade)')
                            .eq('teacher_id', teacherId);

                        setSheetState(() {
                          currentAssignments = List<Map<String, dynamic>>.from(newTcRows);
                        });
                        setState(() {
                          _teachersFuture = _loadTeachers();
                        });

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Class $selectedClass assigned to $teacherName.'),
                              backgroundColor: const Color(0xFF10B981),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to assign class: $e'),
                              backgroundColor: Colors.red,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _resetTeacherPassword(Map<String, dynamic> teacher) async {
    final id = teacher['id'] as String;
    final name = teacher['full_name'] as String? ?? teacher['username'] as String? ?? 'Teacher';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        title: const Text('Reset Teacher Password?'),
        content: Text(
          'This will generate a secure temporary password matching institutional format for $name. '
          'They will be asked to update their password upon next sign in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset Password'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isResetting = true;
      _error = null;
    });

    try {
      final username = teacher['username'] as String? ?? '';
      final result = await _resetService.resetPasswordDirect(
        accountId: id,
        username: username,
        role: AppRoles.teacher,
      );

      if (!mounted) return;

      // Show temporary credential copy dialog
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Color(0xFF10B981)),
              SizedBox(width: 10),
              Text('Password Reset Done'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Faculty member: $name'),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TEMPORARY CREDENTIALS',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                    const SizedBox(height: 6),
                    Text('Username: $username', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    SelectableText(
                      'Password: ${result.temporaryPassword}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy Info'),
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: 'Username: $username\nPassword: ${result.temporaryPassword}'),
                );
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Credentials copied to clipboard!'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not reset password: $e');
      }
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  Future<void> _deleteTeacher(Map<String, dynamic> teacher) async {
    final id = teacher['id'] as String;
    final name = teacher['full_name'] as String? ?? teacher['username'] as String? ?? 'Teacher';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        title: const Text('Delete Faculty Account?'),
        content: Text(
          'Permanently remove $name from Ciro High School registry? '
          'Their assignments, answer sheets, and teaching records will be purged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Faculty'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isResetting = true;
      _error = null;
    });

    try {
      bool deleted = false;
      try {
        await Supabase.instance.client
            .rpc('delete_user_account', params: {'user_id': id, 'p_user_id': id});
        deleted = true;
      } catch (rpcErr) {
        debugPrint('delete_user_account RPC note: $rpcErr');
      }

      if (!deleted) {
        try {
          await Supabase.instance.client.functions.invoke(
            'manage-account',
            body: {'action': 'delete', 'userId': id},
          );
          deleted = true;
        } catch (_) {}
      }

      if (!deleted) {
        try {
          await Supabase.instance.client.from('course_resources').delete().eq('teacher_id', id);
        } catch (_) {}
        try {
          await Supabase.instance.client.from('teacher_courses').delete().eq('teacher_id', id);
        } catch (_) {}
        try {
          await Supabase.instance.client.from('courses').delete().eq('teacher_id', id);
        } catch (_) {}
        try {
          await Supabase.instance.client.from('users').delete().eq('id', id);
          deleted = true;
        } catch (_) {
          await Supabase.instance.client.from('users').update({
            'is_active': false,
            'approval_status': 'rejected',
          }).eq('id', id);
          deleted = true;
        }
      }

      if (!mounted) return;
      setState(() {
        _teachersFuture = _loadTeachers();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Account for $name was removed.'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not delete teacher: $e');
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  Future<void> _editTeacher(Map<String, dynamic> teacher) async {
    final id = teacher['id'] as String;
    final currentName = teacher['full_name'] as String? ?? '';
    final currentEmail = teacher['email'] as String? ?? '';
    final currentSubject = teacher['assigned_subject'] as String? ??
        teacher['requested_subject'] as String? ??
        '';
    bool isAttendance = teacher['is_attendance_teacher'] == true;
    String attendanceClass = teacher['attendance_class'] as String? ?? '9A';
    String attendanceGrade = teacher['attendance_grade'] as String? ?? 'Grade 9';
    bool isActive = teacher['is_active'] != false;

    final nameController = TextEditingController(text: currentName);
    final emailController = TextEditingController(text: currentEmail);
    final subjectController = TextEditingController(text: currentSubject);

    final standardClasses = ['9A', '9B', '9C', '9D', '10A', '10B', '10C', '11A', '11B', '12A'];

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          title: const Row(
            children: [
              Icon(Icons.edit_note_rounded, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text('Edit Faculty Profile'),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: subjectController,
                    decoration: const InputDecoration(
                      labelText: 'Primary Teaching Subject',
                      prefixIcon: Icon(Icons.menu_book_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Attendance Teacher Designation
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isAttendance
                          ? const Color(0xFF10B981).withValues(alpha: 0.1)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isAttendance
                            ? const Color(0xFF10B981)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Attendance Teacher / Homeroom Master',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          subtitle: const Text(
                            'Grants authority to register students and approve registrations for their homeroom class.',
                            style: TextStyle(fontSize: 11),
                          ),
                          value: isAttendance,
                          onChanged: (val) => setDialogState(() => isAttendance = val),
                        ),
                        if (isAttendance) ...[
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: attendanceClass,
                            decoration: const InputDecoration(
                              labelText: 'Designated Class (e.g. 9A, 9B)',
                              prefixIcon: Icon(Icons.meeting_room_outlined),
                            ),
                            items: [
                              for (final c in standardClasses)
                                DropdownMenuItem(value: c, child: Text('Class $c')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setDialogState(() {
                                  attendanceClass = val;
                                  final numPart = val.replaceAll(RegExp(r'[^0-9]'), '');
                                  attendanceGrade = 'Grade $numPart';
                                });
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  SwitchListTile(
                    title: const Text('Account Active', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      isActive ? 'Teacher can sign in and manage quizzes' : 'Account suspended / deactivated',
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: isActive,
                    onChanged: (v) => setDialogState(() => isActive = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) return;

    setState(() {
      _isResetting = true;
      _error = null;
    });

    try {
      final newName = nameController.text.trim();
      final newEmail = emailController.text.trim();
      final newSubject = subjectController.text.trim();
      bool updated = false;

      try {
        await Supabase.instance.client.rpc(
          'admin_update_user',
          params: {
            'p_user_id': id,
            'p_full_name': newName,
            'p_email': newEmail,
            'p_is_active': isActive,
            'p_is_attendance_teacher': isAttendance,
            'p_attendance_class': isAttendance ? attendanceClass : null,
            'p_attendance_grade': isAttendance ? attendanceGrade : null,
            'p_assigned_subject': newSubject,
          },
        );
        updated = true;
      } catch (rpcErr) {
        debugPrint('admin_update_user RPC note: $rpcErr');
      }

      if (!updated) {
        await Supabase.instance.client.from('users').update({
          'full_name': newName,
          'email': newEmail,
          'is_active': isActive,
          'is_attendance_teacher': isAttendance,
          'attendance_class': isAttendance ? attendanceClass : null,
          'attendance_grade': isAttendance ? attendanceGrade : null,
          'assigned_subject': newSubject,
        }).eq('id', id);
      }

      if (!mounted) return;
      setState(() {
        _teachersFuture = _loadTeachers();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Faculty account updated successfully!'),
          backgroundColor: Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not update teacher: $e');
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DashboardShell(
      title: 'Teacher Directory & Assignments',
      body: RefreshIndicator(
        onRefresh: () async {
          final future = _loadTeachers();
          setState(() {
            _teachersFuture = future;
          });
          await future;
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Header summary card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.3)
                        : const Color(0xFF0F172A).withValues(alpha: 0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/images/teachers.jpeg',
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.co_present_rounded,
                          color: Color(0xFF10B981),
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ciro High School Faculty Directory',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Assign multiple grades, classes, and subjects, reset credentials, or moderate faculty accounts.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Quick Actions Bar
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.person_add_rounded, size: 18),
                    label: const Text('Register New Teacher'),
                    onPressed: () async {
                      await context.push('/admin/register-user');
                      setState(() {
                        _teachersFuture = _loadTeachers();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                  label: const Text('Teacher Approvals'),
                  onPressed: () async {
                    await context.push('/admin/approvals');
                    setState(() {
                      _teachersFuture = _loadTeachers();
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Search Bar
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search faculty by name, username, or subject...',
                prefixIcon: const Icon(Icons.search_rounded),
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
            const SizedBox(height: 16),

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

            FutureBuilder<List<Map<String, dynamic>>>(
              future: _teachersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ));
                }

                if (snapshot.hasError) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Text('Could not load teachers: ${snapshot.error}'),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => setState(() {
                              _teachersFuture = _loadTeachers();
                            }),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final teachers = snapshot.data ?? [];
                final query = _searchController.text.trim().toLowerCase();
                final filtered = teachers.where((t) {
                  final name = (t['full_name'] as String? ?? '').toLowerCase();
                  final uname = (t['username'] as String? ?? '').toLowerCase();
                  final subject = (t['assigned_subject'] as String? ?? t['requested_subject'] as String? ?? '').toLowerCase();
                  final attClass = (t['attendance_class'] as String? ?? '').toLowerCase();
                  return name.contains(query) || uname.contains(query) || subject.contains(query) || attClass.contains(query);
                }).toList();

                if (filtered.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(36),
                      child: Center(
                        child: Text(
                          teachers.isEmpty ? 'No teachers found in Ciro High School.' : 'No faculty matches your search.',
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    for (final teacher in filtered) ...[
                      _TeacherDirectoryCard(
                        teacher: teacher,
                        isResetting: _isResetting,
                        onResetPassword: () => _resetTeacherPassword(teacher),
                        onDelete: () => _deleteTeacher(teacher),
                        onEdit: () => _editTeacher(teacher),
                        onManageClasses: () => _manageTeacherClasses(teacher),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TeacherDirectoryCard extends StatelessWidget {
  const _TeacherDirectoryCard({
    required this.teacher,
    required this.isResetting,
    required this.onResetPassword,
    required this.onDelete,
    required this.onEdit,
    required this.onManageClasses,
  });

  final Map<String, dynamic> teacher;
  final bool isResetting;
  final VoidCallback onResetPassword;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onManageClasses;

  @override
  Widget build(BuildContext context) {
    final name = teacher['full_name'] as String? ?? 'Teacher';
    final username = teacher['username'] as String? ?? '';
    final status = teacher['approval_status'] as String? ?? 'approved';
    final isApproved = status == 'approved';
    final isAttendanceTeacher = teacher['is_attendance_teacher'] == true;
    final attendanceClass = teacher['attendance_class'] as String? ?? '';
    final subject = teacher['assigned_subject'] as String? ?? teacher['requested_subject'] as String? ?? '';
    final teachingClasses = (teacher['teaching_classes'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.co_present_rounded, color: Color(0xFF10B981), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (isApproved ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isApproved ? 'Approved' : 'Pending Review',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isApproved ? const Color(0xFF059669) : const Color(0xFFD97706),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        username,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (subject.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Subject: $subject',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                              ),
                            ),
                          if (isAttendanceTeacher)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star_rounded, size: 12, color: Color(0xFF059669)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Homeroom Master: Class $attendanceClass',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF047857),
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
              ],
            ),
            const SizedBox(height: 12),

            // Teaching Classes & Multi-Class Allocations display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Assigned Teaching Classes',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
                      ),
                      InkWell(
                        onTap: onManageClasses,
                        child: const Row(
                          children: [
                            Icon(Icons.edit_calendar_rounded, size: 12, color: Color(0xFF059669)),
                            SizedBox(width: 4),
                            Text(
                              'Assign / Edit Classes',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (teachingClasses.isEmpty)
                    const Text(
                      'No teaching classes assigned yet. Tap "Assign / Edit Classes" to allocate.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontStyle: FontStyle.italic),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final tc in teachingClasses) ...[
                          Builder(
                            builder: (context) {
                              final sMap = tc['sections'] as Map<String, dynamic>?;
                              final grade = sMap?['grade']?.toString() ?? '';
                              final name = sMap?['name']?.toString() ?? '';
                              final sub = tc['subject']?.toString() ?? '';
                              final label = name.isNotEmpty
                                  ? (name.length > 1 ? name : '$grade Class $name')
                                  : 'Class';

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  '$sub · $label',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF047857),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Action Buttons
            Row(
              children: [
                AnimatedPressButton(
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: isResetting ? null : onResetPassword,
                    icon: const Icon(Icons.lock_reset_rounded, size: 16),
                    label: const Text('Reset Password', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedPressButton(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: onManageClasses,
                    icon: const Icon(Icons.class_outlined, size: 16),
                    label: const Text('Classes', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const Spacer(),
                AnimatedPressButton(
                  child: IconButton.outlined(
                    tooltip: 'Edit faculty profile',
                    style: IconButton.styleFrom(
                      foregroundColor: const Color(0xFF10B981),
                      side: const BorderSide(color: Color(0xFF6EE7B7)),
                      minimumSize: const Size(36, 36),
                      padding: const EdgeInsets.all(6),
                    ),
                    onPressed: isResetting ? null : onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 17),
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedPressButton(
                  child: IconButton.outlined(
                    tooltip: 'Delete faculty account',
                    style: IconButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFFECACA)),
                      minimumSize: const Size(36, 36),
                      padding: const EdgeInsets.all(6),
                    ),
                    onPressed: isResetting ? null : onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 17),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
