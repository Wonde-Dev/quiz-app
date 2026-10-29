import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/services/course_resource_service.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_app/shared/models/course_resource.dart';
import 'package:quiz_app/shared/widgets/animated_press_button.dart';
import 'package:quiz_app/shared/widgets/dashboard_shell.dart';

class ResourcesScreen extends ConsumerStatefulWidget {
  const ResourcesScreen({super.key});

  @override
  ConsumerState<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends ConsumerState<ResourcesScreen> {
  final _resourceService = CourseResourceService();
  late Future<List<CourseResource>> _resourcesFuture;
  String _searchQuery = '';
  String _filterType = 'all'; // all, pdf, video, worksheet, exam
  bool _materialsLocked = false;
  bool _togglingLock = false;

  @override
  void initState() {
    super.initState();
    _loadResources();
  }

  void _loadResources() {
    final user = ref.read(authStateProvider).user;
    if (user == null) {
      _resourcesFuture = Future.value([]);
      return;
    }

    _resourceService.isMaterialsLocked(schoolId: user.schoolId).then((locked) {
      if (mounted) setState(() => _materialsLocked = locked);
    });

    if (user.role == AppRoles.teacher) {
      _resourcesFuture = _resourceService.getResourcesByTeacher(user.id);
    } else {
      _resourcesFuture = _resourceService.getResourcesForStudent(
        targetGrade: user.assignedGrade,
        targetSection: user.assignedClass,
        schoolId: user.schoolId,
      );
    }
  }

  Future<void> _toggleMaterialsLock() async {
    final user = ref.read(authStateProvider).user;
    setState(() => _togglingLock = true);
    final nextState = !_materialsLocked;
    await _resourceService.toggleMaterialsLock(nextState, schoolId: user?.schoolId);
    if (mounted) {
      setState(() {
        _materialsLocked = nextState;
        _togglingLock = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextState
                ? 'Exam Mode Enabled: PDFs and videos are now locked for students.'
                : 'Exam Mode Disabled: Students can now access study materials.',
          ),
          backgroundColor: nextState ? Colors.amber.shade900 : const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickAndUploadPdfResource() async {
    final user = ref.read(authStateProvider).user;
    if (user == null || user.role != AppRoles.teacher) return;

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'xlsx'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read file data.')),
        );
      }
      return;
    }

    if (!mounted) return;

    String title = file.name.replaceAll('.pdf', '').replaceAll('_', ' ');
    String description = '';
    String selectedGrade = 'Grade 9';
    String selectedSection = 'Section A';
    String fileType = 'worksheet';

    final shouldUpload = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF10B981)),
              SizedBox(width: 10),
              Text('Upload Worksheet / PDF'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selected File: ${file.name}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  'Size: ${(file.size / 1024).toStringAsFixed(1)} KB',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: title,
                  decoration: const InputDecoration(
                    labelText: 'Worksheet / Exam Title',
                    prefixIcon: Icon(Icons.title_rounded),
                  ),
                  onChanged: (v) => title = v,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Description / Instructions (Optional)',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                  onChanged: (v) => description = v,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedGrade,
                  decoration: const InputDecoration(
                    labelText: 'Target Grade (9 - 12)',
                    prefixIcon: Icon(Icons.grade_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Grade 9', child: Text('Grade 9')),
                    DropdownMenuItem(value: 'Grade 10', child: Text('Grade 10')),
                    DropdownMenuItem(value: 'Grade 11', child: Text('Grade 11')),
                    DropdownMenuItem(value: 'Grade 12', child: Text('Grade 12')),
                  ],
                  onChanged: (v) => setDialogState(() => selectedGrade = v ?? 'Grade 9'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedSection,
                  decoration: const InputDecoration(
                    labelText: 'Target Section / Class',
                    prefixIcon: Icon(Icons.class_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Section A', child: Text('Section A (or 9A/10A)')),
                    DropdownMenuItem(value: 'Section B', child: Text('Section B (or 9B/10B)')),
                    DropdownMenuItem(value: 'Section C', child: Text('Section C (or 9C/10C)')),
                    DropdownMenuItem(value: 'Section D', child: Text('Section D')),
                    DropdownMenuItem(value: 'All Sections', child: Text('All Sections')),
                  ],
                  onChanged: (v) => setDialogState(() => selectedSection = v ?? 'Section A'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: fileType,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'worksheet', child: Text('Worksheet & Practice')),
                    DropdownMenuItem(value: 'exam', child: Text('Official Exam Paper (PDF)')),
                    DropdownMenuItem(value: 'pdf', child: Text('Study Notes / Reference PDF')),
                  ],
                  onChanged: (v) => setDialogState(() => fileType = v ?? 'worksheet'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.cloud_upload_rounded, size: 16),
              label: const Text('Upload PDF'),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );

    if (shouldUpload != true) return;

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Uploading worksheet PDF...')),
        );
      }

