import 'package:chess_srs/src/domain/clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('utcDayKey', () {
    test('returns yyyyMMdd for a UTC instant', () {
      expect(utcDayKey(DateTime.utc(2026, 11, 14, 3, 4, 5)), 20261114);
      expect(utcDayKey(DateTime.utc(2024, 1, 2, 23, 59, 59)), 20240102);
    });

    test('uses UTC day for non-UTC instants', () {
      // 2026-11-14 01:00 in UTC+02 is 2026-11-13 23:00 UTC.
      final instant = DateTime.parse('2026-11-14T01:00:00+02:00');
      expect(utcDayKey(instant), 20261113);
    });
  });

  group('SystemClock', () {
    test('now returns current system time', () {
      final before = DateTime.now();
      final now = const SystemClock().now();
      final after = DateTime.now();
      expect(
        now.isAfter(before.subtract(const Duration(seconds: 1))) || now.isAtSameMomentAs(before),
        isTrue,
      );
      expect(
        now.isBefore(after.add(const Duration(seconds: 1))) || now.isAtSameMomentAs(after),
        isTrue,
      );
    });

    test('localDayKey uses the reader local day of the instant', () {
      const clock = SystemClock();
      final instant = DateTime.utc(2026, 11, 14, 12, 30);
      final local = instant.toLocal();
      final expected = local.year * 10000 + local.month * 100 + local.day;
      expect(clock.localDayKey(instant), expected);
    });
  });

  group('FixedClock', () {
    test('now returns the fixed value', () {
      final value = DateTime.utc(2026, 11, 14, 10);
      final clock = FixedClock(value);
      expect(clock.now(), same(value));
    });

    test('advance moves the clock forward', () {
      final clock = FixedClock(DateTime.utc(2026, 11, 14, 10));
      clock.advance(const Duration(hours: 2, minutes: 30));
      expect(clock.now(), DateTime.utc(2026, 11, 14, 12, 30));
    });

    test('localDayKey returns the UTC day key', () {
      final clock = FixedClock(DateTime.utc(2026, 11, 14, 10));
      final instant = DateTime.parse('2026-11-14T01:00:00+02:00');
      expect(clock.localDayKey(instant), utcDayKey(instant));
      expect(clock.localDayKey(instant), 20261113);
    });
  });
}
