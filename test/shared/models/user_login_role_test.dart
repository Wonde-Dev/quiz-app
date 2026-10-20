import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/shared/models/user.dart';

AppUser user({
  String role = 'student',
  String? requestedRole,
  String approvalStatus = 'approved',
}) {
  return AppUser(
    id: 'user-id',
    username: 'WondeAssegid@Student.edu',
    email: 'wonde@example.com',
    role: role,
    requestedRole: requestedRole,
    approvalStatus: approvalStatus,
    createdAt: DateTime(2026),
  );
}

void main() {
  group('AppUser.canSignInWithRole', () {
    test('allows the assigned role only', () {
      expect(user().canSignInWithRole('student'), isTrue);
      expect(user().canSignInWithRole('teacher'), isFalse);
      expect(user().canSignInWithRole('admin'), isFalse);
    });

    test(
      'allows a pending teacher applicant into their current student role',
      () {
        final applicant = user(
          requestedRole: 'teacher',
          approvalStatus: 'pending',
        );
        expect(applicant.canSignInWithRole('teacher'), isTrue);
        expect(applicant.canSignInWithRole('student'), isTrue);
        expect(applicant.canSignInWithRole('admin'), isFalse);
      },
    );

    test('does not allow rejected teacher requests as a teacher', () {
      final rejected = user(
        requestedRole: 'teacher',
        approvalStatus: 'rejected',
      );
      expect(rejected.canSignInWithRole('teacher'), isFalse);
      expect(rejected.canSignInWithRole('student'), isTrue);
    });

    test('requires an assigned admin role for admin sign-in', () {
      expect(user(role: 'admin').canSignInWithRole('admin'), isTrue);
      expect(
        user(
          requestedRole: 'admin',
          approvalStatus: 'pending',
        ).canSignInWithRole('admin'),
        isFalse,
      );
    });
  });
}
