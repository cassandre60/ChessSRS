// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Fast-path UTC ISO-8601 date parsing for repository row mappers.
library;

/// Parses an ISO-8601 UTC string formatted as `YYYY-MM-DDTHH:MM:SS[.mmm]Z`.
///
/// Falls back to standard [DateTime.parse] if the string does not match the
/// expected UTC layout.
DateTime parseUtcIso(String s) {
  // Fast path for 24-char format: "2026-10-14T12:00:00.000Z"
  // or 20-char format: "2026-10-14T12:00:00Z"
  if (s.endsWith('Z') && s.length >= 20 && s[10] == 'T') {
    try {
      final year = int.parse(s.substring(0, 4));
      final month = int.parse(s.substring(5, 7));
      final day = int.parse(s.substring(8, 10));
      final hour = int.parse(s.substring(11, 13));
      final minute = int.parse(s.substring(14, 16));
      final second = int.parse(s.substring(17, 19));
      var millis = 0;
      if (s.length >= 24 && s[19] == '.') {
        millis = int.parse(s.substring(20, 23));
      }
      return DateTime.utc(year, month, day, hour, minute, second, millis);
    } catch (_) {
      // Fallback on any unexpected integer format
    }
  }
  return DateTime.parse(s).toUtc();
}
