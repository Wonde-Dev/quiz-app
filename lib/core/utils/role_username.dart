String roleUsername(String fullName, String role) {
  final words = fullName
      .trim()
      .split(RegExp(r'[^a-zA-Z]+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.length < 2) return '';

  final name = words
      .map(
        (word) => '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join();
  final roleName = switch (role) {
    'admin' => 'Admin',
    'teacher' => 'Teacher',
    _ => 'Student',
  };
  return '${name.length > 50 ? name.substring(0, 50) : name}@$roleName.edu';
}

bool isRoleUsername(String username, String role) {
  final roleName = switch (role) {
    'admin' => 'Admin',
    'teacher' => 'Teacher',
    _ => 'Student',
  };
  return RegExp(r'^[A-Z][a-z]*([A-Z][a-z]*)+@(Admin|Teacher|Student)\.edu$')
          .hasMatch(username) &&
      username.endsWith('@$roleName.edu');
}

String? roleFromUsername(String username) {
  if (!RegExp(r'^[A-Z][a-z]*([A-Z][a-z]*)+@(Admin|Teacher|Student)\.edu$')
      .hasMatch(username)) {
    return null;
  }
  return switch (username.split('@').last) {
    'Admin.edu' => 'admin',
    'Teacher.edu' => 'teacher',
    'Student.edu' => 'student',
    _ => null,
  };
}

/// Returns the single-letter role initial ('A', 'T', or 'S') for passwords.
String roleLetter(String roleOrUsername) {
  final lower = roleOrUsername.toLowerCase();
  if (lower == 'admin' || lower.contains('@admin') || lower.endsWith('@a.edu')) {
    return 'A';
  }
  if (lower == 'teacher' || lower.contains('@teacher') || lower.endsWith('@t.edu')) {
    return 'T';
  }
  return 'S';
}

/// Generates the default or temporary password following the pattern:
/// `<NamePart><Order>@<RoleInitial>.edu`
/// Example: `WondeAdmin@Admin.edu` -> `WondeAdmin1@A.edu`
/// Example: `WondeAdmin2@Admin.edu` -> `WondeAdmin2@A.edu`
/// Example: `JohnDoe@Student.edu` -> `JohnDoe1@S.edu`
/// Example: `JaneSmith@Teacher.edu` -> `JaneSmith1@T.edu`
String defaultRolePassword({
  required String usernameOrFullName,
  String? role,
  int defaultOrder = 1,
}) {
  String baseName = '';
  int order = defaultOrder;

  if (usernameOrFullName.contains('@')) {
    final parts = usernameOrFullName.split('@');
    final namePart = parts.first;
    final match = RegExp(r'^(.*?)(\d+)$').firstMatch(namePart);
    if (match != null) {
      baseName = match.group(1) ?? namePart;
      order = int.tryParse(match.group(2) ?? '') ?? defaultOrder;
    } else {
      baseName = namePart;
    }
  } else {
    final words = usernameOrFullName
        .trim()
        .split(RegExp(r'[^a-zA-Z0-9]+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) {
      baseName = 'User';
    } else {
      baseName = words
          .map(
            (word) =>
                '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
          )
          .join();
    }
  }

  if (baseName.isEmpty) {
    baseName = 'User';
  }

  final letter = roleLetter(role ?? usernameOrFullName);
  return '$baseName$order@$letter.edu';
}
