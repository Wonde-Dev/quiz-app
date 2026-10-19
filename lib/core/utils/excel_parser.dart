// Parses Excel files (.xlsx) for bulk student registration.
// Uses the `excel` package to read rows.
import 'dart:typed_data';

import 'package:excel/excel.dart';

/// Parses student data from an Excel file's bytes.
/// Expected columns: username, full_name, email (optional), password (optional)
/// Returns a list of maps with keys: username, full_name, email, password.
List<Map<String, dynamic>> parseStudentExcel(Uint8List bytes) {
  final excel = Excel.decodeBytes(bytes);
  final students = <Map<String, dynamic>>[];

  for (final table in excel.tables.values) {
    final rows = table.rows;
    if (rows.isEmpty) continue;

    // Find header row (first row)
    final headerRow = rows.first;
    final headers = headerRow
        .map((cell) => cell?.value?.toString().toLowerCase().trim() ?? '')
        .toList();

    int usernameIdx = headers.indexWhere((h) => h.contains('user'));
    int nameIdx = headers.indexWhere((h) => h.contains('name'));
    int emailIdx = headers.indexWhere((h) => h.contains('email'));
    int passwordIdx = headers.indexWhere((h) => h.contains('pass'));

    if (usernameIdx == -1) usernameIdx = 0;
    if (nameIdx == -1) nameIdx = 1;
    if (emailIdx == -1) emailIdx = 2;
    if (passwordIdx == -1) passwordIdx = 3;

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;

      final username = row.length > usernameIdx
          ? row[usernameIdx]?.value?.toString().trim() ?? ''
          : '';
      if (username.isEmpty) continue;

      students.add({
        'username': username,
        'full_name': row.length > nameIdx
            ? row[nameIdx]?.value?.toString().trim() ?? ''
            : '',
        'email': row.length > emailIdx
            ? row[emailIdx]?.value?.toString().trim() ?? ''
            : '',
        'password': row.length > passwordIdx
            ? row[passwordIdx]?.value?.toString().trim() ?? ''
            : '',
      });
    }
  }

  return students;
}
