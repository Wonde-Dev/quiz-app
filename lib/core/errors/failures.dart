/// Application-wide error types.
class AppFailure implements Exception {
  final String message;
  final String? code;

  const AppFailure(this.message, {this.code});

  @override
  String toString() => 'AppFailure: $message';
}

class AuthFailure extends AppFailure {
  const AuthFailure(super.message, {super.code});
}

class NetworkFailure extends AppFailure {
  const NetworkFailure(super.message, {super.code});
}

class ServerFailure extends AppFailure {
  const ServerFailure(super.message, {super.code});
}

class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {super.code});
}

class PermissionFailure extends AppFailure {
  const PermissionFailure(super.message, {super.code});
}

class NotFoundFailure extends AppFailure {
  const NotFoundFailure(super.message, {super.code});
}