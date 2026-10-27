import 'package:chess_srs/src/model/common/time_increment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TimeIncrement Tests', () {
    test('Initialization', () {
      const timeIncrement = TimeIncrement(300, 5);
      expect(timeIncrement.time, 300);
      expect(timeIncrement.increment, 5);
    });

    test('JSON Serialization', () {
      final json = const TimeIncrement(300, 5).toJson();
      expect(json['time'], 300);
      expect(json['increment'], 5);

      final newTimeIncrement = TimeIncrement.fromJson(json);
      expect(newTimeIncrement.time, 300);
      expect(newTimeIncrement.increment, 5);
    });

    test('Display Strings', () {
      expect(const TimeIncrement(0, 0).display, '∞');
      expect(const TimeIncrement(0, 5).display, '0+5');
      expect(const TimeIncrement(45, 5).display, '¾+5');
      expect(const TimeIncrement(30, 5).display, '½+5');
      expect(const TimeIncrement(15, 5).display, '¼+5');
      expect(const TimeIncrement(90, 5).display, '1.5+5');
      expect(const TimeIncrement(600, 5).display, '10+5');
    });

    test('Estimated Duration', () {
      expect(const TimeIncrement(300, 5).estimatedDuration, const Duration(seconds: 300 + 5 * 40));
      expect(const TimeIncrement(0, 0).estimatedDuration, Duration.zero);
    });

    test('Equality and HashCode', () {
      const timeIncrement1 = TimeIncrement(300, 5);
      const timeIncrement2 = TimeIncrement(300, 5);
      const timeIncrement3 = TimeIncrement(600, 10);

      expect(timeIncrement1, timeIncrement2);
      expect(timeIncrement1.hashCode, timeIncrement2.hashCode);
      expect(timeIncrement1, isNot(timeIncrement3));
    });

    test('Rejects a negative initial time', () {
      const negativeTime = -1;
      expect(() => TimeIncrement(negativeTime, 5), throwsA(isA<AssertionError>()));
    });

    test('Rejects a negative increment', () {
      const negativeIncrement = -1;
      expect(() => TimeIncrement(300, negativeIncrement), throwsA(isA<AssertionError>()));
    });

    test('fromDurations accepts zero durations (the infinite clock)', () {
      final timeIncrement = TimeIncrement.fromDurations(Duration.zero, Duration.zero);

      expect(timeIncrement.time, 0);
      expect(timeIncrement.increment, 0);
      expect(timeIncrement.isInfinite, isTrue);
    });

    test('fromDurations rejects a negative initial duration', () {
      expect(
        () => TimeIncrement.fromDurations(const Duration(seconds: -1), Duration.zero),
        throwsA(isA<AssertionError>()),
      );
    });

    test('fromDurations rejects a negative increment duration', () {
      expect(
        () => TimeIncrement.fromDurations(const Duration(minutes: 5), const Duration(seconds: -1)),
        throwsA(isA<AssertionError>()),
      );
    });

    // Const instances with equal fields are canonicalized to a single object,
    // so `identical(this, other)` short-circuits and no field comparison runs
    // (same canonicalization trap as SPEC INV-026). Build both sides at
    // runtime so the field chain is what decides equality.
    test('Equality holds for runtime-equal, distinct instances', () {
      TimeIncrement build(int time, int increment) => TimeIncrement(time, increment);
      final a = build(300, 5);
      final b = build(300, 5);
      expect(identical(a, b), isFalse);
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('Equality requires the same runtime type', () {
      expect(const TimeIncrement(300, 5), isNot(const _SubTimeIncrement(300, 5)));
    });

    test('Equality distinguishes the initial time alone', () {
      expect(const TimeIncrement(300, 5), isNot(const TimeIncrement(600, 5)));
    });

    test('Equality distinguishes the increment alone', () {
      expect(const TimeIncrement(300, 5), isNot(const TimeIncrement(300, 10)));
    });

    test('clockLabelInMinutes Function', () {
      expect(clockLabelInMinutes(0), '0');
      expect(clockLabelInMinutes(45), '¾');
      expect(clockLabelInMinutes(30), '½');
      expect(clockLabelInMinutes(15), '¼');
      expect(clockLabelInMinutes(60), '1');
      expect(clockLabelInMinutes(90), '1.5');
      expect(clockLabelInMinutes(600), '10');
    });
  });
}

/// A subclass with equal fields, used to prove equality is type-sensitive.
class _SubTimeIncrement extends TimeIncrement {
  const _SubTimeIncrement(super.time, super.increment);
}
