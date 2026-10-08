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

  group('UciExtension', () {
    test('reads a UciCharPair from a two-character id', () {
      final out = pick(<String, dynamic>{'u': 'ab'}, 'u').asUciCharPairOrThrow();

      expect(out, UciCharPair.fromStringId('ab'));
      expect(out.toString(), 'ab');
    });

    test('a malformed id throws ArgumentError', () {
      expect(
        pick(<String, dynamic>{'u': 'abcd'}, 'u').asUciCharPairOrThrow,
        throwsA(isA<ArgumentError>()),
      );
    });

    test('asUciCharPairOrNull returns null instead of throwing', () {
      expect(pick(<String, dynamic>{'u': 'abcd'}, 'u').asUciCharPairOrNull(), isNull);
    });

    test('a missing key yields null from asUciCharPairOrNull', () {
      expect(pick(<String, dynamic>{}, 'u').asUciCharPairOrNull(), isNull);
    });

    test('reads a UciPath and keeps its value', () {
      final out = pick(<String, dynamic>{'p': 'e2e4d7d5'}, 'p').asUciPathOrThrow();

      expect(out, const UciPath('e2e4d7d5'));
    });

    test('an empty path is preserved rather than treated as absent', () {
      final out = pick(<String, dynamic>{'p': ''}, 'p').asUciPathOrNull();

      expect(out, UciPath.empty);
    });

    test('a missing key yields null from asUciPathOrNull', () {
      expect(pick(<String, dynamic>{}, 'p').asUciPathOrNull(), isNull);
    });
  });

  group('TimeExtension.asDateTimeFromMilliseconds', () {
    test('reads a DateTime from epoch milliseconds', () {
      final out = pick(<String, dynamic>{'at': 1700000000000}, 'at')
          .asDateTimeFromMillisecondsOrThrow();

      expect(out.millisecondsSinceEpoch, 1700000000000);
    });

    test('the epoch itself is accepted', () {
      final out = pick(<String, dynamic>{'at': 0}, 'at').asDateTimeFromMillisecondsOrThrow();

      expect(out.millisecondsSinceEpoch, 0);
    });

    test('passes an existing DateTime straight through', () {
      final at = DateTime.utc(2026, 1, 2, 3, 4, 5);

      expect(pick(<String, dynamic>{'at': at}, 'at').asDateTimeFromMillisecondsOrThrow(), at);
    });

    test('a non-numeric value throws a PickException', () {
      expect(
        pick(<String, dynamic>{'at': 'nope'}, 'at').asDateTimeFromMillisecondsOrThrow,
        throwsA(isA<PickException>()),
      );
    });

    test('asDateTimeFromMillisecondsOrNull swallows that failure', () {
      expect(
        pick(<String, dynamic>{'at': 'nope'}, 'at').asDateTimeFromMillisecondsOrNull(),
        isNull,
      );
    });

    test('a missing key yields null from the OrNull variant', () {
      expect(pick(<String, dynamic>{}, 'at').asDateTimeFromMillisecondsOrNull(), isNull);
    });
  });

  group('TimeExtension duration readers', () {
    test('whole minutes', () {
      final out = pick(<String, dynamic>{'d': 90}, 'd').asDurationFromMinutesOrThrow();

      expect(out, const Duration(minutes: 90));
    });

    test('whole seconds', () {
      final out = pick(<String, dynamic>{'d': 90}, 'd').asDurationFromSecondsOrThrow();

      expect(out, const Duration(seconds: 90));
    });

    test('a fractional number of seconds keeps sub-second precision', () {
      final out = pick(<String, dynamic>{'d': 1.5}, 'd').asDurationFromSecondsOrThrow();

      expect(out, const Duration(milliseconds: 1500));
    });

    test('centiseconds', () {
      final out = pick(<String, dynamic>{'d': 250}, 'd').asDurationFromCentiSecondsOrThrow();

      expect(out, const Duration(milliseconds: 2500));
    });

    test('milliseconds', () {
      final out = pick(<String, dynamic>{'d': 1234}, 'd').asDurationFromMilliSecondsOrThrow();

      expect(out, const Duration(milliseconds: 1234));
    });

    test('zero survives as zero rather than being read as absent', () {
      // A clock at exactly zero is a real value in exported games; the OrNull
      // variants must not collapse it to null.
      expect(pick(<String, dynamic>{'d': 0}, 'd').asDurationFromSecondsOrNull(), Duration.zero);
      expect(pick(<String, dynamic>{'d': 0}, 'd').asDurationFromMinutesOrNull(), Duration.zero);
    });

    test('an existing Duration passes straight through', () {
      const already = Duration(seconds: 42);

      expect(pick(<String, dynamic>{'d': already}, 'd').asDurationFromSecondsOrThrow(), already);
    });

    test('a wrong type returns null from every OrNull variant', () {
      final d = pick(<String, dynamic>{'d': 'nope'}, 'd');

      expect(d.asDurationFromMinutesOrNull(), isNull);
      expect(d.asDurationFromSecondsOrNull(), isNull);
      expect(d.asDurationFromCentiSecondsOrNull(), isNull);
      expect(d.asDurationFromMilliSecondsOrNull(), isNull);
    });

    test('a wrong type throws a PickException from the OrThrow variants', () {
      final d = pick(<String, dynamic>{'d': 'nope'}, 'd');

      expect(d.asDurationFromMinutesOrThrow, throwsA(isA<PickException>()));
      expect(d.asDurationFromSecondsOrThrow, throwsA(isA<PickException>()));
      expect(d.asDurationFromCentiSecondsOrThrow, throwsA(isA<PickException>()));
      expect(d.asDurationFromMilliSecondsOrThrow, throwsA(isA<PickException>()));
    });

    test('a missing key yields null rather than zero', () {
      final d = pick(<String, dynamic>{}, 'd');

      expect(d.asDurationFromMinutesOrNull(), isNull);
      expect(d.asDurationFromSecondsOrNull(), isNull);
      expect(d.asDurationFromCentiSecondsOrNull(), isNull);
      expect(d.asDurationFromMilliSecondsOrNull(), isNull);
    });
  });
}
