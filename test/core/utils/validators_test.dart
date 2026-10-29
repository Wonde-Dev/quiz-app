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

  group('Validators.phone', () {
    test('accepts valid international and local phone numbers', () {
      expect(Validators.phone('+251 91 123 4567'), isNull);
      expect(Validators.phone('0911234567'), isNull);
      expect(Validators.phone('+1 (555) 123-4567'), isNull);
    });

    test('rejects short or invalid phone numbers', () {
      expect(Validators.phone('12345'), isNotNull);
      expect(Validators.phone('phone12345'), isNotNull);
      expect(Validators.phone(''), 'Phone number is required');
    });
  });
}
