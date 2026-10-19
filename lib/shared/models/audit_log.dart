/// Represents an activity log entry.
class AuditLog {
  final String id;
  final String action;
  final String? performedBy;
  final String? targetUser;
  final Map<String, dynamic>? details;
  final String? ipAddress;
  final String? userAgent;
  final DateTime createdAt;

  const AuditLog({
    required this.id,
    required this.action,
    required this.performedBy,
    this.targetUser,
    this.details,
    this.ipAddress,
    this.userAgent,
    required this.createdAt,
  });

  factory AuditLog.fromMap(Map<String, dynamic> map) {
    return AuditLog(
      id: map['id'] as String,
      action: map['action'] as String,
      performedBy: map['performed_by'] as String?,
      targetUser: map['target_user'] as String?,
      details: map['details'] as Map<String, dynamic>?,
      ipAddress: map['ip_address'] as String?,
      userAgent: map['user_agent'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'action': action,
      'performed_by': performedBy,
      'target_user': targetUser,
      'details': details,
      'ip_address': ipAddress,
      'user_agent': userAgent,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
