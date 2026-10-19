/// Represents a user of the application.
class AppUser {
  final String id;
  final String username;
  final String email;
  final String role; // admin, teacher, student
  final String? schoolId;
  final String? fullName;
  final String? avatarUrl;
  final bool mustChangePassword;
  final bool isActive;
  final String? requestedRole;
  final String approvalStatus;
  final DateTime createdAt;
  final DateTime? lastLogin;

  const AppUser({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    this.schoolId,
    this.fullName,
    this.avatarUrl,
    this.mustChangePassword = false,
    this.isActive = true,
    this.requestedRole,
    this.approvalStatus = 'approved',
    required this.createdAt,
    this.lastLogin,
  });

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: map['id'] as String,
      username: map['username'] as String? ?? '',
      email: map['email'] as String? ?? '',
      role: map['role'] as String,
      schoolId: map['school_id'] as String?,
      fullName: map['full_name'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      mustChangePassword: map['must_change_password'] as bool? ?? false,
      isActive: map['is_active'] as bool? ?? true,
      requestedRole: map['requested_role'] as String?,
      approvalStatus: map['approval_status'] as String? ?? 'approved',
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
      lastLogin: map['last_login'] != null
          ? DateTime.parse(map['last_login'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'role': role,
      'school_id': schoolId,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'must_change_password': mustChangePassword,
      'is_active': isActive,
      'requested_role': requestedRole,
      'approval_status': approvalStatus,
      'created_at': createdAt.toIso8601String(),
      'last_login': lastLogin?.toIso8601String(),
    };
  }

  AppUser copyWith({
    String? id,
    String? username,
    String? email,
    String? role,
    String? schoolId,
    String? fullName,
    String? avatarUrl,
    bool? mustChangePassword,
    bool? isActive,
    String? requestedRole,
    String? approvalStatus,
    DateTime? createdAt,
    DateTime? lastLogin,
  }) {
    return AppUser(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      role: role ?? this.role,
      schoolId: schoolId ?? this.schoolId,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      isActive: isActive ?? this.isActive,
      requestedRole: requestedRole ?? this.requestedRole,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      createdAt: createdAt ?? this.createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
    );
  }

  bool get isAdmin => role == 'admin';
  bool get isTeacher => role == 'teacher';
  bool get isStudent => role == 'student';
  bool get isPendingApproval => approvalStatus == 'pending';
  bool get isRejected => approvalStatus == 'rejected';
}
