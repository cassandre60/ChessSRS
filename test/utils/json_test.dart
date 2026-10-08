import 'dart:ui' show Locale;

import 'package:chess_srs/src/model/common/uci.dart';
import 'package:chess_srs/src/utils/json.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:flutter_test/flutter_test.dart';

// Every statement here is deliberately kept on one line: there is no Dart
// toolchain in the environment this was written in, so the file cannot be run
// through `dart format` locally. Single-line statements under the 100-column
// page width are the one shape the formatter provably leaves alone.

/// Reads a field that is not an int, so the mapper itself throws.
int? _intField(Map<String, dynamic> m) => m['n'] as int;

void main() {
  group('decodeObjectList', () {
    test('maps every element of a JSON list', () {
      final json = <Object?>[<String, dynamic>{'n': 1}, <String, dynamic>{'n': 2}];
      final out = decodeObjectList<int>(json, mapper: (m) => m['n'] as int);

      expect(out.toList(), [1, 2]);
    });

    test('drops the elements a mapper returns null for', () {
      final json = <Object?>[<String, dynamic>{'n': 1}, <String, dynamic>{'n': null}];
      final out = decodeObjectList<int?>(json, mapper: (m) => m['n'] as int?);

      expect(out.toList(), [1]);
    });

    test('an empty list decodes to an empty result', () {
      final out = decodeObjectList<int>(<Object?>[], mapper: (m) => m['n'] as int);

      expect(out, isEmpty);
    });

    test('a single element is handled the same as many', () {
      final json = <Object?>[<String, dynamic>{'n': 7}];
      final out = decodeObjectList<int>(json, mapper: (m) => m['n'] as int);

      expect(out.toList(), [7]);
    });

    test('a non-list input throws', () {
      final json = <String, dynamic>{'n': 1};

      expect(() => decodeObjectList<int>(json, mapper: (m) => 1), throwsA(isA<Exception>()));
    });

    test('null input throws rather than decoding to empty', () {
      expect(() => decodeObjectList<int>(null, mapper: (m) => 1), throwsA(isA<Exception>()));
    });

    test('an element that is not an object throws', () {
      final json = <Object?>[1, 2];

      expect(() => decodeObjectList<int>(json, mapper: (m) => 1), throwsA(isA<Exception>()));
    });

    test('a mapper that throws is rethrown wrapped as an Exception', () {
      final json = <Object?>[<String, dynamic>{'n': 'not an int'}];

      expect(() => decodeObjectList<int>(json, mapper: _intField), throwsA(isA<Exception>()));
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

    test('round-trips a locale carrying a script', () {
      const locale = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');

      expect(converter.fromJson(converter.toJson(locale)), locale);
    });

    test('round-trips a locale carrying a script and a country', () {
      const locale = Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN');

      expect(converter.fromJson(converter.toJson(locale)), locale);
    });

    test('a language-only locale serialises null country and script', () {
      final out = converter.toJson(const Locale('de'));

      expect(out, isNotNull);
      expect(out!['languageCode'], 'de');
      expect(out['countryCode'], isNull);
      expect(out['scriptCode'], isNull);
    });

    test('fromJson throws when languageCode is missing', () {
      // Suspected bug: json['languageCode'] as String throws a TypeError on a
      // map that omits the key. Every sibling field is read as nullable, so a
      // truncated payload fails here instead of degrading gracefully.
      final json = <String, dynamic>{'countryCode': 'FR'};

      expect(() => converter.fromJson(json), throwsA(isA<TypeError>()));
    });
  });

  group('UciExtension', () {
    test('reads a UciCharPair from a two-character id', () {
      final out = pick(<String, dynamic>{'u': 'ab'}, 'u').asUciCharPairOrThrow();

      expect(out, UciCharPair.fromStringId('ab'));
      expect(out.toString(), 'ab');
    });

    test('a malformed id throws ArgumentError', () {
      final p = pick(<String, dynamic>{'u': 'abcd'}, 'u');

      expect(p.asUciCharPairOrThrow, throwsA(isA<ArgumentError>()));
    });

    test('asUciCharPairOrNull returns null instead of throwing', () {
      final p = pick(<String, dynamic>{'u': 'abcd'}, 'u');

      expect(p.asUciCharPairOrNull(), isNull);
    });

    test('a missing key yields null from asUciCharPairOrNull', () {
      final p = pick(<String, dynamic>{}, 'u');

      expect(p.asUciCharPairOrNull(), isNull);
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
      final p = pick(<String, dynamic>{}, 'p');

      expect(p.asUciPathOrNull(), isNull);
    });
  });

  group('TimeExtension.asDateTimeFromMilliseconds', () {
    test('reads a DateTime from epoch milliseconds', () {
      final p = pick(<String, dynamic>{'at': 1700000000000}, 'at');
      final out = p.asDateTimeFromMillisecondsOrThrow();

      expect(out.millisecondsSinceEpoch, 1700000000000);
    });

    test('the epoch itself is accepted', () {
      final out = pick(<String, dynamic>{'at': 0}, 'at').asDateTimeFromMillisecondsOrThrow();

      expect(out.millisecondsSinceEpoch, 0);
    });

    test('passes an existing DateTime straight through', () {
      final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
      final p = pick(<String, dynamic>{'at': at}, 'at');

      expect(p.asDateTimeFromMillisecondsOrThrow(), at);
    });

    test('a non-numeric value throws a PickException', () {
      final p = pick(<String, dynamic>{'at': 'nope'}, 'at');

      expect(p.asDateTimeFromMillisecondsOrThrow, throwsA(isA<PickException>()));
    });

    test('asDateTimeFromMillisecondsOrNull swallows that failure', () {
      final p = pick(<String, dynamic>{'at': 'nope'}, 'at');

      expect(p.asDateTimeFromMillisecondsOrNull(), isNull);
    });

    test('a missing key yields null from the OrNull variant', () {
      final p = pick(<String, dynamic>{}, 'at');

      expect(p.asDateTimeFromMillisecondsOrNull(), isNull);
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

    test('zero seconds survives as zero rather than being read as absent', () {
      // A clock at exactly zero is a real value in exported games; the OrNull
      // variants must not collapse it to null.
      final s = pick(<String, dynamic>{'d': 0}, 'd');
      final m = pick(<String, dynamic>{'d': 0}, 'd');

      expect(s.asDurationFromSecondsOrNull(), Duration.zero);
      expect(m.asDurationFromMinutesOrNull(), Duration.zero);
    });

    test('an existing Duration passes straight through', () {
      const already = Duration(seconds: 42);
      final p = pick(<String, dynamic>{'d': already}, 'd');

      expect(p.asDurationFromSecondsOrThrow(), already);
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
