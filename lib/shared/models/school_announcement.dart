class SchoolAnnouncement {
  final String id;
  final String schoolId;
  final String authorId;
  final String authorName;
  final String authorRole;
  final String title;
  final String content;
  final String targetAudience;
  final bool isPinned;
  final DateTime createdAt;

  const SchoolAnnouncement({
    required this.id,
    required this.schoolId,
    required this.authorId,
    required this.authorName,
    required this.authorRole,
    required this.title,
    required this.content,
    required this.targetAudience,
    required this.isPinned,
    required this.createdAt,
  });

  factory SchoolAnnouncement.fromJson(Map<String, dynamic> json) {
    return SchoolAnnouncement(
      id: json['id'] as String? ?? '',
      schoolId: json['school_id'] as String? ?? '00000000-0000-4000-8000-000000000001',
      authorId: json['author_id'] as String? ?? '',
      authorName: json['author_name'] as String? ?? 'Director',
      authorRole: json['author_role'] as String? ?? 'Director',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      targetAudience: json['target_audience'] as String? ?? 'all',
      isPinned: json['is_pinned'] == true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'school_id': schoolId,
      'author_id': authorId,
      'author_name': authorName,
      'author_role': authorRole,
      'title': title,
      'content': content,
      'target_audience': targetAudience,
      'is_pinned': isPinned,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
