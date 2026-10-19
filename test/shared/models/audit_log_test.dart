import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/shared/models/audit_log.dart';

void main() {
  test('parses activity rows without an authenticated actor', () {
    final log = AuditLog.fromMap({
      'id': 'log-id',
      'action': 'quiz_submitted',
      'performed_by': null,
      'target_user': 'student-id',
      'details': {'percentage': 80},
      'created_at': '2026-10-19T09:00:00.000Z',
    });

    expect(log.performedBy, isNull);
    expect(log.targetUser, 'student-id');
    expect(log.details?['percentage'], 80);
  });
}
