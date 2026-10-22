import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
            'id, username, email, full_name, requested_role, requested_grade, requested_class, requested_subject, created_at',
          )
          .eq('approval_status', 'pending')
          .order('created_at');
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      if (e is PostgrestException && e.code == '42703') {
        // Resilient fallback if requested_class/requested_grade/requested_subject columns are not yet in the DB
        final fallbackRows = await Supabase.instance.client
            .from('users')
            .select(
              'id, username, email, full_name, requested_role, created_at',
            )
            .eq('approval_status', 'pending')
            .order('created_at');
        return List<Map<String, dynamic>>.from(fallbackRows);
      }
      rethrow;
    }
  }

  Future<void> _review(Map<String, dynamic> request, String decision) async {
    final id = request['id'] as String;
    final requestedRole = request['requested_role'] as String? ?? 'teacher';
    String? schoolId;
    if (decision == 'approve' && requestedRole == 'teacher') {
      schoolId = await _askForSchoolId();
      if (schoolId == null) return;
    }

    setState(() {
      _working.add(id);
      _error = null;
    });
    try {
      await Supabase.instance.client.functions.invoke(
        'review-account',
        body: {'userId': id, 'decision': decision, 'schoolId': schoolId},
      );
      if (mounted) setState(() => _requests = _load());
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not review this request: $error');
      }
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
      title: 'Role requests',
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
          final requests = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => setState(() => _requests = _load()),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Review access requests',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'New accounts stay in student mode until you approve an elevated role.',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (requests.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('You’re all caught up. No pending requests.'),
                    ),
                  ),
                for (final request in requests)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              child: Icon(
                                request['requested_role'] == 'admin'
                                    ? Icons.admin_panel_settings_outlined
                                    : Icons.school_outlined,
                              ),
                            ),
                            title: Text(
                              request['full_name'] as String? ??
                                  request['username'] as String? ??
                                  'New user',
                            ),
                            subtitle: Text(
                              '${request['email'] ?? ''}\n'
                              'Requested: ${request['requested_role']}'
                              '${request['requested_grade'] == null ? '' : '\nGrade: ${request['requested_grade']}'}'
                              '${request['requested_class'] == null ? '' : '\nClass: ${request['requested_class']}'}'
                              '${request['requested_subject'] == null ? '' : '\nSubject: ${request['requested_subject']}'}',
                            ),
                            isThreeLine:
                                request['requested_grade'] != null ||
                                request['requested_class'] != null ||
                                request['requested_subject'] != null,
                          ),
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: _working.contains(request['id'])
                                    ? null
                                    : () => _review(request, 'reject'),
                                child: const Text('Decline'),
                              ),
                              FilledButton.icon(
                                onPressed: _working.contains(request['id'])
                                    ? null
                                    : () => _review(request, 'approve'),
                                icon: const Icon(Icons.verified_outlined),
                                label: const Text('Approve'),
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
