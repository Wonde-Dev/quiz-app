import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_app/core/utils/validators.dart';

void main() {
  group('Validators.email', () {
    test('accepts a valid email with surrounding whitespace', () {
      expect(Validators.email('  learner@example.com  '), isNull);
    });

    test('rejects an invalid email', () {
      expect(Validators.email('learner@example'), 'Enter a valid email');
    });

    test('requires an email', () {
      expect(Validators.email('  '), 'Email is required');
    });
  });
}
