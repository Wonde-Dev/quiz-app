String roleUsername(String fullName, String role) {
  final words = fullName
      .trim()
      .split(RegExp(r'[^a-zA-Z]+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.length < 2) return '';

  final name =
      '${words.first[0].toUpperCase()}'
      '${words.first.substring(1).toLowerCase()}'
      '${words.skip(1).map((word) => word.toLowerCase()).join()}';
  final suffix = switch (role) {
    'admin' => 'A',
    'teacher' => 'T',
    _ => 'S',
  };
  return '${name.length > 50 ? name.substring(0, 50) : name}@$suffix.edu';
}

bool isRoleUsername(String username, String role) {
  final suffix = switch (role) {
    'admin' => 'A',
    'teacher' => 'T',
    _ => 'S',
  };
  return RegExp(r'^[A-Z][a-z]{1,49}@[ATS]\.edu$').hasMatch(username) &&
      username.endsWith('@$suffix.edu');
}
