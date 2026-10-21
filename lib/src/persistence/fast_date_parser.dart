// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Fast-path UTC ISO-8601 date parsing for repository row mappers.
library;

/// Parses an ISO-8601 UTC string formatted as `YYYY-MM-DDTHH:MM:SS[.mmm]Z`.
///
/// Falls back to standard [DateTime.parse] if the string does not match the
/// expected UTC layout.
DateTime parseUtcIso(String s) {
  // Fast path for the two layouts this function documents: "2026-10-14T12:00:00Z"
  // (20 chars) and "2026-10-14T12:00:00.000Z" (24 chars).
  //
  // Only those two. The fast path reads fixed offsets and nothing else, so a
  // string it half-understands — an offset suffix, a longer fractional part, a
  // stray character where the milliseconds are — would be read as a different
  // instant than the same string means to [DateTime.parse]. The fast path is a
  // shortcut, not a second interpretation: wherever it cannot read the whole
  // string, [DateTime.parse] owns it.
  final hasMillis = s.length == 24 && s[19] == '.';
  if (s.endsWith('Z') && (s.length == 20 || hasMillis) && s[10] == 'T') {
    try {
      final year = int.parse(s.substring(0, 4));
      final month = int.parse(s.substring(5, 7));
      final day = int.parse(s.substring(8, 10));
      final hour = int.parse(s.substring(11, 13));
      final minute = int.parse(s.substring(14, 16));
      final second = int.parse(s.substring(17, 19));
      var millis = 0;
      if (hasMillis) {
        millis = int.parse(s.substring(20, 23));
      }
      return DateTime.utc(year, month, day, hour, minute, second, millis);
    } catch (_) {
      // Fallback on any unexpected integer format
    }
  }
  return DateTime.parse(s).toUtc();
}
