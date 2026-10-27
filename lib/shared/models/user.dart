/// Represents a user of the application.
class AppUser {
  final String id;
  final String username;
  final String email;
  final String role; // admin, subadmin, teacher, student
  final String? schoolId;
  final String? sectionId;
  final String? fullName;
  final String? avatarUrl;
  final bool mustChangePassword;
  final bool isActive;
  final String? requestedRole;
  final String approvalStatus;
  final DateTime createdAt;
  final DateTime? lastLogin;

  // Additional role & assignment attributes
  final bool isSuperAdmin;
  final bool isAttendanceTeacher;
  final String? attendanceGrade; // e.g. 'Grade 9'
  final String? attendanceClass; // e.g. '9A' or 'Section A'
  final String? assignedGrade; // e.g. 'Grade 9'
  final String? assignedClass; // e.g. '9A'
  final String? assignedSubject; // e.g. 'Mathematics'

  const AppUser({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    this.schoolId,
    this.sectionId,
    this.fullName,
    this.avatarUrl,
    this.mustChangePassword = false,
    this.isActive = true,
    this.requestedRole,
    this.approvalStatus = 'approved',
    required this.createdAt,
    this.lastLogin,
    this.isSuperAdmin = false,
    this.isAttendanceTeacher = false,
    this.attendanceGrade,
    this.attendanceClass,
    this.assignedGrade,
    this.assignedClass,
    this.assignedSubject,
  });

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: map['id'] as String,
      username: map['username'] as String? ?? '',
      email: map['email'] as String? ?? '',
      role: map['role'] as String? ?? 'student',
      schoolId: map['school_id'] as String?,
      sectionId: map['section_id'] as String?,
      fullName: map['full_name'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      mustChangePassword: map['must_change_password'] as bool? ?? false,
      isActive: map['is_active'] as bool? ?? true,
      requestedRole: map['requested_role'] as String?,
      approvalStatus: map['approval_status'] as String? ?? 'approved',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      lastLogin: map['last_login'] != null
          ? DateTime.tryParse(map['last_login'] as String)
          : null,
      isSuperAdmin: map['is_super_admin'] as bool? ??
          (map['role'] == 'admin' &&
              ((map['email'] as String? ?? '').toLowerCase().contains('wonde') ||
                  (map['username'] as String? ?? '').toLowerCase().contains('wonde'))),
      isAttendanceTeacher: map['is_attendance_teacher'] as bool? ?? false,
      attendanceGrade: map['attendance_grade'] as String? ??
          map['requested_grade'] as String?,
      attendanceClass: map['attendance_class'] as String? ??
          map['requested_class'] as String?,
      assignedGrade: map['assigned_grade'] as String? ??
          map['requested_grade'] as String?,
      assignedClass: map['assigned_class'] as String? ??
          map['requested_class'] as String?,
      assignedSubject: map['assigned_subject'] as String? ??
          map['requested_subject'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'role': role,
      'school_id': schoolId,
      'section_id': sectionId,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'must_change_password': mustChangePassword,
      'is_active': isActive,
      'requested_role': requestedRole,
      'approval_status': approvalStatus,
      'created_at': createdAt.toIso8601String(),
      'last_login': lastLogin?.toIso8601String(),
      'is_super_admin': isSuperAdmin,
      'is_attendance_teacher': isAttendanceTeacher,
      'attendance_grade': attendanceGrade,
      'attendance_class': attendanceClass,
      'assigned_grade': assignedGrade,
      'assigned_class': assignedClass,
      'assigned_subject': assignedSubject,
    };
  }

  AppUser copyWith({
    String? id,
    String? username,
    String? email,
    String? role,
    String? schoolId,
    String? sectionId,
    String? fullName,
    String? avatarUrl,
    bool? mustChangePassword,
    bool? isActive,
    String? requestedRole,
    String? approvalStatus,
    DateTime? createdAt,
    DateTime? lastLogin,
    bool? isSuperAdmin,
    bool? isAttendanceTeacher,
    String? attendanceGrade,
    String? attendanceClass,
    String? assignedGrade,
    String? assignedClass,
    String? assignedSubject,
  }) {
    return AppUser(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      role: role ?? this.role,
      schoolId: schoolId ?? this.schoolId,
      sectionId: sectionId ?? this.sectionId,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      isActive: isActive ?? this.isActive,
      requestedRole: requestedRole ?? this.requestedRole,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      createdAt: createdAt ?? this.createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
      isSuperAdmin: isSuperAdmin ?? this.isSuperAdmin,
      isAttendanceTeacher: isAttendanceTeacher ?? this.isAttendanceTeacher,
      attendanceGrade: attendanceGrade ?? this.attendanceGrade,
      attendanceClass: attendanceClass ?? this.attendanceClass,
      assignedGrade: assignedGrade ?? this.assignedGrade,
      assignedClass: assignedClass ?? this.assignedClass,
      assignedSubject: assignedSubject ?? this.assignedSubject,
    );
  }

  /// Whether user has administrative rights (Main Admin or Sub-Admin / Director)
  bool get isAdmin => role == 'admin' || role == 'subadmin';

  /// Main Administrator (Super Admin) who cannot be deleted
  bool get isMainAdmin => isSuperAdmin || role == 'admin';

  /// Sub-Administrator / Director
  bool get isSubAdmin => role == 'subadmin';

  /// Teacher role
  bool get isTeacher => role == 'teacher';

  /// Student role
  bool get isStudent => role == 'student';

  bool get isPendingApproval => approvalStatus == 'pending';
  bool get isRejected => approvalStatus == 'rejected';

  /// Label for class e.g. "9A"
  String get classDisplayName {
    if (attendanceClass != null && attendanceClass!.isNotEmpty) {
      return attendanceClass!;
    }
    if (assignedClass != null && assignedClass!.isNotEmpty) {
      return assignedClass!;
    }
    return '';
  }

  bool canSignInWithRole(String selectedRole) {
    if (role == selectedRole) return true;
    if (isAdmin && (selectedRole == 'admin' || selectedRole == 'subadmin')) {
      return true;
    }
    return selectedRole == 'teacher' &&
        role == 'student' &&
        requestedRole == 'teacher' &&
        isPendingApproval;
  }
}
