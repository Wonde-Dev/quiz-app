import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/services/announcement_service.dart';
import 'package:quiz_app/core/services/teacher_activity_service.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/shared/models/school_announcement.dart';
import 'package:quiz_app/shared/models/teacher_academic_activity.dart';
import 'package:quiz_app/shared/widgets/animated_press_button.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class DirectorDashboardScreen extends ConsumerStatefulWidget {
  const DirectorDashboardScreen({super.key});

  @override
  ConsumerState<DirectorDashboardScreen> createState() =>
      _DirectorDashboardScreenState();
}

class _DirectorDashboardScreenState extends ConsumerState<DirectorDashboardScreen>
    with SingleTickerProviderStateMixin {
  static const String _ciroSchoolId = '00000000-0000-4000-8000-000000000001';

  int _facultyTeacherCount = 0;
  int _activeTeacherCount = 0;
  int _pendingTeacherApprovals = 0;
  int _announcementsCount = 0;
  List<Map<String, dynamic>> _gradeStats = [];
  List<TeacherAcademicActivity> _teacherActivities = [];
  List<SchoolAnnouncement> _announcements = [];
  bool _loading = true;

  late final AnimationController _pulseController;
  RealtimeChannel? _realtimeChannel;
  RealtimeChannel? _announcementsChannel;

  final _announcementService = AnnouncementService();
  final _activityService = TeacherActivityService();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _loadDashboardData();
    _setupRealtime();
  }

  void _setupRealtime() {
    try {
      _realtimeChannel = Supabase.instance.client
          .channel('public:director_dashboard_users')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'users',
            callback: (_) {
              if (mounted) _loadDashboardData();
            },
          )
          .subscribe();

      _announcementsChannel = Supabase.instance.client
          .channel('public:director_announcements')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'school_announcements',
            callback: (_) {
              if (mounted) _loadDashboardData();
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Director realtime notice: $e');
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    if (_realtimeChannel != null) {
      Supabase.instance.client.removeChannel(_realtimeChannel!);
    }
    if (_announcementsChannel != null) {
      Supabase.instance.client.removeChannel(_announcementsChannel!);
    }
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _loading = true);
    final client = Supabase.instance.client;

    try {
      final results = await Future.wait<dynamic>([
        // 1. Get school stats via RPC
        client.rpc('get_school_user_stats', params: {
          'p_school_id': _ciroSchoolId,
        }),
        // 2. Fetch announcements
        _announcementService.fetchAnnouncements(schoolId: _ciroSchoolId, limit: 10),
        // 3. Fetch teacher academic activities
        _activityService.fetchActivities(schoolId: _ciroSchoolId, limit: 20),
        // 4. Fetch faculty teachers count breakdown
        client
            .from('users')
            .select('id, is_active, approval_status')
            .eq('role', AppRoles.teacher)
            .eq('school_id', _ciroSchoolId),
      ]);

      if (!mounted) return;

      final rpcRes = results[0];
      final announcements = results[1] as List<SchoolAnnouncement>;
      final activities = results[2] as List<TeacherAcademicActivity>;
      final teacherRows = results[3] as List;

      int totalTeachers = teacherRows.length;
      int activeTeachers = teacherRows.where((t) => t['is_active'] == true && t['approval_status'] == 'approved').length;
      int pendingApprovals = teacherRows.where((t) => t['approval_status'] == 'pending').length;

      List<Map<String, dynamic>> gradeStats = [];
      if (rpcRes is Map && rpcRes['grades'] != null) {
        gradeStats = List<Map<String, dynamic>>.from(rpcRes['grades'] as List);
      }

      setState(() {
        _facultyTeacherCount = totalTeachers;
        _activeTeacherCount = activeTeachers;
        _pendingTeacherApprovals = pendingApprovals;
        _announcementsCount = announcements.length;
        _announcements = announcements;
        _teacherActivities = activities;
        _gradeStats = gradeStats;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading director dashboard: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _showTransferPositionDialog() async {
    final client = Supabase.instance.client;
    final passwordController = TextEditingController();
    bool isSubmitting = false;
    bool obscurePassword = true;
    String? selectedTeacherId;
    String? selectedTeacherName;
    String? errorText;

    // Load active faculty teachers eligible for promotion
    List<Map<String, dynamic>> eligibleTeachers = [];
    try {
      final rows = await client
          .from('users')
          .select('id, full_name, username, email, assigned_subject')
          .eq('role', AppRoles.teacher)
          .eq('is_active', true)
          .eq('approval_status', 'approved')
          .order('full_name');
      eligibleTeachers = List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('Error loading teachers for director transfer: $e');
    }

    if (!mounted) return;

    if (eligibleTeachers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No eligible active faculty teachers available for position transfer.'),
          backgroundColor: Color(0xFFD97706),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF6366F1), size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Transfer Director Position',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Position Transfer Protocol: By transferring your School Director position, your account will transition to Faculty Teacher, and the selected teacher will assume the role of School Director.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF92400E), height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Select Successor Faculty Teacher *',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedTeacherId,
                          hint: const Text('Choose eligible faculty teacher...'),
                          isExpanded: true,
                          items: eligibleTeachers.map((teacher) {
                            final name = (teacher['full_name'] as String?)?.trim().isNotEmpty == true
                                ? teacher['full_name'] as String
                                : teacher['username'] as String;
                            final subj = teacher['assigned_subject'] as String? ?? 'General';
                            return DropdownMenuItem<String>(
                              value: teacher['id'] as String,
                              child: Text('$name ($subj)'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setDialogState(() {
                              selectedTeacherId = val;
                              final match = eligibleTeachers.firstWhere((t) => t['id'] == val);
                              selectedTeacherName = match['full_name'] as String? ?? match['username'] as String?;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Confirm Your Current Password *',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        hintText: 'Enter your password to authorize',
                        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                          onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                errorText!,
                                style: const TextStyle(color: Colors.red, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: (isSubmitting || selectedTeacherId == null)
                    ? null
                    : () async {
                        final pass = passwordController.text.trim();
                        if (pass.isEmpty) {
                          setDialogState(() => errorText = 'Password confirmation is required.');
                          return;
                        }

                        setDialogState(() {
                          isSubmitting = true;
                          errorText = null;
                        });

                        try {
                          final res = await _activityService.transferDirectorPosition(
                            targetTeacherId: selectedTeacherId!,
                            currentPassword: pass,
                          );

                          if (dialogCtx.mounted) {
                            Navigator.pop(dialogCtx);
                          }

                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(res['message']?.toString() ??
                                  'Director position transferred to $selectedTeacherName!'),
                              backgroundColor: const Color(0xFF10B981),
                            ),
                          );

                          // Reload state & router
                          await ref.read(authStateProvider.notifier).refreshCurrentUser();
                          if (mounted) context.go('/teacher/dashboard');
                        } catch (e) {
                          setDialogState(() {
                            isSubmitting = false;
                            errorText = e.toString().replaceAll('Exception:', '').trim();
                          });
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Confirm Transfer'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAnnouncementDialog({SchoolAnnouncement? announcement}) async {
    final titleController = TextEditingController(text: announcement?.title ?? '');
    final contentController = TextEditingController(text: announcement?.content ?? '');
    String targetAudience = announcement?.targetAudience ?? 'all';
    bool isPinned = announcement?.isPinned ?? false;
    bool isSubmitting = false;
    String? errorText;

    final currentUser = ref.read(authStateProvider).user;
    final authorName = currentUser?.fullName?.isNotEmpty == true
        ? currentUser!.fullName!
        : (currentUser?.username ?? 'School Director');

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(
                  announcement == null ? Icons.campaign_rounded : Icons.edit_note_rounded,
                  color: const Color(0xFF10B981),
                ),
                const SizedBox(width: 10),
                Text(
                  announcement == null ? 'Post School Announcement' : 'Edit Announcement',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        labelText: 'Announcement Title *',
                        hintText: 'e.g. End of Semester Faculty Meeting',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: contentController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Announcement Body *',
                        hintText: 'Enter complete announcement message...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: targetAudience,
                      decoration: InputDecoration(
                        labelText: 'Audience',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('Entire School')),
                        DropdownMenuItem(value: 'teachers', child: Text('Faculty Only')),
                        DropdownMenuItem(value: 'students', child: Text('Students Only')),
                        DropdownMenuItem(value: 'Grade 9', child: Text('Grade 9 Students')),
                        DropdownMenuItem(value: 'Grade 10', child: Text('Grade 10 Students')),
                        DropdownMenuItem(value: 'Grade 11', child: Text('Grade 11 Students')),
                        DropdownMenuItem(value: 'Grade 12', child: Text('Grade 12 Students')),
                      ],
                      onChanged: (v) => setDialogState(() => targetAudience = v ?? 'all'),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Pin to Top of Feed', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      subtitle: const Text('Highlighted for all members', style: TextStyle(fontSize: 11)),
                      value: isPinned,
                      onChanged: (v) => setDialogState(() => isPinned = v),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final title = titleController.text.trim();
                        final content = contentController.text.trim();
                        if (title.isEmpty || content.isEmpty) {
                          setDialogState(() => errorText = 'Title and content are required.');
                          return;
                        }

                        setDialogState(() {
                          isSubmitting = true;
                          errorText = null;
                        });

                        try {
                          if (announcement == null) {
                            await _announcementService.createAnnouncement(
                              schoolId: _ciroSchoolId,
                              title: title,
                              content: content,
                              authorName: authorName,
                              authorRole: 'School Director',
                              targetAudience: targetAudience,
                              isPinned: isPinned,
                            );
                          } else {
                            await _announcementService.updateAnnouncement(
                              id: announcement.id,
                              title: title,
                              content: content,
                              targetAudience: targetAudience,
                              isPinned: isPinned,
                            );
                          }

                          if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                          _loadDashboardData();
                        } catch (e) {
                          setDialogState(() {
                            isSubmitting = false;
                            errorText = 'Error saving announcement: $e';
                          });
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Text(announcement == null ? 'Publish' : 'Update'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _deleteAnnouncement(SchoolAnnouncement announcement) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Announcement'),
        content: Text('Are you sure you want to remove "${announcement.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _announcementService.deleteAnnouncement(announcement.id);
        _loadDashboardData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Announcement deleted.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentUser = ref.watch(authStateProvider).user;
    final directorName = currentUser?.fullName?.isNotEmpty == true
        ? currentUser!.fullName!
        : currentUser?.username ?? 'Director';

    return DashboardShell(
      title: 'Director Portal',
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Welcome Banner
              _buildHeaderBanner(isDark, directorName),
              const SizedBox(height: 24),

              // 2. Statistics Grid
              _buildStatsGrid(isDark),
              const SizedBox(height: 24),

              // 3. Quick Actions
              _buildQuickActions(isDark),
              const SizedBox(height: 24),

              // 4. Ciro High School Student Enrollment by Grade Level
              _buildGradeEnrollmentCard(isDark),
              const SizedBox(height: 24),

              // 5. Teacher Academic Activity Monitoring
              _buildTeacherActivityCard(isDark),
              const SizedBox(height: 24),

              // 6. School Announcements Management
              _buildAnnouncementsCard(isDark),
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBanner(bool isDark, String directorName) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFF1E293B), const Color(0xFF334155)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_rounded, size: 14, color: Color(0xFF10B981)),
                    SizedBox(width: 6),
                    Text(
                      'Ciro High School • School Director',
                      style: TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '1 Appointed Director',
                  style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: _loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18, color: Colors.white70),
                onPressed: _loading ? null : _loadDashboardData,
                tooltip: 'Refresh Director Data',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Welcome, Director $directorName',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Overseeing faculty administration, teacher reviews, academic coordination, and official school communications.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900
            ? 4
            : constraints.maxWidth > 550
                ? 2
                : 1;

        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: constraints.maxWidth > 550 ? 1.6 : 2.4,
          children: [
            _buildStatCard(
              title: 'Faculty Teachers',
              value: '$_facultyTeacherCount',
              subtitle: '$_activeTeacherCount active in service',
              icon: Icons.co_present_rounded,
              color: const Color(0xFF3B82F6),
              isDark: isDark,
              onTap: () => context.push('/admin/teachers'),
            ),
            _buildStatCard(
              title: 'Teacher Approvals',
              value: '$_pendingTeacherApprovals',
              subtitle: _pendingTeacherApprovals > 0 ? 'Pending your review' : 'All requests resolved',
              icon: Icons.how_to_reg_rounded,
              color: const Color(0xFFF59E0B),
              isDark: isDark,
              onTap: () => context.push('/admin/approvals'),
            ),
            _buildStatCard(
              title: 'Announcements',
              value: '$_announcementsCount',
              subtitle: 'Active school notices',
              icon: Icons.campaign_rounded,
              color: const Color(0xFF10B981),
              isDark: isDark,
              onTap: () => _showAnnouncementDialog(),
            ),
            _buildStatCard(
              title: 'Academic Activities',
              value: '${_teacherActivities.length}',
              subtitle: 'Exams & study materials',
              icon: Icons.history_edu_rounded,
              color: const Color(0xFF8B5CF6),
              isDark: isDark,
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isDark,
    VoidCallback? onTap,
  }) {
    return AnimatedPressButton(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: isDark ? 0.2 : 0.15)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[400] : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.bolt_rounded, color: Color(0xFF6366F1), size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'Director Administrative Hub',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildActionButton(
                label: 'Register Faculty',
                icon: Icons.person_add_rounded,
                color: const Color(0xFF3B82F6),
                onTap: () => context.push('/admin/register-user'),
              ),
              _buildActionButton(
                label: 'Faculty Directory',
                icon: Icons.badge_outlined,
                color: const Color(0xFF0EA5E9),
                onTap: () => context.push('/admin/teachers'),
              ),
              _buildActionButton(
                label: 'Teacher Approvals',
                icon: Icons.approval_rounded,
                color: const Color(0xFFF59E0B),
                badgeCount: _pendingTeacherApprovals,
                onTap: () => context.push('/admin/approvals'),
              ),
              _buildActionButton(
                label: 'Post Announcement',
                icon: Icons.campaign_rounded,
                color: const Color(0xFF10B981),
                onTap: () => _showAnnouncementDialog(),
              ),
              _buildActionButton(
                label: 'Transfer Position',
                icon: Icons.swap_horiz_rounded,
                color: const Color(0xFF6366F1),
                onTap: _showTransferPositionDialog,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    return AnimatedPressButton(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
            ),
            if (badgeCount != null && badgeCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGradeEnrollmentCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.school_rounded, color: Color(0xFF10B981), size: 18),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ciro High School Students by Grade Level',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Grade enrollment numbers only (no individual records)',
                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_gradeStats.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: const Text('Enrollment stats loading...'),
            )
          else
            LayoutBuilder(
              builder: (ctx, constraints) {
                final isWide = constraints.maxWidth > 600;
                final cards = _gradeStats.map((g) {
                  final gradeName = g['grade']?.toString() ?? 'Grade';
                  final count = (g['count'] as num?)?.toInt() ?? 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                gradeName.replaceAll(RegExp(r'[^0-9]'), ''),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF10B981),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              gradeName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$count Students',
                            style: const TextStyle(
                              color: Color(0xFF10B981),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList();

                if (isWide) {
                  return GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 12,
                    childAspectRatio: 3.2,
                    children: cards,
                  );
                }

                return Column(
                  children: cards
                      .map((c) => Padding(padding: const EdgeInsets.only(bottom: 8), child: c))
                      .toList(),
                );
              },
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF64748B).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, size: 16, color: Color(0xFF64748B)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Student Privacy Gate: As School Director, grade level enrollment counts are shown for school-wide capacity planning. Individual marks, exams, and student private records are handled strictly by assigned teachers.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeacherActivityCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.history_edu_rounded, color: Color(0xFF8B5CF6), size: 18),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Teacher Academic Activity Monitoring',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Real-time feed of examinations, quizzes, and resources created by teachers',
                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                onPressed: _loadDashboardData,
                tooltip: 'Refresh Activity Feed',
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_teacherActivities.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 36, color: Colors.grey.withValues(alpha: 0.4)),
                  const SizedBox(height: 8),
                  const Text('No recent teacher activities recorded.', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _teacherActivities.length.clamp(0, 8),
              separatorBuilder: (_, _) => const Divider(height: 16),
              itemBuilder: (ctx, index) {
                final act = _teacherActivities[index];
                IconData actIcon = Icons.quiz_outlined;
                Color actColor = const Color(0xFF3B82F6);

                if (act.activityType == 'examination_published') {
                  actIcon = Icons.fact_check_rounded;
                  actColor = const Color(0xFF10B981);
                } else if (act.activityType == 'resource_uploaded') {
                  actIcon = Icons.menu_book_rounded;
                  actColor = const Color(0xFFF59E0B);
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: actColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(actIcon, size: 16, color: actColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                act.teacherName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              if (act.subject != null) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    act.subject!,
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                              const Spacer(),
                              Text(
                                act.status,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: act.status == 'Published' ? const Color(0xFF10B981) : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            act.description,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.grey[300] : const Color(0xFF334155),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Target: ${act.targetDisplay} • ${_formatRelativeTime(act.createdAt)}',
                            style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementsCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.campaign_rounded, color: Color(0xFF10B981), size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Official School Announcements',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Notice', style: TextStyle(fontSize: 12)),
                onPressed: () => _showAnnouncementDialog(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_announcements.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: const Text('No active announcements. Click "New Notice" to publish.',
                  style: TextStyle(color: Colors.grey)),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _announcements.length,
              separatorBuilder: (_, _) => const Divider(height: 16),
              itemBuilder: (ctx, index) {
                final ann = _announcements[index];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  ann.title,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    ann.targetAudience.toUpperCase(),
                                    style: const TextStyle(
                                      color: Color(0xFF10B981),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              ann.content,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.grey[300] : const Color(0xFF475569),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatRelativeTime(ann.createdAt),
                              style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        tooltip: 'Edit Notice',
                        onPressed: () => _showAnnouncementDialog(announcement: ann),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        tooltip: 'Delete Notice',
                        onPressed: () => _deleteAnnouncement(ann),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${time.day}/${time.month}/${time.year}';
  }
}
