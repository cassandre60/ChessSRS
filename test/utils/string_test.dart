import 'package:chess_srs/src/utils/string.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  group('genRandomString', () {
    test('returns empty string for length 0', () {
      expect(genRandomString(0), '');
    });

    test('returns base64url characters without padding', () {
      final value = genRandomString(16);
      expect(value, isNotEmpty);
      expect(value.contains('='), isFalse);
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value), isTrue);
    });

    test('produces different values across calls', () {
      final a = genRandomString(16);
      final b = genRandomString(16);
      expect(a, isNot(equals(b)));
    });
  });

  group('StringExtension.capitalize', () {
    test('capitalizes first character', () {
      expect('hello'.capitalize(), 'Hello');
    });

    test('keeps already capitalized string', () {
      expect('Hello'.capitalize(), 'Hello');
    });

    test('returns empty string unchanged', () {
      expect(''.capitalize(), '');
    });

    test('handles single character', () {
      expect('a'.capitalize(), 'A');
    });

    test('does not change rest of string', () {
      expect('hELLO'.capitalize(), 'HELLO');
    });
  });

  group('NumberLocalizationExtension.localizeNumbers', () {
    setUp(() {
      Intl.defaultLocale = 'en_US';
    });

    tearDown(() {
      Intl.defaultLocale = null;
    });

    test('formats integers using default NumberFormat', () {
      expect('1234'.localizeNumbers(), NumberFormat().format(1234));
    });

    test('formats decimal numbers', () {
      expect('12.5'.localizeNumbers(), NumberFormat().format(12.5));
    });

    test('localizes numbers inside text', () {
      expect('score 1000 points'.localizeNumbers(), 'score ${NumberFormat().format(1000)} points');
    });

    test('returns text unchanged when no numbers present', () {
      expect('hello'.localizeNumbers(), 'hello');
    });
  });
}
