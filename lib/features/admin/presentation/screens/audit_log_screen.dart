import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quiz_app/core/services/audit_log_service.dart';
import 'package:quiz_app/shared/models/audit_log.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  final _auditService = AuditLogService();
  final _searchController = TextEditingController();
  List<AuditLog> _logs = [];
  bool _loading = true;
  String? _error;
  String _selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final logs = await _auditService.fetchLogs(limit: 250);
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<AuditLog> get _filteredLogs {
    final query = _searchController.text.trim().toLowerCase();
    return _logs.where((log) {
      // Category filter
      if (_selectedFilter == 'accounts') {
        if (!log.action.contains('account') && !log.action.contains('user')) {
          return false;
        }
      } else if (_selectedFilter == 'passwords') {
        if (!log.action.contains('password')) return false;
      } else if (_selectedFilter == 'quizzes') {
        if (!log.action.contains('quiz')) return false;
      } else if (_selectedFilter == 'security') {
        if (!log.action.contains('suspicious') &&
            !log.action.contains('screenshot') &&
            !log.action.contains('record')) {
          return false;
        }
      }

      // Search query
      if (query.isNotEmpty) {
        final action = log.action.toLowerCase();
        final actor = log.details?['actor_name']?.toString().toLowerCase() ?? '';
        final target = log.targetUser?.toLowerCase() ?? '';
        final detailsStr = log.details?.toString().toLowerCase() ?? '';
        return action.contains(query) ||
            actor.contains(query) ||
            target.contains(query) ||
            detailsStr.contains(query);
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DashboardShell(
      title: 'System Activity & Audit Logs',
      body: RefreshIndicator(
        onRefresh: _loadLogs,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Header summary card (White aesthetic)
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
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      color: Color(0xFF0F172A),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Audit Surveillance',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Live chronological log of user management, password resets, and exam activity.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Refresh activities',
                    onPressed: _loading ? null : _loadLogs,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Search bar
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search by actor, action, or metadata...',
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
            ),
            const SizedBox(height: 12),

            // Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final item in const [
                    (id: 'all', label: 'All Activities', icon: Icons.all_inclusive_rounded),
                    (id: 'accounts', label: 'Accounts', icon: Icons.manage_accounts_rounded),
                    (id: 'passwords', label: 'Passwords', icon: Icons.lock_reset_rounded),
                    (id: 'quizzes', label: 'Quizzes', icon: Icons.quiz_rounded),
                    (id: 'security', label: 'Security', icon: Icons.shield_rounded),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        avatar: Icon(item.icon, size: 16),
                        label: Text(item.label),
                        selected: _selectedFilter == item.id,
                        onSelected: (selected) {
                          if (!selected) return;
                          setState(() => _selectedFilter = item.id);
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (_loading && _logs.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: theme.colorScheme.error),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Error loading audit logs: $_error')),
                      TextButton(
                        onPressed: _loadLogs,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_filteredLogs.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(36),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.search_off_rounded,
                        size: 48,
                        color: Color(0xFF94A3B8),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No matching system activities found',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Try clearing your search or choosing another filter.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              for (final log in _filteredLogs) ...[
                _AuditLogItemCard(log: log),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _AuditLogItemCard extends StatelessWidget {
  const _AuditLogItemCard({required this.log});

  final AuditLog log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final (badgeColor, badgeIcon, actionTitle) = _getActionMeta(log.action);
    final actorName = log.details?['actor_name'] as String? ??
        log.details?['actor_email'] as String? ??
        (log.performedBy != null && log.performedBy!.length > 8
            ? log.performedBy!.substring(0, 8)
            : log.performedBy ?? 'System');

    final timeStr = _formatTimestamp(log.createdAt);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(badgeIcon, color: badgeColor, size: 22),
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
                              actionTitle,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Text(
                            timeStr,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _TagPill(
                            label: 'Actor: $actorName',
                            icon: Icons.person_outline_rounded,
                            isDark: isDark,
                          ),
                          if (log.targetUser != null && log.targetUser!.isNotEmpty)
                            _TagPill(
                              label: 'Target: ${log.targetUser!.length > 8 ? log.targetUser!.substring(0, 8) : log.targetUser}',
                              icon: Icons.arrow_forward_rounded,
                              isDark: isDark,
                            ),
                          if (log.details?['role'] != null)
                            _TagPill(
                              label: 'Role: ${log.details!['role']}',
                              icon: Icons.badge_outlined,
                              isDark: isDark,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (log.details != null && log.details!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Text(
                  _formatDetails(log.details!),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: isDark
                        ? const Color(0xFFCBD5E1)
                        : const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  (Color, IconData, String) _getActionMeta(String action) {
    if (action.contains('account_created') || action.contains('registered')) {
      return (const Color(0xFF10B981), Icons.person_add_rounded, 'User Account Created');
    }
    if (action.contains('password_reset')) {
      return (const Color(0xFFF59E0B), Icons.lock_reset_rounded, 'Password Reset');
    }
    if (action.contains('password_changed')) {
      return (const Color(0xFF3B82F6), Icons.password_rounded, 'Password Changed');
    }
    if (action.contains('account_approved')) {
      return (const Color(0xFF10B981), Icons.verified_user_rounded, 'Account Approved');
    }
    if (action.contains('account_deleted')) {
      return (const Color(0xFFEF4444), Icons.delete_forever_rounded, 'Account Removed');
    }
    if (action.contains('quiz_created') || action.contains('quiz_published')) {
      return (const Color(0xFF8B5CF6), Icons.quiz_rounded, 'Quiz Created & Published');
    }
    if (action.contains('quiz_submitted')) {
      return (const Color(0xFF06B6D4), Icons.assignment_turned_in_rounded, 'Quiz Attempt Submitted');
    }
    if (action.contains('suspicious') || action.contains('screenshot')) {
      return (const Color(0xFFDC2626), Icons.warning_amber_rounded, 'Security Violation Flagged');
    }
    return (
      const Color(0xFF64748B),
      Icons.timeline_rounded,
      action
          .replaceAll('_', ' ')
          .replaceFirstMapped(RegExp(r'^[a-z]'), (m) => m.group(0)!.toUpperCase()),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  String _formatDetails(Map<String, dynamic> details) {
    final filtered = Map<String, dynamic>.from(details)
      ..remove('actor_name')
      ..remove('timestamp');
    if (filtered.isEmpty) return 'No extra parameters';
    return filtered.entries.map((e) => '${e.key}: ${e.value}').join('  •  ');
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({
    required this.label,
    required this.icon,
    required this.isDark,
  });

  final String label;
  final IconData icon;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }
}

