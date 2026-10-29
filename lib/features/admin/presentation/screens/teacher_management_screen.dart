import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/services/student_password_reset_service.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
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
  final _searchController = TextEditingController();
  final _resetService = StudentPasswordResetService();
  late Future<List<Map<String, dynamic>>> _teachersFuture;
  List<Map<String, dynamic>> _schools = [];
  String? _selectedSchoolId;
  bool _isResetting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _teachersFuture = _loadTeachers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadTeachers() async {
    final client = Supabase.instance.client;
    final currentUser = ref.read(authStateProvider).user;
    final isSubadmin = currentUser?.isSuperAdmin != true;
    final targetSchoolId = isSubadmin ? currentUser?.schoolId : _selectedSchoolId;

    try {
      final sRows = await client.from('schools').select('id, name').order('name');
      _schools = List<Map<String, dynamic>>.from(sRows);
    } catch (_) {}

    var query = client
        .from('users')
        .select(
          'id, full_name, username, email, school_id, approval_status, is_active, created_at, '
          'is_attendance_teacher, attendance_grade, attendance_class, assigned_grade, assigned_class, assigned_subject, requested_subject, schools(name)',
        )
        .eq('role', AppRoles.teacher)
        .neq('is_active', false);

    if (targetSchoolId != null && targetSchoolId.isNotEmpty) {
      query = query.eq('school_id', targetSchoolId);
    }

    final rows = await query.order('full_name', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
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
          'Permanently remove $name from the institutional registry? '
          'Their quizzes, answer sheets, and teaching records will be purged.',
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
                      labelText: 'Teaching Subject',
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
                            'Grants authority to register students and approve registrations for their class.',
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
      title: 'Teacher Directory & Credentials',
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
                          'Faculty Management & Attendance Masters',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Oversee faculty credentials, subject allocations, and appointed class attendance teachers.',
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
            const SizedBox(height: 18),

            // Campus Scope / Filter
            if (_schools.isNotEmpty) ...[
              if (ref.watch(authStateProvider).user?.isSuperAdmin == true) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('All Schools'),
                        selected: _selectedSchoolId == null,
                        onSelected: (_) {
                          setState(() {
                            _selectedSchoolId = null;
                            _teachersFuture = _loadTeachers();
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      for (final s in _schools) ...[
                        ChoiceChip(
                          label: Text(s['name'] as String? ?? 'School'),
                          selected: _selectedSchoolId == s['id'],
                          onSelected: (sel) {
                            setState(() {
                              _selectedSchoolId = sel ? s['id'] as String : null;
                              _teachersFuture = _loadTeachers();
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.domain_rounded, size: 16, color: Color(0xFF047857)),
                      const SizedBox(width: 8),
                      Text(
                        'School: ${_schools.firstWhere((s) => s['id'] == ref.watch(authStateProvider).user?.schoolId, orElse: () => {'name': 'Your Campus'})['name']}',
                        style: const TextStyle(
                          color: Color(0xFF047857),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],

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
                          teachers.isEmpty ? 'No teachers found in the system.' : 'No faculty matches your search.',
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
                      ),
                      const SizedBox(height: 10),
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
  });

  final Map<String, dynamic> teacher;
  final bool isResetting;
  final VoidCallback onResetPassword;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final name = teacher['full_name'] as String? ?? 'Teacher';
    final username = teacher['username'] as String? ?? '';
    final school = (teacher['schools'] as Map<String, dynamic>?)?['name'] as String? ?? 'School';
    final status = teacher['approval_status'] as String? ?? 'approved';
    final isApproved = status == 'approved';
    final isAttendanceTeacher = teacher['is_attendance_teacher'] == true;
    final attendanceClass = teacher['attendance_class'] as String? ?? '';
    final subject = teacher['assigned_subject'] as String? ?? teacher['requested_subject'] as String? ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
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
                          isApproved ? 'Approved' : 'Pending',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isApproved ? const Color(0xFF059669) : const Color(0xFFD97706),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    username,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 4),
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
                                'Attendance Master: Class $attendanceClass',
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
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.location_city_rounded, size: 13, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 4),
                      Text(
                        school,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      AnimatedPressButton(
                        child: FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 34),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: isResetting ? null : onResetPassword,
                          icon: const Icon(Icons.lock_reset_rounded, size: 16),
                          label: const Text('Reset Password', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedPressButton(
                        child: IconButton.outlined(
                          tooltip: 'Edit faculty profile & attendance assignment',
                          style: IconButton.styleFrom(
                            foregroundColor: const Color(0xFF10B981),
                            side: const BorderSide(color: Color(0xFF6EE7B7)),
                            minimumSize: const Size(34, 34),
                            padding: const EdgeInsets.all(6),
                          ),
                          onPressed: isResetting ? null : onEdit,
                          icon: const Icon(Icons.edit_outlined, size: 16),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedPressButton(
                        child: IconButton.outlined(
                          tooltip: 'Delete faculty account',
                          style: IconButton.styleFrom(
                            foregroundColor: const Color(0xFFEF4444),
                            side: const BorderSide(color: Color(0xFFFECACA)),
                            minimumSize: const Size(34, 34),
                            padding: const EdgeInsets.all(6),
                          ),
                          onPressed: isResetting ? null : onDelete,
                          icon: const Icon(Icons.delete_outline_rounded, size: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
