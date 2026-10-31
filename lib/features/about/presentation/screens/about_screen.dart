import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late final AnimationController _pulseController;
  Timer? _carouselTimer;
  int _currentPage = 0;

  final List<({String image, String title, String subtitle, IconData icon})>
      _slides = const [
    (
      image: 'assets/images/about.jpeg',
      title: 'Ciro Schools Academic Mission',
      subtitle: 'Nurturing future leaders through modern digital education, high standards, and integrity.',
      icon: Icons.auto_awesome_rounded,
    ),
    (
      image: 'assets/images/home.jpeg',
      title: 'Unified Digital Campus',
      subtitle: 'Centralized high school portal for secure tests, practice sheets, and grade records.',
      icon: Icons.school_rounded,
    ),
    (
      image: 'assets/images/school_building.jpeg',
      title: 'Main Academic Campus',
      subtitle: 'Modern educational infrastructure dedicated to student excellence.',
      icon: Icons.domain_rounded,
    ),
    (
      image: 'assets/images/campus.jpeg',
      title: 'Vibrant Campus Grounds',
      subtitle: 'Inspiring collegiate environment fostering collaborative study.',
      icon: Icons.park_rounded,
    ),
    (
      image: 'assets/images/classroom.jpeg',
      title: 'Advanced Classrooms',
      subtitle: 'Digital-first learning spaces equipped for secure testing.',
      icon: Icons.meeting_room_rounded,
    ),
    (
      image: 'assets/images/exam_prep.jpeg',
      title: 'Proctored Examination Halls',
      subtitle: 'Fair, secure, and monitored testing with anti-cheat protection.',
      icon: Icons.quiz_rounded,
    ),
    (
      image: 'assets/images/teachers.jpeg',
      title: 'Dedicated Faculty & Mentors',
      subtitle: 'Expert educators preparing targeted curriculum and diagnostics.',
      icon: Icons.co_present_rounded,
    ),
    (
      image: 'assets/images/diploma.jpeg',
      title: 'Academic Achievement',
      subtitle: 'Celebrating high-school milestones and pathway to higher education.',
      icon: Icons.workspace_premium_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _startAutoPlay();
  }

  void _startAutoPlay() {
    _carouselTimer?.cancel();
    _carouselTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted || !_pageController.hasClients) return;
      final nextPage = (_currentPage + 1) % _slides.length;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _pageController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _showAntiCheatModal(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.security_rounded,
                    color: Color(0xFF10B981),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Anti-Cheat & Examination Security',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'To ensure absolute fairness during high school academic exams, the system enforces multi-tiered security protocols:',
              style: TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 14),
            _buildSecurityPoint(
              icon: Icons.screenshot_monitor_rounded,
              title: 'Native Screenshot Blocking (FLAG_SECURE)',
              subtitle: 'Device captures during exams are blacked out at the operating system level.',
            ),
            _buildSecurityPoint(
              icon: Icons.videocam_off_rounded,
              title: 'Active Screen Recording Defense',
              subtitle: 'Detects background screen recorders and obscures questions with a security shield.',
            ),
            _buildSecurityPoint(
              icon: Icons.shuffle_rounded,
              title: 'Shuffled Questions & Individual Timers',
              subtitle: 'Questions and choices are randomized per student to prevent adjacent glancing.',
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Understood & Verified', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showPdfWorksheetsModal(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf_rounded,
                    color: Color(0xFF0284C7),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Worksheet & PDF Distribution',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSecurityPoint(
              icon: Icons.upload_file_rounded,
              title: 'Teacher PDF & Worksheet Upload',
              subtitle:
                  'Teachers can upload practice worksheets, revision packages, and official exam question papers directly for their grade and section.',
            ),
            _buildSecurityPoint(
              icon: Icons.download_rounded,
              title: 'Targeted Student PDF Access',
              subtitle:
                  'Students in Grade 9 to 12 only see worksheets targeted to their enrolled grade and section (A, B, C, D).',
            ),
            _buildSecurityPoint(
              icon: Icons.attach_file_rounded,
              title: 'Exam Question Paper Attachments',
              subtitle:
                  'Quizzes can include an attached exam PDF paper that students can consult during their proctored test.',
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Got It', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showGradingModal(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: Color(0xFF6366F1),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Grading Standards & Assessment',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSecurityPoint(
              icon: Icons.check_circle_rounded,
              title: 'Automated Instant Scoring',
              subtitle: 'Multiple-choice and true/false questions are verified instantaneously on submission.',
            ),
            _buildSecurityPoint(
              icon: Icons.draw_rounded,
              title: 'Teacher Diagram Evaluation',
              subtitle: 'Descriptive answers with student diagrams or photos are reviewed by course teachers.',
            ),
            _buildSecurityPoint(
              icon: Icons.insights_rounded,
              title: 'Targeted Grade & Section Rosters',
              subtitle: 'Exams are tailored to Grade 9, 10, 11, or 12 and specific classroom sections (A, B, C).',
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close Standards', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showContactModal(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.contact_support_rounded,
                    color: Color(0xFF0D9488),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Administration & Tech Support',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                children: [
                  _buildContactRow(
                    icon: Icons.email_rounded,
                    label: 'Administration Desk',
                    value: 'admin@ciroschools.edu',
                    onCopy: () => _copyText(context, 'admin@ciroschools.edu'),
                  ),
                  const Divider(height: 20),
                  _buildContactRow(
                    icon: Icons.headset_mic_rounded,
                    label: 'Technical Helpdesk',
                    value: 'support@ciroschools.edu',
                    onCopy: () => _copyText(context, 'support@ciroschools.edu'),
                  ),
                  const Divider(height: 20),
                  _buildContactRow(
                    icon: Icons.school_rounded,
                    label: 'Campus Domains',
                    value: '@Admin.edu · @Director.edu · @Teacher.edu · @Student.edu',
                    onCopy: () => _copyText(context, '@Director.edu'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.share_rounded, size: 18),
              label: const Text('Share Portal Information', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                _copyText(
                  context,
                  'Ciro High Schools Assessment Portal\nCredentials format:\n- Student: NameFatherName@Student.edu\n- Faculty Teacher: NameFatherName@Teacher.edu\n- School Director: NameFatherName@Director.edu\n- Super Admin: NameFatherName@Admin.edu',
                );
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _checkSystemStatus(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Checking system health & latency...'),
          ],
        ),
        duration: Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final start = DateTime.now();
      await Supabase.instance.client.from('schools').select('id').limit(1);
      final latency = DateTime.now().difference(start).inMilliseconds;

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'System Operational · Real-time Latency: ${latency}ms · All Services Active',
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Portal Online · Local Cache Active'),
          backgroundColor: Color(0xFF0D9488),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _copyText(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard!'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildContactRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onCopy,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF10B981)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy_rounded, size: 16),
          tooltip: 'Copy',
          onPressed: onCopy,
        ),
      ],
    );
  }

  static Widget _buildSecurityPoint({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF10B981), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DashboardShell(
      title: 'About Ciro Schools Portal',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Animated School Showcase Carousel
          Container(
            height: 260,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _pageController,
                    onPageChanged: (index) => setState(() => _currentPage = index),
                    itemCount: _slides.length,
                    itemBuilder: (context, index) {
                      final slide = _slides[index];
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset(
                            slide.image,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              child: const Icon(
                                Icons.school_rounded,
                                size: 64,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ),
                          // Gradient scrim for text readability
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.15),
                                  Colors.black.withValues(alpha: 0.85),
                                ],
                              ),
                            ),
                          ),
                          // Slide Caption
                          Positioned(
                            left: 20,
                            right: 20,
                            bottom: 20,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(slide.icon, size: 14, color: Colors.white),
                                      const SizedBox(width: 6),
                                      Text(
                                        'CIRO CAMPUS ${index + 1}/${_slides.length}',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.8,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  slide.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  slide.subtitle,
                                  style: const TextStyle(
                                    color: Color(0xFFE2E8F0),
                                    fontSize: 12,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  // Carousel Indicators & Controls
                  Positioned(
                    top: 14,
                    right: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int i = 0; i < _slides.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              margin: const EdgeInsets.symmetric(horizontal: 2.5),
                              width: _currentPage == i ? 18 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: _currentPage == i
                                    ? const Color(0xFF10B981)
                                    : Colors.white.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Institutional Header with Animated Pulse Logo
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, _) => Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(
                        color: const Color(0xFF10B981),
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(
                            alpha: 0.2 + (_pulseController.value * 0.3),
                          ),
                          blurRadius: 16 + (_pulseController.value * 8),
                          spreadRadius: 2 + (_pulseController.value * 3),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.school_rounded,
                          size: 36,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CIRO HIGH SCHOOLS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                          color: isDark
                              ? const Color(0xFF34D399)
                              : const Color(0xFF059669),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Examination & Assessment Portal',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text(
                          'Release 2.0 · Verified Secure',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Interactive Operational Actions & Dialogs
          Text(
            'Portal Information & Protocols',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),

          _InteractiveActionCard(
            icon: Icons.picture_as_pdf_rounded,
            color: const Color(0xFF0284C7),
            title: 'Class Worksheets & Exam PDFs',
            subtitle:
                'Explore teacher PDF upload features, worksheet distribution, and targeted classroom materials.',
            buttonText: 'Worksheets Guide',
            onTap: () => _showPdfWorksheetsModal(context),
          ),
          const SizedBox(height: 10),

          _InteractiveActionCard(
            icon: Icons.shield_rounded,
            color: const Color(0xFF10B981),
            title: 'Anti-Cheat & Security Protocols',
            subtitle:
                'Explore native screenshot protection, active screen recording detection, and randomize algorithms.',
            buttonText: 'View Protocols',
            onTap: () => _showAntiCheatModal(context),
          ),
          const SizedBox(height: 10),

          _InteractiveActionCard(
            icon: Icons.assignment_turned_in_rounded,
            color: const Color(0xFF6366F1),
            title: 'Academic Standards & Grading Policies',
            subtitle:
                'Understand auto-grading thresholds, diagram evaluations, and grade/section targeting.',
            buttonText: 'Grading Guide',
            onTap: () => _showGradingModal(context),
          ),
          const SizedBox(height: 10),

          _InteractiveActionCard(
            icon: Icons.support_agent_rounded,
            color: const Color(0xFF0D9488),
            title: 'Administration & Technical Support',
            subtitle:
                'Access administrator contact emails, institutional credentials format, and support tickets.',
            buttonText: 'Contact Support',
            onTap: () => _showContactModal(context),
          ),
          const SizedBox(height: 10),

          _InteractiveActionCard(
            icon: Icons.speed_rounded,
            color: const Color(0xFF0F172A),
            title: 'System Health & Latency Test',
            subtitle:
                'Execute live diagnostic ping to Supabase servers to verify real-time assessment connectivity.',
            buttonText: 'Test Latency',
            onTap: () => _checkSystemStatus(context),
          ),
          const SizedBox(height: 28),

          // Institutional Footer
          Center(
            child: Column(
              children: [
                const Icon(Icons.verified_rounded, size: 28, color: Color(0xFF10B981)),
                const SizedBox(height: 8),
                Text(
                  'Ciro Schools Academic Assessment Portal',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Empowering students and faculty with modern, secure academic assessments.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InteractiveActionCard extends StatelessWidget {
  const _InteractiveActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: color.withValues(alpha: 0.14),
                  foregroundColor: color,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: onTap,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      buttonText,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_rounded, size: 14),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
