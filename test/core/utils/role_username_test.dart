import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/utils/role_username.dart';

void main() {
  group('roleUsername', () {
    test('joins first and last name and uses the full role suffix', () {
      expect(roleUsername('Wonde Assegid', 'admin'), 'WondeAssegid@Admin.edu');
      expect(
        roleUsername('Wonde Assegid', 'teacher'),
        'WondeAssegid@Teacher.edu',
      );
      expect(
        roleUsername('Wonde Assegid', 'student'),
        'WondeAssegid@Student.edu',
      );
    });

    test('rejects names without both first and last name', () {
      expect(roleUsername('Wonde', 'student'), isEmpty);
    });
  });

  group('isRoleUsername', () {
    test('only accepts the matching role suffix and required casing', () {
      expect(isRoleUsername('WondeAssegid@Admin.edu', 'admin'), isTrue);
      expect(isRoleUsername('WondeAssegid@Teacher.edu', 'teacher'), isTrue);
      expect(isRoleUsername('WondeAssegid@Student.edu', 'student'), isTrue);
      expect(isRoleUsername('WondeAssegid@Admin.edu', 'student'), isFalse);
      expect(isRoleUsername('Wondeassegid@Student.edu', 'student'), isFalse);
    });
  });

  group('roleFromUsername', () {
    test('detects the role suffix without a role picker', () {
      expect(roleFromUsername('WondeAssegid@Admin.edu'), 'admin');
      expect(roleFromUsername('WondeAssegid@Teacher.edu'), 'teacher');
      expect(roleFromUsername('WondeAssegid@Student.edu'), 'student');
    });

    test('rejects usernames that do not follow the required format', () {
      expect(roleFromUsername('wondeAssegid@Student.edu'), isNull);
      expect(roleFromUsername('WondeAssegid@teacher.edu'), isNull);
      expect(roleFromUsername('wonde@example.edu'), isNull);
    });
  });

  group('defaultRolePassword', () {
    test('generates expected default password matching user requirements', () {
      // User's exact prompt example:
      // "like for admin his username is WondeAdmin@Admin.edu so the password is gonna be WondeAdmin1@A.edu"
      expect(
        defaultRolePassword(usernameOrFullName: 'WondeAdmin@Admin.edu'),
        'WondeAdmin1@A.edu',
      );
      expect(
        defaultRolePassword(usernameOrFullName: 'WondeAdmin2@Admin.edu'),
        'WondeAdmin2@A.edu',
      );
      expect(
        defaultRolePassword(usernameOrFullName: 'JohnDoe@Student.edu'),
        'JohnDoe1@S.edu',
      );
      expect(
        defaultRolePassword(usernameOrFullName: 'JaneSmith@Teacher.edu'),
        'JaneSmith1@T.edu',
      );
      expect(
        defaultRolePassword(
          usernameOrFullName: 'Abebe Kebede',
          role: 'student',
        ),
        'AbebeKebede1@S.edu',
      );
    });
  });
}
