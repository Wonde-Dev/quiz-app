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
