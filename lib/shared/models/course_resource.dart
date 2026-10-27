class CourseResource {
  final String id;
  final String title;
  final String? description;
  final String fileName;
  final String fileUrl;
  final String fileType; // pdf, worksheet, exam, video, study_guide
  final int? fileSize;
  final String? videoUrl;
  final String? thumbnailUrl;
  final String? schoolId;
  final String? teacherId;
  final String? teacherName;
  final String? targetGrade;
  final String? targetSection;
  final DateTime createdAt;

  const CourseResource({
    required this.id,
    required this.title,
    this.description,
    required this.fileName,
    required this.fileUrl,
    this.fileType = 'pdf',
    this.fileSize,
    this.videoUrl,
    this.thumbnailUrl,
    this.schoolId,
    this.teacherId,
    this.teacherName,
    this.targetGrade,
    this.targetSection,
    required this.createdAt,
  });

  bool get isVideo =>
      fileType == 'video' ||
      (videoUrl != null && videoUrl!.trim().isNotEmpty) ||
      fileUrl.contains('youtube.com') ||
      fileUrl.contains('youtu.be') ||
      fileUrl.contains('vimeo.com') ||
      fileUrl.endsWith('.mp4') ||
      fileUrl.endsWith('.mkv') ||
      fileUrl.endsWith('.webm');

  bool get isPdf =>
      fileType == 'pdf' ||
      fileType == 'worksheet' ||
      fileType == 'exam' ||
      fileName.toLowerCase().endsWith('.pdf') ||
      fileUrl.toLowerCase().endsWith('.pdf');

  /// Auto-extracts YouTube video thumbnail if no custom thumbnail provided
  String? get effectiveThumbnail {
    if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty) {
      return thumbnailUrl;
    }
    final urlToSearch = (videoUrl != null && videoUrl!.isNotEmpty) ? videoUrl! : fileUrl;
    return extractYoutubeThumbnail(urlToSearch);
  }

  static String? extractYoutubeThumbnail(String? url) {
    if (url == null || url.isEmpty) return null;
    final regExp = RegExp(
      r'(?:https?:\/\/)?(?:www\.)?(?:youtube\.com\/(?:[^\/\n\s]+\/\S+\/|(?:v|e(?:mbed)?)\/|\S*?[?&]v=)|youtu\.be\/)([a-zA-Z0-9_-]{11})',
      caseSensitive: false,
    );
    final match = regExp.firstMatch(url);
    if (match != null && match.groupCount >= 1) {
      final videoId = match.group(1);
      return 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
    }
    return null;
  }

  factory CourseResource.fromMap(Map<String, dynamic> map) {
    final vUrl = map['video_url'] as String?;
    final fUrl = map['file_url'] as String? ?? '';
    final fType = map['file_type'] as String? ?? ((vUrl != null && vUrl.isNotEmpty) ? 'video' : 'pdf');

    return CourseResource(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? 'Untitled Resource',
      description: map['description'] as String?,
      fileName: map['file_name'] as String? ?? ((fType == 'video') ? 'Video Lesson' : 'document.pdf'),
      fileUrl: fUrl,
      fileType: fType,
      fileSize: map['file_size'] as int?,
      videoUrl: vUrl,
      thumbnailUrl: map['thumbnail_url'] as String?,
      schoolId: map['school_id'] as String?,
      teacherId: map['teacher_id'] as String?,
      teacherName: map['teacher_name'] as String?,
      targetGrade: map['target_grade'] as String?,
      targetSection: map['target_section'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'file_name': fileName,
      'file_url': fileUrl,
      'file_type': fileType,
      'file_size': fileSize,
      'video_url': videoUrl,
      'thumbnail_url': thumbnailUrl,
      'school_id': schoolId,
      'teacher_id': teacherId,
      'teacher_name': teacherName,
      'target_grade': targetGrade,
      'target_section': targetSection,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
