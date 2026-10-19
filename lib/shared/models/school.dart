/// Represents a school/institution.
class School {
  final String id;
  final String name;
  final String? address;
  final String? contactEmail;
  final DateTime createdAt;

  const School({
    required this.id,
    required this.name,
    this.address,
    this.contactEmail,
    required this.createdAt,
  });

  factory School.fromMap(Map<String, dynamic> map) {
    return School(
      id: map['id'] as String,
      name: map['name'] as String,
      address: map['address'] as String?,
      contactEmail: map['contact_email'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'contact_email': contactEmail,
      'created_at': createdAt.toIso8601String(),
    };
  }
}