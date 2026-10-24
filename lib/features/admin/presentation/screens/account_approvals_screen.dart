import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/services/audit_log_service.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class AccountApprovalsScreen extends StatefulWidget {
  const AccountApprovalsScreen({super.key});

  @override
  State<AccountApprovalsScreen> createState() => _AccountApprovalsScreenState();
}

class _AccountApprovalsScreenState extends State<AccountApprovalsScreen> {
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
            'id, username, email, full_name, role, requested_role, school_id, section_id, requested_grade, requested_class, requested_subject, created_at',
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
            'p_school_id':? schoolId,
          },
        );
        reviewed = true;
      } catch (rpcErr) {
        debugPrint('review_user_registration RPC note: $rpcErr');
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
        if (errStr.contains('permission denied')) {
          setState(() => _error =
              'Database permission denied: Please apply migration 20261024000000 in Supabase SQL editor to grant administrator update permissions on table users.');
        } else {
          setState(() => _error = 'Could not review this request: $error');
        }
      }
    } finally {
      if (mounted) setState(() => _working.remove(id));
    }
  }

  Future<void> _deleteRequest(Map<String, dynamic> request) async {
    final id = request['id'] as String;
    final name = request['full_name'] as String? ??
        request['username'] as String? ??
        'this user';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Request?'),
          ],
        ),
        content: Text(
          'Permanently remove registration request for $name? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _working.add(id));
    try {
      bool deleted = false;
      try {
        await Supabase.instance.client.rpc(
          'delete_user_account',
          params: {'user_id': id, 'p_user_id': id},
        );
        deleted = true;
      } catch (_) {}

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
        final client = Supabase.instance.client;
        try {
          await client.from('student_sections').delete().eq('student_id', id);
        } catch (_) {}
        try {
          await client.from('answers').delete().eq('student_id', id);
        } catch (_) {}
        try {
          await client.from('grades').delete().eq('student_id', id);
        } catch (_) {}
        try {
          await client.from('quiz_attempts').delete().eq('student_id', id);
        } catch (_) {}
        try {
          await client.from('users').delete().eq('id', id);
        } catch (_) {
          await client.from('users').update({
            'is_active': false,
            'approval_status': 'rejected',
          }).eq('id', id);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Registration request for $name deleted successfully.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _requests = _load());
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not delete request: $e');
    } finally {
      if (mounted) setState(() => _working.remove(id));
    }
  }

  Future<String?> _askForSchoolId() async {
    final schools = Supabase.instance.client
        .from('schools')
        .select('id, name')
        .order('name');
    String? selectedSchoolId;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Assign a school'),
          content: FutureBuilder(
            future: schools,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('Could not load schools: ${snapshot.error}');
              }
              if (!snapshot.hasData) {
                return const SizedBox(
                  height: 72,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final entries = List<Map<String, dynamic>>.from(snapshot.data!);
              if (entries.isEmpty) {
                return const Text('No schools are available.');
              }
              return DropdownButtonFormField<String>(
                initialValue: selectedSchoolId,
                decoration: const InputDecoration(labelText: 'School'),
                items: [
                  for (final school in entries)
                    DropdownMenuItem<String>(
                      value: school['id'] as String,
                      child: Text(school['name'] as String? ?? 'School'),
                    ),
                ],
                onChanged: (value) =>
                    setDialogState(() => selectedSchoolId = value),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selectedSchoolId == null
                  ? null
                  : () => Navigator.pop(context, selectedSchoolId),
              child: const Text('Approve teacher'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return null;
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return DashboardShell(
      title: 'Registration Approvals',
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
            if (_filter == 'student') {
              return (r['requested_role'] ?? r['role']) == 'student';
            }
            if (_filter == 'teacher') {
              return (r['requested_role'] ?? r['role']) == 'teacher';
            }
            return true;
          }).toList();

          return RefreshIndicator(
            onRefresh: () async => setState(() => _requests = _load()),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
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

                // Filter Segmented Buttons
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
                              _filter == 'all'
                                  ? 'No pending registration requests.'
                                  : 'No pending $_filter registration requests.',
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                for (final request in requests)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: const Color(0xFFECFDF5),
                                child: Icon(
                                  (request['requested_role'] ?? request['role']) == 'teacher'
                                      ? Icons.co_present_rounded
                                      : Icons.school_rounded,
                                  color: const Color(0xFF10B981),
                                  size: 24,
                                ),
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
                                            request['full_name'] as String? ??
                                                request['username'] as String? ??
                                                'New user',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: (request['requested_role'] ?? request['role']) == 'teacher'
                                                ? const Color(0xFFEFF6FF)
                                                : const Color(0xFFECFDF5),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: (request['requested_role'] ?? request['role']) == 'teacher'
                                                  ? const Color(0xFFBFDBFE)
                                                  : const Color(0xFFA7F3D0),
                                            ),
                                          ),
                                          child: Text(
                                            ((request['requested_role'] ?? request['role']) as String? ?? 'student').toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: (request['requested_role'] ?? request['role']) == 'teacher'
                                                  ? const Color(0xFF1D4ED8)
                                                  : const Color(0xFF047857),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Username: ${request['username'] ?? '—'}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF047857),
                                      ),
                                    ),
                                    if (request['email'] != null && request['email'] != request['username'])
                                      Text(
                                        'Email: ${request['email']}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    if (request['requested_grade'] != null ||
                                        request['requested_class'] != null ||
                                        request['requested_subject'] != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          [
                                            if (request['requested_grade'] != null)
                                              'Grade: ${request['requested_grade']}',
                                            if (request['requested_class'] != null)
                                              'Class: ${request['requested_class']}',
                                            if (request['requested_subject'] != null)
                                              'Subject: ${request['requested_subject']}',
                                          ].join(' • '),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF475569),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Delete request permanently',
                                onPressed: _working.contains(request['id'])
                                    ? null
                                    : () => _deleteRequest(request),
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Color(0xFFDC2626),
                                  size: 20,
                                ),
                              ),
                              const Spacer(),
                              OutlinedButton(
                                onPressed: _working.contains(request['id'])
                                    ? null
                                    : () => _review(request, 'reject'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFDC2626),
                                  side: const BorderSide(
                                    color: Color(0xFFFCA5A5),
                                  ),
                                ),
                                child: const Text('Decline'),
                              ),
                              const SizedBox(width: 10),
                              FilledButton.icon(
                                onPressed: _working.contains(request['id'])
                                    ? null
                                    : () => _review(request, 'approve'),
                                icon: const Icon(
                                  Icons.check_circle_outline,
                                  size: 16,
                                ),
                                label: const Text('Approve Account'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
