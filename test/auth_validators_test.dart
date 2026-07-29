import 'package:explorer_os_mobile/features/auth/auth_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateEmail', () {
    test('rejects empty + malformed, accepts valid', () {
      expect(validateEmail(''), isNotNull);
      expect(validateEmail('nope'), isNotNull);
      expect(validateEmail('a@b'), isNotNull);
      expect(validateEmail('dev@exploreros.app'), isNull);
      expect(validateEmail('  dev@exploreros.app  '), isNull);
    });
  });

  group('validatePassword', () {
    test('requires >= 8 chars', () {
      expect(validatePassword(''), isNotNull);
      expect(validatePassword('short'), isNotNull);
      expect(validatePassword('ExplorerOS123!'), isNull);
    });
  });

  group('validateConfirmPassword', () {
    test('must match', () {
      expect(validateConfirmPassword('abc12345', ''), isNotNull);
      expect(validateConfirmPassword('abc12345', 'different'), isNotNull);
      expect(validateConfirmPassword('abc12345', 'abc12345'), isNull);
    });
  });

  group('validateRequired', () {
    test('flags blanks', () {
      expect(validateRequired('', 'first name'), isNotNull);
      expect(validateRequired('  ', 'first name'), isNotNull);
      expect(validateRequired('Ada', 'first name'), isNull);
    });
  });

  group('friendlyAuthError', () {
    test('maps common errors to friendly text', () {
      expect(friendlyAuthError(Exception('Invalid login credentials')),
          contains('Incorrect email'));
      expect(friendlyAuthError(Exception('User already registered')),
          contains('already exists'));
      expect(friendlyAuthError(Exception('Email not confirmed')),
          contains('confirm your email'));
      expect(friendlyAuthError(Exception('SocketException: failed host')),
          contains('Network error'));
      expect(friendlyAuthError(Exception('weird')), contains('went wrong'));
    });
  });
}
