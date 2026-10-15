# PERF-FIX-38 — Inverted differential due-summary tallying

## 1. Why this is a brief at all

In `ReviewService.getDueSummary`, after database loading, Dart iterates through
every decision in the library to populate `_DueTally`:

```dart
for (final d in loadedData.allDecisions) {
  tally.add(
    d,
    reviewStates: loadedData.reviewStates,
    now: now,
    ...
  );
}
```

On a library with 31,182 decisions, iterating this loop 31,182 times in Dart
allocates map lookups, checks scope filters, and accumulates totals on every
single run.

### The observation
In an SRS database:
- Total decisions: **31,182**
- Learned/reviewed decisions: **~427**
- Unreviewed decisions: **~30,755**

Over 98% of the decisions in the database have **no review state** (`state == null`).
For every unreviewed decision:
- `isLearned` is always `false`.
- `isDue` is always `true` (`state == null || state.isDueAt(now)`).
- Its contribution to `studyTotals`, `chapterTotals`, and `sideTotals` is static
  and fixed when the study is imported!

## 2. Read before touching anything

1. `lib/src/review/review_service.dart` — `_DueTally`, `getDueSummary`.
2. SPEC **INV-016** (transpositions share one memory; canonical IDs deduplicate
   due counts across studies).
3. SPEC **INV-030** (scopes filter exactly).

## 3. The Mathematical / Architectural Solution

### Insight: Static Structural Totals vs Dynamic Review State
The structural totals:
- `studyTotals` (how many total decisions each study contains)
- `chapterTotals` (how many total decisions each chapter contains)
- `sideTotals` (total decisions per side)
- `studySideTotals` (total decisions per study and side)

These are **static repertoire properties**. They do not change when a user
answers a review card! They only change when a study is imported, modified, or
deleted.

### Dynamic Counts:
Only two things change when a user reviews cards or as time passes:
1. Which items are learned (`repetitionCount > 0`).
2. Which items are due at `now` (`isDueAt(now)`).

Because only ~427 items exist in `srs_review_state` / `position_knowledge_state`:
Instead of iterating 31,182 decisions every time `getDueSummary` runs:
1. **Cache or pre-aggregate the static structural counts**:
   `SELECT studyId, chapterId, COUNT(*) FROM srs_decision GROUP BY studyId, chapterId`
   gives all chapter and study totals in 1 fast indexed SQL query (~2 ms).
2. **Only evaluate the dynamic entries (the ~427 reviewed states)**:
   For reviewed states, adjust the learned counts and due counts.
3. For deduplication of due canonical IDs (INV-016):
   Only decisions that share a canonical ID (in the grown library, 77 decisions)
   need deduplication tracking.

## 4. Implementation Steps for Agent

1. Add a test in `test/review/review_service_test.dart` verifying that the
   inverted/cached tally produces byte-for-byte identical `DueCountsSummary`
   metrics across all scopes (`all()`, `white()`, `black()`, `study()`, `opening()`).
2. Implement structural totals caching or SQL `GROUP BY` pre-aggregation in
   `SqliteStudyRepository`.
3. In `_DueTally`, evaluate dynamic review states rather than looping 31,182
   times.
4. Verify with the fingerprint test in `test/perf/due_summary_attribution_test.dart`.

## 5. What counts as done

- In-memory tally time drops from ~40 ms to < 1 ms.
- Output of `getDueSummary` remains 100% byte-identical.
- All existing tests in `review_service_test.dart` pass.
- `./scripts/gates.sh t1` passes.
