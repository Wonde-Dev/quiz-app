import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_app/shared/models/school.dart';

class SchoolService {
  SchoolService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Fetches all registered schools, enriched with current teacher and student counts.
  Future<List<School>> getSchools() async {
    try {
      final schoolRows = await _client
          .from('schools')
          .select('id, name, code, address, city, phone, is_active, created_at')
          .order('name');

      final schools = List<Map<String, dynamic>>.from(schoolRows);

      // Attempt to load student/teacher counts per school
      Map<String, int> teacherCounts = {};
      Map<String, int> studentCounts = {};

      try {
        final users = await _client
            .from('users')
            .select('school_id, role')
            .not('school_id', 'is', null)
            .neq('is_active', false);

        for (final u in users) {
          final sId = u['school_id'] as String?;
          final role = u['role'] as String?;
          if (sId == null) continue;
          if (role == 'teacher') {
            teacherCounts[sId] = (teacherCounts[sId] ?? 0) + 1;
          } else if (role == 'student') {
            studentCounts[sId] = (studentCounts[sId] ?? 0) + 1;
          }
        }
      } catch (e) {
        debugPrint('School user count resolution note: $e');
      }

      return schools.map((row) {
        final id = row['id'] as String;
        final mutableRow = Map<String, dynamic>.from(row);
        mutableRow['teacher_count'] = teacherCounts[id] ?? 0;
        mutableRow['student_count'] = studentCounts[id] ?? 0;
        return School.fromMap(mutableRow);
      }).toList();
    } catch (e) {
      debugPrint('getSchools error: $e');
      // Minimal fallback to avoid UI blocking if network or schema cache glitch occurs
      return [];
    }
  }

  /// Creates a new school and provisions default Grades (9-12) and Sections (A, B, C).
  Future<School> createSchool({
    required String name,
    String? code,
    String? address,
    String? city,
    String? phone,
  }) async {
    final cleanName = name.trim();
    final cleanCode = code?.trim().toUpperCase();
    final cleanAddress = address?.trim();
    final cleanCity = city?.trim();
    final cleanPhone = phone?.trim();

    try {
      // 1. Try dedicated admin_create_school RPC
      final rpcRes = await _client.rpc(
        'admin_create_school',
        params: {
          'p_name': cleanName,
          'p_code': cleanCode,
          'p_address': cleanAddress,
          'p_city': cleanCity,
          'p_phone': cleanPhone,
        },
      );

      if (rpcRes is Map && rpcRes['success'] == true) {
        final schoolId = rpcRes['school_id'] as String;
        return School(
          id: schoolId,
          name: cleanName,
          code: cleanCode,
          address: cleanAddress,
          city: cleanCity,
          phone: cleanPhone,
          createdAt: DateTime.now(),
        );
      } else if (rpcRes is Map && rpcRes['error'] != null) {
        throw Exception(rpcRes['error'].toString());
      }
    } catch (e) {
      debugPrint('admin_create_school RPC fallback notice: $e');
    }

    // 2. Direct fallback table insert
    final inserted = await _client
        .from('schools')
        .insert({
          'name': cleanName,
          'code': cleanCode,
          'address': cleanAddress,
          'city': cleanCity,
          'phone': cleanPhone,
          'is_active': true,
        })
        .select()
        .single();

    final school = School.fromMap(inserted);

    // Auto-provision standard grades 9..12 & sections A, B, C for this new school
    try {
      for (int g = 9; g <= 12; g++) {
        final gradeRow = await _client
            .from('school_grades')
            .insert({'school_id': school.id, 'name': 'Grade $g'})
            .select()
            .single();

        final gradeId = gradeRow['id'] as String;
        for (final sec in ['A', 'B', 'C']) {
          await _client.from('sections').insert({
            'school_id': school.id,
            'grade_id': gradeId,
            'name': sec,
            'grade': 'Grade $g',
          });
        }
      }
    } catch (provisionErr) {
      debugPrint('Auto-provision grades note: $provisionErr');
    }

    return school;
  }

  /// Updates an existing school's information.
  Future<void> updateSchool({
    required String schoolId,
    String? name,
    String? code,
    String? address,
    String? city,
    String? phone,
    bool? isActive,
  }) async {
    final Map<String, dynamic> updates = {};
    if (name != null) updates['name'] = name.trim();
    if (code != null) updates['code'] = code.trim().toUpperCase();
    if (address != null) updates['address'] = address.trim();
    if (city != null) updates['city'] = city.trim();
    if (phone != null) updates['phone'] = phone.trim();
    if (isActive != null) updates['is_active'] = isActive;

    if (updates.isEmpty) return;

    await _client.from('schools').update(updates).eq('id', schoolId);
  }
}
