import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/utils/role_username.dart';

void main() {
  group('roleUsername', () {
    test('joins first and last name and uses the role letter', () {
      expect(roleUsername('Wonde Assegid', 'admin'), 'Wondeassegid@A.edu');
      expect(roleUsername('Wonde Assegid', 'teacher'), 'Wondeassegid@T.edu');
      expect(roleUsername('Wonde Assegid', 'student'), 'Wondeassegid@S.edu');
    });

    test('rejects names without both first and last name', () {
      expect(roleUsername('Wonde', 'student'), isEmpty);
    });
  });

  group('isRoleUsername', () {
    test('only accepts the matching role suffix and required casing', () {
      expect(isRoleUsername('Wondeassegid@A.edu', 'admin'), isTrue);
      expect(isRoleUsername('Wondeassegid@A.edu', 'student'), isFalse);
      expect(isRoleUsername('WondeAssegid@S.edu', 'student'), isFalse);
      expect(isRoleUsername('Wondeassegid@S.edu', 'student'), isTrue);
    });
  });
}