      await _resourceService.uploadResource(
        fileBytes: file.bytes!,
        fileName: file.name,
        title: title,
        description: description.isNotEmpty ? description : null,
        targetGrade: selectedGrade,
        targetSection: selectedSection,
        teacherId: user.id,
        teacherName: user.fullName?.isNotEmpty == true ? user.fullName! : user.username,
        schoolId: user.schoolId,
        fileType: fileType,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Worksheet PDF uploaded successfully for students!'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        setState(() => _loadResources());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _addVideoLessonResource() async {
    final user = ref.read(authStateProvider).user;
    if (user == null || user.role != AppRoles.teacher) return;

    final titleController = TextEditingController();
    final urlController = TextEditingController();
    final descController = TextEditingController();

    String selectedGrade = 'Grade 9';
    String selectedSection = 'Section A';
    String? liveThumbnailUrl;
    Uint8List? pickedThumbnailBytes;
    String? pickedThumbnailName;

    final shouldAdd = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.smart_display_rounded, color: Color(0xFFEF4444)),
              SizedBox(width: 10),
              Text('Add Video Lesson'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Provide a video URL (YouTube, Vimeo, MP4) for your students to watch alongside course notes.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Video Title *',
                    hintText: 'e.g. Physics: Newton\'s Laws Explained',
                    prefixIcon: Icon(Icons.title_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: 'Video Link / URL *',
                    hintText: 'https://www.youtube.com/watch?v=...',
                    prefixIcon: Icon(Icons.link_rounded),
                  ),
                  onChanged: (val) {
                    final detected = CourseResource.extractYoutubeThumbnail(val.trim());
                    setDialogState(() => liveThumbnailUrl = detected);
                  },
                ),
                const SizedBox(height: 12),

