import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/services/audit_log_service.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class AccountApprovalsScreen extends ConsumerStatefulWidget {
  const AccountApprovalsScreen({super.key});

  @override
  ConsumerState<AccountApprovalsScreen> createState() =>
      _AccountApprovalsScreenState();
}

class _AccountApprovalsScreenState extends ConsumerState<AccountApprovalsScreen> {
  late Future<List<Map<String, dynamic>>> _requests;
  final Set<String> _working = {};
  String? _error;

  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _requests = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('users')
          .select(
            'id, username, email, full_name, role, requested_role, school_id, section_id, '
            'requested_grade, requested_class, requested_subject, assigned_class, assigned_grade, created_at',
          )
          .eq('approval_status', 'pending')
          .order('created_at');
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      try {
        final fallbackRows = await Supabase.instance.client
            .from('users')
            .select(
              'id, username, email, full_name, role, requested_role, created_at',
            )
            .eq('approval_status', 'pending')
            .order('created_at');
        return List<Map<String, dynamic>>.from(fallbackRows);
      } catch (_) {
        rethrow;
      }
    }
  }

  Future<void> _review(Map<String, dynamic> request, String decision) async {
    final id = request['id'] as String;
    final requestedRole = (request['requested_role'] as String?)?.isNotEmpty == true
        ? request['requested_role'] as String
        : (request['role'] as String? ?? 'student');
    String? schoolId = request['school_id'] as String?;
    if (decision == 'approve' && requestedRole == 'teacher' && schoolId == null) {
      schoolId = await _askForSchoolId();
      if (schoolId == null) return;
    }

    setState(() {
      _working.add(id);
      _error = null;
    });
    try {
      bool reviewed = false;

      // 1. Try dedicated database RPC function (security definer, bypasses restrictive RLS)
      try {
        await Supabase.instance.client.rpc(
          'review_user_registration',
          params: {
            'p_user_id': id,
            'p_decision': decision,
            'p_school_id': schoolId,
          },
        );
        reviewed = true;
      } catch (rpcErr) {
        debugPrint('review_user_registration p_ RPC note: $rpcErr');
        try {
          await Supabase.instance.client.rpc(
            'review_user_registration',
            params: {
              'user_id': id,
              'decision': decision,
              'school_id': schoolId,
            },
          );
          reviewed = true;
        } catch (rpcErr2) {
          debugPrint('review_user_registration fallback RPC note: $rpcErr2');
        }
      }

      // 2. Try Edge Function if RPC was not defined
      if (!reviewed) {
        try {
          await Supabase.instance.client.functions.invoke(
            'review-account',
            body: {'userId': id, 'decision': decision, 'schoolId': schoolId},
          );
          reviewed = true;
        } catch (fnErr) {
          debugPrint('review-account edge function fallback note: $fnErr');
        }
      }

      // 3. Fallback: direct users table update
      if (!reviewed) {
        final isApprove = decision == 'approve';
        final updateMap = <String, dynamic>{
          'approval_status': isApprove ? 'approved' : 'rejected',
          'is_active': isApprove,
          'role': isApprove ? requestedRole : 'student',
        };
        if (isApprove && schoolId != null) {
          updateMap['school_id'] = schoolId;
        }
        await Supabase.instance.client
            .from('users')
            .update(updateMap)
            .eq('id', id);

        // Auto-enroll student into section if requested
        if (isApprove && requestedRole == 'student') {
          final sectionId = request['section_id'] as String?;
          if (sectionId != null) {
            try {
              await Supabase.instance.client.from('student_sections').upsert({
                'student_id': id,
                'section_id': sectionId,
              });
            } catch (_) {}
          }
        }
      }

      // Record audit activity
      try {
        await AuditLogService().logForCurrentUser(
          action: decision == 'approve' ? 'account_approved' : 'account_rejected',
          targetUser: request['username'] as String? ?? id,
          details: {
            'role': requestedRole,
            'full_name': request['full_name'],
            'decision': decision,
          },
        );
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              decision == 'approve'
                  ? 'Account for ${request['full_name'] ?? request['username']} approved successfully!'
                  : 'Account for ${request['full_name'] ?? request['username']} was declined.',
            ),
            backgroundColor: decision == 'approve' ? const Color(0xFF10B981) : Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _requests = _load());
      }
    } catch (error) {
      if (mounted) {
        final errStr = error.toString();
        setState(() {
          _error = errStr.contains('Permission denied')
              ? 'Permission denied: Only Administrators or the assigned Attendance Teacher for this class can approve this request.'
              : 'Could not process review request: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _working.remove(id));
      }
    }
  }

  Future<String?> _askForSchoolId() async {
    final client = Supabase.instance.client;
    final rows = await client.from('schools').select('id, name');
    final schools = List<Map<String, dynamic>>.from(rows);
    if (schools.isEmpty || !mounted) return null;
    String? selected = schools.first['id'] as String;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Assign School'),
          content: DropdownButtonFormField<String>(
            initialValue: selected,
            decoration: const InputDecoration(labelText: 'School'),
            items: [
              for (final s in schools)
                DropdownMenuItem(
                  value: s['id'] as String,
                  child: Text(s['name'] as String? ?? 'School'),
                ),
            ],
            onChanged: (v) => setDialogState(() => selected = v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authStateProvider).user;
    final isAttendanceTeacher = currentUser?.isAttendanceTeacher == true;
    final attendanceClass = currentUser?.attendanceClass;

    return DashboardShell(
      title: 'Pending Account Approvals',
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _requests,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Could not load requests: ${snapshot.error}'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => setState(() => _requests = _load()),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final allRequests = snapshot.data!;
          final requests = allRequests.where((r) {
            final targetRole = (r['requested_role'] ?? r['role'] ?? 'student');
            final reqClass = (r['requested_class'] ?? r['assigned_class'] ?? '').toString().trim();

            if (isAttendanceTeacher && !AppRoles.isAdmin(currentUser?.role)) {
              // Attendance teachers only review students for their assigned class (e.g. 9A)
              if (targetRole != 'student') return false;
              if (attendanceClass != null && attendanceClass.isNotEmpty) {
                return reqClass.toLowerCase() == attendanceClass.toLowerCase();
              }
            }

            if (_filter == 'student') {
              return targetRole == 'student';
            }
            if (_filter == 'teacher') {
              return targetRole == 'teacher';
            }
            if (_filter == 'my_class' && attendanceClass != null) {
              return reqClass.toLowerCase() == attendanceClass.toLowerCase();
            }
            return true;
          }).toList();

          return RefreshIndicator(
            onRefresh: () async => setState(() => _requests = _load()),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // Top Header Banner
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Review Registration Requests',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${allRequests.length} account registration${allRequests.length == 1 ? '' : 's'} awaiting approval',
                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Attendance Teacher Notice Banner
                if (isAttendanceTeacher) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.how_to_reg_rounded, color: Color(0xFF047857), size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Attendance Master View: Class ${attendanceClass ?? '9A'}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                  color: Color(0xFF065F46),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'You are authorized to review and approve registrations for students joining Class ${attendanceClass ?? '9A'}.',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF047857)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Filter Segmented Buttons (for Admins & Sub-admins)
                if (AppRoles.isAdmin(currentUser?.role))
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'all',
                        label: Text('All (${allRequests.length})'),
                        icon: const Icon(Icons.people_outline, size: 16),
                      ),
                      ButtonSegment(
                        value: 'student',
                        label: Text('Students (${allRequests.where((r) => (r['requested_role'] ?? r['role']) == 'student').length})'),
                        icon: const Icon(Icons.school_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: 'teacher',
                        label: Text('Teachers (${allRequests.where((r) => (r['requested_role'] ?? r['role']) == 'teacher').length})'),
                        icon: const Icon(Icons.co_present_outlined, size: 16),
                      ),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (selected) {
                      setState(() => _filter = selected.first);
                    },
                  ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (requests.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          children: [
                            const Icon(
                              Icons.check_circle_outline_rounded,
                              size: 48,
                              color: Color(0xFF10B981),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'All caught up!',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isAttendanceTeacher
                                  ? 'No pending registrations for Class ${attendanceClass ?? 'your class'}.'
                                  : (_filter == 'all'
                                      ? 'No pending registration requests.'
                                      : 'No pending $_filter registration requests.'),
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  ...requests.map((request) {
                    final id = request['id'] as String;
                    final isBusy = _working.contains(id);
                    final role = request['requested_role'] ?? request['role'] ?? 'student';
                    final fullName = request['full_name'] as String? ?? 'New User';
                    final username = request['username'] as String? ?? '';
                    final grade = request['requested_grade'] as String? ?? request['assigned_grade'] as String? ?? '';
                    final className = request['requested_class'] as String? ?? request['assigned_class'] as String? ?? '';
                    final subject = request['requested_subject'] as String? ?? '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: role == 'teacher'
                                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                      : const Color(0xFF3B82F6).withValues(alpha: 0.15),
                                  child: Icon(
                                    role == 'teacher'
                                        ? Icons.co_present_rounded
                                        : Icons.school_rounded,
                                    color: role == 'teacher'
                                        ? const Color(0xFF059669)
                                        : const Color(0xFF2563EB),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        fullName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        username,
                                        style: const TextStyle(
                                          color: Color(0xFF64748B),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: role == 'teacher'
                                        ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                        : const Color(0xFF3B82F6).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    role == 'teacher' ? 'Teacher' : 'Student',
                                    style: TextStyle(
                                      color: role == 'teacher'
                                          ? const Color(0xFF047857)
                                          : const Color(0xFF1D4ED8),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                if (className.isNotEmpty)
                                  Chip(
                                    avatar: const Icon(Icons.meeting_room_outlined, size: 14),
                                    label: Text('Class: $className'),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                if (grade.isNotEmpty)
                                  Chip(
                                    avatar: const Icon(Icons.grade_outlined, size: 14),
                                    label: Text(grade),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                if (subject.isNotEmpty)
                                  Chip(
                                    avatar: const Icon(Icons.menu_book_outlined, size: 14),
                                    label: Text('Subject: $subject'),
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Color(0xFFFECACA)),
                                  ),
                                  onPressed: isBusy
                                      ? null
                                      : () => _review(request, 'reject'),
                                  child: const Text('Decline'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                  ),
                                  onPressed: isBusy
                                      ? null
                                      : () => _review(request, 'approve'),
                                  icon: isBusy
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.check_circle_outline, size: 18),
                                  label: const Text('Approve Account'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }
}
