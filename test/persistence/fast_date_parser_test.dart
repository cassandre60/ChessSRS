// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/persistence/fast_date_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseUtcIso', () {
    // SPEC INV-002. PERF-FIX-35: fast-path UTC ISO-8601 parsing equivalent to DateTime.parse.
    test('parses 24-character UTC ISO timestamp with milliseconds', () {
      const input = '2026-10-14T12:34:56.789Z';
      final parsed = parseUtcIso(input);
      final expected = DateTime.parse(input).toUtc();
      expect(parsed, expected);
      expect(parsed.isUtc, isTrue);
      expect(parsed.year, 2026);
      expect(parsed.month, 10);
      expect(parsed.day, 14);
      expect(parsed.hour, 12);
      expect(parsed.minute, 34);
      expect(parsed.second, 56);
      expect(parsed.millisecond, 789);
    });

    test('parses 20-character UTC ISO timestamp without milliseconds', () {
      const input = '2026-10-14T12:34:56Z';
      final parsed = parseUtcIso(input);
      final expected = DateTime.parse(input).toUtc();
      expect(parsed, expected);
      expect(parsed.isUtc, isTrue);
      expect(parsed.millisecond, 0);
    });

    test('parses leap day timestamp', () {
      const input = '2024-02-29T00:00:00.000Z';
      final parsed = parseUtcIso(input);
      final expected = DateTime.parse(input).toUtc();
      expect(parsed, expected);
      expect(parsed.year, 2024);
      expect(parsed.month, 2);
      expect(parsed.day, 29);
    });

    test('parses midnight and end-of-year boundaries', () {
      const midnight = '2025-01-01T00:00:00.000Z';
      expect(parseUtcIso(midnight), DateTime.parse(midnight).toUtc());

      const endOfYear = '2025-12-31T23:59:59.999Z';
      expect(parseUtcIso(endOfYear), DateTime.parse(endOfYear).toUtc());
    });

    test('falls back correctly on non-standard formats with offsets or space separators', () {
      const withOffset = '2026-10-14T14:34:56+02:00';
      expect(parseUtcIso(withOffset), DateTime.parse(withOffset).toUtc());

      const withSpace = '2026-10-14 12:34:56.000Z';
      expect(parseUtcIso(withSpace), DateTime.parse(withSpace).toUtc());

      const plainDate = '2026-10-14';
      expect(parseUtcIso(plainDate), DateTime.parse(plainDate).toUtc());
    });
  });
}
