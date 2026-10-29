/// Represents a school or branch institution in the system.
class School {
  final String id;
  final String name;
  final String? code;
  final String? address;
  final String? city;
  final String? phone;
  final bool isActive;
  final DateTime createdAt;
  final int teacherCount;
  final int studentCount;

  const School({
    required this.id,
    required this.name,
    this.code,
    this.address,
    this.city,
    this.phone,
    this.isActive = true,
    required this.createdAt,
    this.teacherCount = 0,
    this.studentCount = 0,
  });

  factory School.fromMap(Map<String, dynamic> map) {
    return School(
      id: map['id'] as String,
      name: map['name'] as String? ?? 'Unnamed School',
      code: map['code'] as String?,
      address: map['address'] as String?,
      city: map['city'] as String?,
      phone: map['phone'] as String?,
      isActive: map['is_active'] as bool? ?? true,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      teacherCount: (map['teacher_count'] as num?)?.toInt() ?? 0,
      studentCount: (map['student_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'address': address,
      'city': city,
      'phone': phone,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }

  School copyWith({
    String? id,
    String? name,
    String? code,
    String? address,
    String? city,
    String? phone,
    bool? isActive,
    DateTime? createdAt,
    int? teacherCount,
    int? studentCount,
  }) {
    return School(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      address: address ?? this.address,
      city: city ?? this.city,
      phone: phone ?? this.phone,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      teacherCount: teacherCount ?? this.teacherCount,
      studentCount: studentCount ?? this.studentCount,
    );
  }
}
