import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:quiz_app/core/constants/app_roles.dart';
import 'package:quiz_app/core/services/course_resource_service.dart';
import 'package:quiz_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:quiz_app/shared/models/course_resource.dart';
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
  String _filterType = 'all'; // all, worksheet, exam, pdf

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

    if (user.role == AppRoles.teacher) {
      _resourcesFuture = _resourceService.getResourcesByTeacher(user.id);
    } else {
      _resourcesFuture = _resourceService.getResourcesForStudent(
        targetGrade: null, // will fetch and filter
        targetSection: null,
        schoolId: user.schoolId,
      );
    }
  }

  Future<void> _pickAndUploadResource() async {
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

    // Show dialog to enter Title, Grade, and Section
    String title = file.name.replaceAll('.pdf', '').replaceAll('_', ' ');
    String description = '';
    String selectedGrade = 'Grade 9';
    String selectedSection = 'Section A';
    String fileType = 'worksheet';

    final shouldUpload = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.upload_file_rounded, color: Color(0xFF10B981)),
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
                    labelText: 'Target Section',
                    prefixIcon: Icon(Icons.class_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Section A', child: Text('Section A')),
                    DropdownMenuItem(value: 'Section B', child: Text('Section B')),
                    DropdownMenuItem(value: 'Section C', child: Text('Section C')),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = ref.watch(authStateProvider).user;
    final isTeacher = user?.role == AppRoles.teacher;

    return DashboardShell(
      title: 'Class Worksheets & PDFs',
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _loadResources()),
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
                                Icons.picture_as_pdf_rounded,
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
                                        ? 'Teacher PDF & Worksheet Uploader'
                                        : 'My Class Worksheets & Exams',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isTeacher
                                        ? 'Upload exams, worksheets, and course materials targeted for Grade 9-12 and specific sections.'
                                        : 'Access and download official worksheets and exams uploaded by your teachers for your grade and section.',
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
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF0F172A),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _pickAndUploadResource,
                            icon: const Icon(Icons.upload_file_rounded, size: 18),
                            label: const Text(
                              'Upload Worksheet / Exam PDF',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Search Bar & Filter Chips
            TextField(
              decoration: InputDecoration(
                hintText: 'Search worksheets by title, grade, or topic...',
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
                    (type: 'all', label: 'All Files', icon: Icons.folder_open_rounded),
                    (type: 'worksheet', label: 'Worksheets', icon: Icons.assignment_outlined),
                    (type: 'exam', label: 'Exam Papers', icon: Icons.quiz_outlined),
                    (type: 'pdf', label: 'Reference PDFs', icon: Icons.menu_book_outlined),
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
                          'Could not load worksheets: ${snapshot.error}',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ),
                  );
                }

                final allList = snapshot.data ?? [];
                final filtered = allList.where((res) {
                  if (_filterType != 'all' && res.fileType != _filterType) {
                    return false;
                  }
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
                                  ? 'No worksheets uploaded yet'
                                  : 'No worksheets available for your class yet',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isTeacher
                                  ? 'Click the button above to upload PDF worksheets and exams for your students.'
                                  : 'When your teachers upload study sheets, exam papers, or PDFs, they will appear here.',
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
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final res = filtered[index];
                    return _ResourceCard(
                      resource: res,
                      isDark: isDark,
                      isTeacher: isTeacher,
                      onDelete: isTeacher
                          ? () async {
                              await _resourceService.deleteResource(res.id);
                              setState(() => _loadResources());
                            }
                          : null,
                    );
                  },
                );
              },
            ),
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

  @override
  Widget build(BuildContext context) {
    final sizeKb = resource.fileSize != null
        ? '${(resource.fileSize! / 1024).toStringAsFixed(1)} KB'
        : 'PDF';

    return Container(
      padding: const EdgeInsets.all(16),
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
                : const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.picture_as_pdf_rounded,
                  color: Color(0xFF10B981),
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resource.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      resource.fileName,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
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
                fontSize: 12,
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
                  sizeKb,
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
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Download / View PDF'),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Opening ${resource.fileName}...'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
