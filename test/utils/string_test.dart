import 'package:chess_srs/src/utils/string.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  group('genRandomString', () {
    test('produces a different value on each call', () {
      expect(genRandomString(16), isNot(equals(genRandomString(16))));
    });

    test('length follows the requested byte count', () {
      // base64url of 3 bytes is exactly 4 characters; of 6 bytes, 8.
      expect(genRandomString(3).length, 4);
      expect(genRandomString(6).length, 8);
    });

    test('emits only base64url characters', () {
      final value = genRandomString(32);

      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value), isTrue);
    });

    test('zero length yields the empty string', () {
      expect(genRandomString(0), isEmpty);
    });

    test('negative length is rejected', () {
      expect(() => genRandomString(-1), throwsRangeError);
    });
  });

  group('StringExtension.capitalize', () {
    test('upper-cases the first character and leaves the rest untouched', () {
      expect('hello'.capitalize(), 'Hello');
      expect('Hello'.capitalize(), 'Hello');
      expect('hELLO wORLD'.capitalize(), 'HELLO wORLD');
    });

    test('handles a single character', () {
      expect('a'.capitalize(), 'A');
    });

    test('does not change a leading non-letter', () {
      expect('1abc'.capitalize(), '1abc');
      expect(' élan'.capitalize(), ' élan');
    });

    test('preserves the rest of a unicode string', () {
      expect('école'.capitalize(), 'École');
    });

    test('empty string throws', () {
      // Suspected bug: this[0] on an empty string is a RangeError rather than
      // returning ''. Nothing in lib/ calls capitalize today, so it is latent.
      expect(() => ''.capitalize(), throwsRangeError);
    });
  });

  group('NumberLocalizationExtension.localizeNumbers', () {
    // NumberFormat() falls back to the default locale, so pin it: without this
    // the grouping separator depends on the host environment.
    setUpAll(() {
      Intl.defaultLocale = 'en_US';
    });

    test('leaves a string with no digits unchanged', () {
      expect('no digits here'.localizeNumbers(), 'no digits here');
    });

    test('groups a four-digit number', () {
      expect('1234'.localizeNumbers(), '1,234');
    });

    test('leaves a number below the grouping threshold alone', () {
      expect('42'.localizeNumbers(), '42');
    });

    test('groups the integer part of a decimal and keeps the fraction', () {
      expect('1234.5'.localizeNumbers(), '1,234.5');
    });

    test('handles several numbers in one string', () {
      expect('1000 and 2000'.localizeNumbers(), '1,000 and 2,000');
    });

    test('preserves surrounding text and punctuation', () {
      expect('Score: 12345!'.localizeNumbers(), 'Score: 12,345!');
    });

    test('keeps exactly three fraction digits', () {
      expect('1234.999'.localizeNumbers(), '1,234.999');
    });

    test('a longer fraction is rounded away, so this is lossy', () {
      // NumberFormat's default is 3 fraction digits. Pinned because callers hand
      // it user-visible strings: 1234.9999 comes back as 1,235.
      expect('1234.9999'.localizeNumbers(), '1,235');
    });

    test('an empty string stays empty', () {
      expect(''.localizeNumbers(), isEmpty);
    });
  });
}
