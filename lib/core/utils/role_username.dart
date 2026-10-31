String roleUsername(String fullName, String role, {int? order}) {
  final words = fullName
      .trim()
      .split(RegExp(r'[^a-zA-Z0-9]+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.length < 2) return '';

  final name = words
      .map(
        (word) => '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join();
  final roleName = switch (role.toLowerCase()) {
    'admin' => 'Admin',
    'subadmin' || 'director' => 'Director',
    'teacher' => 'Teacher',
    _ => 'Student',
  };
  final suffix = (order != null && order > 0) ? '$order' : '';
  final truncatedName = name.length > 50 ? name.substring(0, 50) : name;
  return '$truncatedName$suffix@$roleName.edu';
}

/// Computes the next available username for [fullName] under [role],
/// handling overlapping/duplicate names by appending registration order numbers:
/// 1st: `FirstnameLastname@Student.edu`
/// 2nd: `FirstnameLastname1@Student.edu`
/// 3rd: `FirstnameLastname2@Student.edu`
String nextRoleUsername({
  required String fullName,
  required String role,
  required Iterable<String> existingUsernames,
}) {
  final baseUsername = roleUsername(fullName, role);
  if (baseUsername.isEmpty) return '';

  final parts = baseUsername.split('@');
  final baseName = parts[0];
  final domain = parts[1];

  final existingLower = existingUsernames
      .map((u) => u.trim().toLowerCase())
      .toSet();

  // If the base username is not yet taken in this role, use it:
  if (!existingLower.contains(baseUsername.toLowerCase()) &&
      !existingLower.contains('$baseName@students.edu'.toLowerCase())) {
    return baseUsername;
  }

  // Otherwise, assign sequential registration numbers 1, 2, 3...
  int counter = 1;
  while (true) {
    final candidate = '$baseName$counter@$domain';
    final altCandidate = '$baseName$counter@students.edu'.toLowerCase();
    if (!existingLower.contains(candidate.toLowerCase()) &&
        !existingLower.contains(altCandidate)) {
      return candidate;
    }
    counter++;
  }
}

bool isRoleUsername(String username, String role) {
  final clean = username.trim();
  final roleLower = role.toLowerCase();

  // Matches: CapitalizedNamePart(CapitalizedFatherName)+[Digits]@(Admin|Director|Teacher|Student|Students).edu
  final regex = RegExp(
    r'^[A-Z][a-z]*([A-Z][a-z]*)+(\d+)?@(Admin|Director|Teacher|Students?)\.edu$',
  );
  if (!regex.hasMatch(clean)) return false;

  final domain = clean.split('@').last;
  if (roleLower == 'admin') {
    return domain == 'Admin.edu';
  } else if (roleLower == 'subadmin' || roleLower == 'director') {
    return domain == 'Director.edu' || domain == 'Admin.edu';
  } else if (roleLower == 'teacher') {
    return domain == 'Teacher.edu';
  } else {
    return domain == 'Student.edu' || domain == 'Students.edu';
  }
}

String? roleFromUsername(String username) {
  final clean = username.trim();
  final regex = RegExp(
    r'^[A-Z][a-z]*([A-Z][a-z]*)+(\d+)?@(Admin|Director|Teacher|Students?)\.edu$',
  );
  if (!regex.hasMatch(clean)) {
    return null;
  }
  final domain = clean.split('@').last;
  return switch (domain) {
    'Admin.edu' => 'admin',
    'Director.edu' => 'subadmin',
    'Teacher.edu' => 'teacher',
    'Student.edu' || 'Students.edu' => 'student',
    _ => null,
  };
}

/// Returns the single-letter role initial ('A', 'D', 'T', or 'S') for passwords.
String roleLetter(String roleOrUsername) {
  final lower = roleOrUsername.toLowerCase();
  if (lower == 'admin' || lower.contains('@admin') || lower.endsWith('@a.edu')) {
    return 'A';
  }
  if (lower == 'subadmin' ||
      lower == 'director' ||
      lower.contains('@director') ||
      lower.endsWith('@d.edu')) {
    return 'D';
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
