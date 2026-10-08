import 'dart:ui' show Locale;

import 'package:chess_srs/src/model/common/uci.dart';
import 'package:chess_srs/src/utils/json.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decodeObjectList', () {
    test('maps every element of a JSON list', () {
      final json = <Object?>[
        <String, dynamic>{'n': 1},
        <String, dynamic>{'n': 2},
        <String, dynamic>{'n': 3},
      ];

      final out = decodeObjectList<int>(json, mapper: (m) => m['n'] as int);

      expect(out.toList(), [1, 2, 3]);
    });

    test('drops the elements a mapper returns null for', () {
      final json = <Object?>[
        <String, dynamic>{'n': 1},
        <String, dynamic>{'n': null},
        <String, dynamic>{'n': 3},
      ];

      final out = decodeObjectList<int?>(json, mapper: (m) => m['n'] as int?);

      expect(out.toList(), [1, 3]);
    });

    test('an empty list decodes to an empty result', () {
      final out = decodeObjectList<int>(<Object?>[], mapper: (m) => m['n'] as int);

      expect(out, isEmpty);
    });

    test('a single element is handled the same as many', () {
      final out = decodeObjectList<int>(
        <Object?>[<String, dynamic>{'n': 7}],
        mapper: (m) => m['n'] as int,
      );

      expect(out.toList(), [7]);
    });

    test('a non-list input throws', () {
      expect(
        () => decodeObjectList<int>(<String, dynamic>{'n': 1}, mapper: (m) => m['n'] as int),
        throwsA(isA<Exception>()),
      );
    });

    test('null input throws rather than decoding to empty', () {
      expect(
        () => decodeObjectList<int>(null, mapper: (m) => m['n'] as int),
        throwsA(isA<Exception>()),
      );
    });

    test('an element that is not an object throws', () {
      expect(
        () => decodeObjectList<int>(<Object?>[1, 2], mapper: (m) => m['n'] as int),
        throwsA(isA<Exception>()),
      );
    });

    test('a mapper that throws is rethrown wrapped as an Exception', () {
      final json = <Object?>[<String, dynamic>{'n': 'not an int'}];

      expect(
        () => decodeObjectList<int>(json, mapper: (m) => m['n'] as int),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('LocaleConverter', () {
    const converter = LocaleConverter();

    test('fromJson returns null for null', () {
      expect(converter.fromJson(null), isNull);
    });

    test('toJson returns null for a null locale', () {
      expect(converter.toJson(null), isNull);
    });

    test('round-trips a language-only locale', () {
      const locale = Locale('fr');

      expect(converter.fromJson(converter.toJson(locale)), locale);
    });

    test('round-trips a locale carrying a script and a country', () {
      const locale = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN');

      expect(converter.fromJson(converter.toJson(locale)), locale);
    });

    test('a language-only locale serialises null country and script', () {
      final expected = <String, dynamic>{
        'languageCode': 'de',
        'countryCode': null,
        'scriptCode': null,
      };

      expect(converter.toJson(const Locale('de')), expected);
    });

    test('fromJson throws when languageCode is missing', () {
      // Suspected bug: json['languageCode'] as String throws a TypeError on a
      // map that omits the key. Every other field is read as nullable, so a
      // truncated payload fails here instead of degrading gracefully.
      expect(
        () => converter.fromJson(<String, dynamic>{'countryCode': 'FR'}),
        throwsA(isA<TypeError>()),
      );
    });
  });

}
