# PERF-FIX-35 — Fast UTC ISO-8601 date parsing for repository row mappers

## 1. Why this is a brief at all

In `SqliteStudyRepository`, row mappers for `ReviewState` and
`PositionKnowledgeState` convert ISO-8601 timestamp strings from SQLite columns
into Dart `DateTime` instances:

```dart
static ReviewState _reviewStateFromRow(Map<String, Object?> row) {
  final first = row['firstReviewedAt'] as String?;
  final last = row['lastReviewedAt'] as String?;
  final next = row['nextDueAt'] as String?;

  return ReviewState(
    decisionId: (row['canonicalId'] ?? row['decisionId'])! as String,
    firstReviewedAt: first != null ? DateTime.parse(first).toUtc() : null,
    lastReviewedAt: last != null ? DateTime.parse(last).toUtc() : null,
    nextDueAt: next != null ? DateTime.parse(next).toUtc() : null,
    ...
  );
}
```

### The cost of `DateTime.parse` on real FFI strings
Standard Dart `DateTime.parse()` is a general-purpose parser that handles
arbitrary time zones, signs, fractional seconds, and offsets.

On freshly allocated strings crossing the FFI boundary, each call to
`DateTime.parse()` takes **~5 to 6 µs**.
- For 427 `ReviewState` rows × 3 dates = **1,281 parses**
- For 349 `PositionKnowledgeState` rows × 4 dates = **1,396 parses**
- Total: **~2,600 parses = ~14–16 ms** spent purely in string parsing during a
  full state load.

### Two key observations
1. **In `getDueSummary()`, 75% of these parses are thrown away:**
   `_DueTally.add` only checks `state.isDueAt(now)` (which only reads `nextDueAt`)
   and `state.repetitionCount > 0` (an integer). `firstReviewedAt`,
   `lastReviewedAt`, and `lastExposedAt` are completely unused by `_DueTally`!
2. **All timestamps stored in this database are strict UTC strings:**
   Every write in `sqlite_study_repository.dart` formats dates using:
   `dateTime.toUtc().toIso8601String()`.
   The format is strictly: `YYYY-MM-DDTHH:MM:SS.mmmZ` (24 chars) or
   `YYYY-MM-DDTHH:MM:SSZ` (20 chars).

## 2. Read before touching anything

1. `lib/src/persistence/sqlite_study_repository.dart` — `_reviewStateFromRow`,
   `_knowledgeStateFromRow`, and row insertion queries.
2. `lib/src/domain/review_state.dart` — `ReviewState.isDueAt`.
3. `test/perf/due_summary_attribution_test.dart` — date parsing benchmarks.
4. SPEC **INV-041**:
   > Scheduling and review paths take time only through Clock.

## 3. Implementation Plan for Agent

### Part A: Avoid parsing unused dates in summary paths (Composes with PERF-FIX-33/34)
When loading states specifically for due count summaries (or if using a slim
state representation):
Only parse `nextDueAt`. Leave other dates null or omitted in the summary tally.

### Part B: Dedicated fast-path UTC ISO-8601 parser
Write a fast-path parser in a helper file, e.g.
`lib/src/persistence/fast_date_parser.dart`:

```dart
/// Parses an ISO-8601 UTC string formatted as `YYYY-MM-DDTHH:MM:SS[.mmm]Z`.
///
/// Falls back to standard [DateTime.parse] if the string does not match the
/// expected 20-character or 24-character UTC layout.
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
      // Fallback on any unexpected structure
    }
  }
  return DateTime.parse(s).toUtc();
}
```

### Verification & Correctness Contract
1. **Unit tests for parser**:
   Add a unit test verifying `parseUtcIso` gives byte-for-byte identical results
   to `DateTime.parse(s).toUtc()` for:
   - Dates with milliseconds (`2026-10-14T12:34:56.789Z`)
   - Dates without milliseconds (`2026-10-14T12:34:56Z`)
   - Leap years (`2024-02-29T00:00:00.000Z`)
   - Century boundaries, midnight, end-of-year
   - Fallback on non-standard strings (offsets like `+02:00`, lowercase `z`, etc.)
2. **Benchmark**:
   Measure `parseUtcIso` against `DateTime.parse`. Expected: 4–6x faster
   (~1 µs vs ~6 µs).
3. **Run repository tests**:
   ```bash
   fvm flutter test test/persistence/sqlite_study_repository_test.dart
   ```

## 4. What counts as done

- `parseUtcIso` implemented with full unit test coverage and equivalence tests against `DateTime.parse`.
- Row mappers in `sqlite_study_repository.dart` use `parseUtcIso`.
- Zero regressions across existing persistence and review tests.
- `./scripts/gates.sh t1` passes.
