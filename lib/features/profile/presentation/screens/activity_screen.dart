import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quiz_app/core/services/audit_log_service.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/shared/models/audit_log.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return DashboardShell(
      title: 'Activity',
      body: _ActivityList(userId: user.id, role: user.role),
    );
  }
}

class _ActivityList extends StatefulWidget {
  const _ActivityList({required this.userId, required this.role});

  final String userId;
  final String role;

  @override
  State<_ActivityList> createState() => _ActivityListState();
}

class _ActivityListState extends State<_ActivityList> {
  final _auditLogService = AuditLogService();
  late Future<List<AuditLog>> _activities;

  @override
  void initState() {
    super.initState();
    _activities = _load();
  }

  Future<List<AuditLog>> _load() => _auditLogService.fetchLogs(limit: 200);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AuditLog>>(
      future: _activities,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load activity: ${snapshot.error}'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async {
            final future = _load();
            setState(() {
              _activities = future;
            });
            await future;
          },
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.role == 'student'
                    ? 'Your account activity'
                    : 'Recent account activity',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                widget.role == 'student'
                    ? 'A history of actions involving your account.'
                    : 'Activity from administrators, teachers, and students.',
              ),
              const SizedBox(height: 20),
              if (items.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nothing here yet. Your activity will appear here.',
                    ),
                  ),
                ),
              for (final item in items)
                Card(
                  child: ListTile(
                    leading: Icon(_iconFor(item.action)),
                    title: Text(_titleFor(item)),
                    subtitle: Text(_subtitleFor(item)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  IconData _iconFor(String action) {
    if (action.contains('quiz')) return Icons.quiz_outlined;
    if (action.contains('password')) return Icons.lock_outline;
    if (action.contains('profile')) return Icons.account_circle_outlined;
    if (action.contains('account') || action.contains('user')) {
      return Icons.manage_accounts_outlined;
    }
    return Icons.history;
  }

  String _titleFor(AuditLog item) {
    final labels = {
      'user_signed_in': 'Signed in',
      'profile_updated': 'Profile updated',
      'profile_photo_updated': 'Profile photo changed',
      'password_changed': 'Password changed',
      'account_created': 'Account created',
      'account_deleted': 'Account deleted',
      'account_updated': 'Account updated',
      'password_reset': 'Password reset',
      'account_approved': 'Account approved',
      'account_rejected': 'Account request rejected',
      'quiz_created': 'Quiz created',
      'quiz_published': 'Quiz published',
      'quiz_unpublished': 'Quiz unpublished',
      'quiz_updated': 'Quiz updated',
      'quiz_deleted': 'Quiz deleted',
      'quiz_started': 'Quiz started',
      'quiz_submitted': 'Quiz submitted',
    };
    return labels[item.action] ??
        item.action
            .replaceAll('_', ' ')
            .replaceFirstMapped(
              RegExp(r'^[a-z]'),
              (match) => match.group(0)!.toUpperCase(),
            );
  }

  String _subtitleFor(AuditLog item) {
    final details = item.details ?? const <String, dynamic>{};
    final actor =
        details['actor_name'] as String? ??
        (item.performedBy == widget.userId
            ? 'You'
            : item.performedBy ?? 'System');
    final target =
        details['target_name'] as String? ?? details['quiz_title'] as String?;
    final percentage = details['percentage']?.toString();
    final date = item.createdAt.toLocal().toString();
    final timestamp = date.length >= 16 ? date.substring(0, 16) : date;
    return [
      if (target != null && target.isNotEmpty) target,
      if (percentage != null) 'Score: $percentage%',
      'By $actor · $timestamp',
    ].join(' · ');
  }
}
