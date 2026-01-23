import 'package:test/test.dart';
import 'package:mdns_dart/src/utils.dart'; // Accessing internal public utils

void main() {
  group('Utils', () {
    group('trimDot', () {
      test('trims trailing dot', () {
        expect(trimDot('example.com.'), equals('example.com'));
      });

      test('trims leading dot', () {
        expect(trimDot('.example.com'), equals('example.com'));
      });

      test('trims both leading and trailing dots', () {
        expect(trimDot('.example.com.'), equals('example.com'));
      });

      test('handles string with no dots', () {
        expect(trimDot('example'), equals('example'));
      });

      test('handles empty string', () {
        expect(trimDot(''), equals(''));
      });

      test('handles string with only dots', () {
        expect(trimDot('...'), equals(''));
      });

      test('does not affect internal dots', () {
        expect(trimDot('a.b.c'), equals('a.b.c'));
      });
    });

    group('isValidFQDN', () {
      test('validates standard FQDN', () {
        expect(isValidFQDN('example.com.'), isTrue);
      });

      test('validates single label FQDN', () {
        expect(isValidFQDN('local.'), isTrue);
      });

      test('rejects missing trailing dot', () {
        expect(isValidFQDN('example.com'), isFalse);
      });

      test('rejects empty string', () {
        expect(isValidFQDN(''), isFalse);
      });

      test('rejects dot only', () {
        expect(isValidFQDN('.'),
            isFalse); // Implementation splits gives empty labels
      });

      test('rejects empty labels (consecutive dots)', () {
        expect(isValidFQDN('example..com.'), isFalse);
      });

      test('rejects invalid characters', () {
        expect(isValidFQDN('ex@mple.com.'), isFalse);
        expect(isValidFQDN('exa mple.com.'), isFalse);
      });

      test('rejects labels starting with hyphen', () {
        expect(isValidFQDN('-example.com.'), isFalse);
      });

      test('rejects labels ending with hyphen', () {
        expect(isValidFQDN('example-.com.'), isFalse);
      });

      test('rejects labels too long (>63 chars)', () {
        final longLabel = 'a' * 64;
        expect(isValidFQDN('$longLabel.com.'), isFalse);
      });

      test('accepts valid labels with hyphens', () {
        expect(isValidFQDN('my-printer.local.'), isTrue);
      });

      test('accepts alphanumeric labels', () {
        expect(isValidFQDN('printer123.local.'), isTrue);
      });
    });
  });
}