                // Live Thumbnail Preview Card
                if (pickedThumbnailBytes != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.memory(
                          pickedThumbnailBytes!,
                          height: 130,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ] else if (liveThumbnailUrl != null && liveThumbnailUrl!.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.network(
                          liveThumbnailUrl!,
                          height: 130,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '✓ Auto-detected YouTube Thumbnail',
                    style: TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                ],

                OutlinedButton.icon(
                  onPressed: () async {
                    final picker = ImagePicker();
                    final img = await picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 1280,
                      maxHeight: 720,
                      imageQuality: 85,
                    );
                    if (img != null) {
                      final bytes = await img.readAsBytes();
                      setDialogState(() {
                        pickedThumbnailBytes = bytes;
                        pickedThumbnailName = img.name;
                      });
                    }
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
                  label: Text(
                    pickedThumbnailBytes != null ? 'Change Custom Thumbnail' : 'Upload Custom Thumbnail',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Video Description / Lesson Objectives',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  initialValue: selectedGrade,
                  decoration: const InputDecoration(
                    labelText: 'Target Grade (9 - 12)',
                    prefixIcon: Icon(Icons.grade_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Grade 9', child: Text('Grade 9')),
                    DropdownMenuItem(value: 'Grade 10', child: Text('Grade 10')),
                    DropdownMenuItem(value: 'Grade 11', child: Text('Grade 11')),
                    DropdownMenuItem(value: 'Grade 12', child: Text('Grade 12')),
                  ],
                  onChanged: (v) => setDialogState(() => selectedGrade = v ?? 'Grade 9'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedSection,
                  decoration: const InputDecoration(
                    labelText: 'Target Section / Class',
                    prefixIcon: Icon(Icons.class_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Section A', child: Text('Section A (or 9A/10A)')),
                    DropdownMenuItem(value: 'Section B', child: Text('Section B (or 9B/10B)')),
                    DropdownMenuItem(value: 'Section C', child: Text('Section C (or 9C/10C)')),
                    DropdownMenuItem(value: 'Section D', child: Text('Section D')),
                    DropdownMenuItem(value: 'All Sections', child: Text('All Sections')),
                  ],
                  onChanged: (v) => setDialogState(() => selectedSection = v ?? 'Section A'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Add Video'),
              onPressed: () {
                if (titleController.text.trim().isEmpty || urlController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Enter both video title and URL')),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
            ),
          ],
        ),
      ),
    );

    if (shouldAdd != true) return;

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saving video lesson...')),
        );
      }

      await _resourceService.addVideoResource(
        title: titleController.text.trim(),
        description: descController.text.trim().isNotEmpty ? descController.text.trim() : null,
        videoUrl: urlController.text.trim(),
        thumbnailBytes: pickedThumbnailBytes,
        thumbnailFileName: pickedThumbnailName,
        targetGrade: selectedGrade,
        targetSection: selectedSection,
        teacherId: user.id,
        teacherName: user.fullName?.isNotEmpty == true ? user.fullName! : user.username,
        schoolId: user.schoolId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video lesson added successfully for students!'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        setState(() => _loadResources());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = ref.watch(authStateProvider).user;
    final isTeacher = user?.role == AppRoles.teacher;
    final isFacultyOrAdmin = isTeacher ||
        user?.isSuperAdmin == true ||
        user?.role == AppRoles.admin ||
        user?.role == AppRoles.subadmin;

    return DashboardShell(
      title: 'Course Materials & Video Lessons',
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {
            _loadResources();
          });
          await _resourcesFuture;
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Welcome Header Card with Classroom Illustration
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFF10B981).withValues(alpha: 0.35),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.16),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.4)
                        : const Color(0xFF0F172A).withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/classroom.jpeg',
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: const Color(0xFF064E3B),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? [
                                  const Color(0xF5064E3B),
                                  const Color(0xF80F172A),
                                  const Color(0xF0022C22),
                                ]
                              : [
                                  const Color(0xEE064E3B),
                                  const Color(0xEA0F172A),
                                  const Color(0xDC047857),
                                ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                              ),
                              child: const Icon(
                                Icons.auto_stories_rounded,
                                color: Color(0xFF34D399),
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isTeacher
                                        ? 'Teacher Learning Materials Hub'
                                        : 'My Worksheets & Video Lessons',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isTeacher
                                        ? 'Upload PDF worksheets, official exams, and interactive video lesson URLs with thumbnails.'
                                        : 'Access worksheets, study guides, and watch video lessons published by your teachers.',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFE2E8F0),
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (isTeacher) ...[
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF0F172A),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: _pickAndUploadPdfResource,
                                icon: const Icon(Icons.upload_file_rounded, size: 18),
                                label: const Text(
                                  'Upload PDF Worksheet',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFEF4444),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: _addVideoLessonResource,
                                icon: const Icon(Icons.video_call_rounded, size: 18),
                                label: const Text(
                                  'Add Video Lesson',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Teacher & Administration Exam Lockdown One-Button Toggle
            if (isFacultyOrAdmin) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _materialsLocked
                      ? const Color(0xFF78350F).withValues(alpha: isDark ? 0.35 : 0.12)
                      : const Color(0xFF10B981).withValues(alpha: isDark ? 0.18 : 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _materialsLocked ? const Color(0xFFD97706) : const Color(0xFF10B981),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _materialsLocked ? const Color(0xFFD97706) : const Color(0xFF10B981),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _materialsLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _materialsLocked
                                ? 'EXAM LOCKDOWN: ACTIVE'
                                : 'STUDY MATERIALS: ONLINE',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 0.4,
                              color: _materialsLocked ? const Color(0xFFD97706) : const Color(0xFF047857),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _materialsLocked
                                ? 'Students cannot view PDFs or videos during the exam period.'
                                : 'Students can view and download worksheets and watch video lessons.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    AnimatedPressButton(
                      onTap: _togglingLock ? null : _toggleMaterialsLock,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: _materialsLocked ? const Color(0xFF10B981) : const Color(0xFFD97706),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: _togglingLock
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _materialsLocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _materialsLocked ? 'Unlock' : 'Lock for Exam',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Student Exam Lockdown Gate: Students cannot access PDFs or videos during exam time
            if (user?.role == AppRoles.student && _materialsLocked) ...[
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFD97706), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD97706).withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD97706).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_clock_rounded, color: Color(0xFFD97706), size: 54),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Study Materials Locked for Exam',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Your teacher has closed access to PDF worksheets and video lessons while an exam is taking place to ensure exam integrity.\n\nPlease focus on your active quiz!',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    AnimatedPressButton(
                      onTap: () => context.go('/student/dashboard'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF10B981), Color(0xFF059669)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.quiz_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Go to Quizzes & Exams',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _loadResources();
                        });
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Check / Refresh Status'),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Search Bar
              TextField(
              decoration: InputDecoration(
                hintText: 'Search worksheets and video lessons...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 14),

            // Category filter chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final item in const [
                    (type: 'all', label: 'All Resources', icon: Icons.folder_open_rounded),
                    (type: 'video', label: 'Video Lessons', icon: Icons.smart_display_outlined),
                    (type: 'pdf', label: 'Worksheets & PDFs', icon: Icons.picture_as_pdf_outlined),
                    (type: 'exam', label: 'Exam Papers', icon: Icons.quiz_outlined),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        avatar: Icon(item.icon, size: 16),
                        label: Text(item.label),
                        selected: _filterType == item.type,
                        onSelected: (_) => setState(() => _filterType = item.type),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Resources List
            FutureBuilder<List<CourseResource>>(
              future: _resourcesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'Could not load materials: ${snapshot.error}',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ),
                  );
                }

                final allList = snapshot.data ?? [];
                final filtered = allList.where((res) {
                  if (_filterType == 'video' && !res.isVideo) return false;
                  if (_filterType == 'pdf' && !res.isPdf) return false;
                  if (_filterType == 'exam' && res.fileType != 'exam') return false;

                  if (_searchQuery.isNotEmpty) {
                    final t = res.title.toLowerCase();
                    final g = (res.targetGrade ?? '').toLowerCase();
                    final s = (res.targetSection ?? '').toLowerCase();
                    final d = (res.description ?? '').toLowerCase();
                    return t.contains(_searchQuery) ||
                        g.contains(_searchQuery) ||
                        s.contains(_searchQuery) ||
                        d.contains(_searchQuery);
                  }
                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(36),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.description_outlined,
                              size: 48,
                              color: isDark ? Colors.white38 : Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              isTeacher
                                  ? 'No learning materials uploaded yet'
                                  : 'No worksheets or video lessons available yet',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isTeacher
                                  ? 'Use the buttons above to upload PDF worksheets or add interactive video lessons for your classes.'
                                  : 'When your teachers publish worksheets, study materials, or video lessons, they will show up here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final res = filtered[index];
                    final canDelete = isTeacher ||
                        user?.isSuperAdmin == true ||
                        user?.role == AppRoles.admin ||
                        (user?.role == AppRoles.subadmin &&
                            (res.schoolId == null || res.schoolId == user?.schoolId));

                    return _ResourceCard(
                      resource: res,
                      isDark: isDark,
                      isTeacher: isTeacher,
                      onDelete: canDelete
                          ? () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete Learning Material?'),
                                  content: Text(
                                    'Are you sure you want to delete "${res.title}"?\n\n'
                                    'This document or video prepared for students will be removed permanently.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await _resourceService.deleteResource(res.id);
                                if (context.mounted) {
                                  setState(() => _loadResources());
                                }
                              }
                            }
                          : null,
                    );
                  },
                );
              },
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    ),
  );
}
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({
    required this.resource,
    required this.isDark,
    required this.isTeacher,
    this.onDelete,
  });

  final CourseResource resource;
  final bool isDark;
  final bool isTeacher;
  final VoidCallback? onDelete;

  Future<void> _openResource(BuildContext context) async {
    final urlStr = (resource.videoUrl != null && resource.videoUrl!.isNotEmpty)
        ? resource.videoUrl!
        : resource.fileUrl;

    if (urlStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No link attached to this resource.')),
      );
      return;
    }

    final uri = Uri.tryParse(urlStr);
    if (uri != null) {
      try {
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched && context.mounted) {
          _showResourceFallbackDialog(context, urlStr);
        }
      } catch (_) {
        if (context.mounted) _showResourceFallbackDialog(context, urlStr);
      }
    } else {
      _showResourceFallbackDialog(context, urlStr);
    }
  }

  void _showResourceFallbackDialog(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(resource.isVideo ? 'Video Lesson' : 'Resource Document'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(resource.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SelectableText(url, style: const TextStyle(fontSize: 12, color: Colors.blue)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = resource.isVideo;
    final thumbnail = resource.effectiveThumbnail;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // If Video and Thumbnail is available, show video banner with play button
          if (isVideo && thumbnail != null && thumbnail.isNotEmpty)
            InkWell(
              onTap: () => _openResource(context),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.network(
                    thumbnail,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      height: 120,
                      color: const Color(0xFF1E293B),
                      child: const Center(
                        child: Icon(Icons.smart_display_rounded, size: 48, color: Colors.white54),
                      ),
                    ),
                  ),
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.ondemand_video_rounded, color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text(
                            'VIDEO LESSON',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isVideo || thumbnail == null || thumbnail.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: (isVideo ? const Color(0xFFEF4444) : const Color(0xFF10B981))
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isVideo ? Icons.smart_display_rounded : Icons.picture_as_pdf_rounded,
                          color: isVideo ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                          size: 26,
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            resource.title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isVideo ? (resource.videoUrl ?? resource.fileUrl) : resource.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onDelete != null)
                      IconButton(
                        tooltip: 'Delete resource',
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                        onPressed: onDelete,
                      ),
                  ],
                ),
                if (resource.description != null && resource.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    resource.description!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (resource.targetGrade != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: Text(
                          resource.targetGrade!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF047857),
                          ),
                        ),
                      ),
                    if (resource.targetSection != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Text(
                          resource.targetSection!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1D4ED8),
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isVideo ? 'Video' : 'PDF Worksheet',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                    if (resource.teacherName != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'by ${resource.teacherName}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: isVideo
                            ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                            : const Color(0xFF10B981).withValues(alpha: 0.12),
                        foregroundColor: isVideo ? const Color(0xFFDC2626) : const Color(0xFF047857),
                        minimumSize: const Size(0, 38),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      icon: Icon(
                        isVideo ? Icons.play_circle_fill_rounded : Icons.download_rounded,
                        size: 18,
                      ),
                      label: Text(isVideo ? 'Watch Video Lesson' : 'Open / Read PDF'),
                      onPressed: () => _openResource(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
