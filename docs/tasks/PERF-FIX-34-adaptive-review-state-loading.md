# PERF-FIX-34 — Eliminate pathological multi-query chunking in review state loading

## 1. Why this is a brief at all

In `ReviewService._loadReviewData`, review states and knowledge states are
fetched for all in-scope decisions:

```dart
final decisionIds = allDecisions.map((d) => d.id).toList();
final canonicalIds = allDecisions.map((d) => d.canonicalId).toSet().toList();
final allQueryIds = {...decisionIds, ...canonicalIds}.toList();
final reviewStatesList = await repository.getReviewStatesByIds(allQueryIds);
final reviewStates = {for (final s in reviewStatesList) s.decisionId: s};
final kStates = await repository.getKnowledgeStatesByCanonicalIds(canonicalIds);
```

Both `getReviewStatesByIds` and `getKnowledgeStatesByCanonicalIds` chunk their
input IDs at **400 items per query** (`IN (?, ?, ...)` with 400 parameters):

```dart
const chunkSize = 400;
for (var i = 0; i < ids.length; i += chunkSize) {
  final chunk = ids.sublist(i, i + chunkSize > ids.length ? ids.length : i + chunkSize);
  final placeholders = List.filled(chunk.length, '?').join(',');
  ...
}
```

### The pathology
On the owner's library with 31,182 decisions:
- `allQueryIds` contains **~32,000 IDs**
- `canonicalIds` contains **25,102 IDs**
- `getReviewStatesByIds` executes **80 sequential SQLite queries**!
- `getKnowledgeStatesByCanonicalIds` executes **63 sequential SQLite queries**!
- That is **143 sequential database queries** over FFI.

Meanwhile, the actual tables contain:
- `srs_review_state`: **427 rows**
- `position_knowledge_state`: **349 rows**

The app is executing **143 database queries with 400 parameters each** just to
locate ~400 rows across two tiny tables! This costs **~80–120 ms** of pure query
orchestration and FFI driver overhead.

## 2. Read before touching anything

1. `lib/src/review/review_service.dart` — `_loadReviewData`, `getDueSummary`,
   `startSessionAndSummary`.
2. `lib/src/persistence/sqlite_study_repository.dart` — `getReviewStatesByIds`
   and `getKnowledgeStatesByCanonicalIds`.
3. `test/review/review_service_test.dart` — line 312:
   `test('getDueSummary reads review state by the ids it counts, not the whole table')`.
4. SPEC **INV-051**:
   > Review-state reads and deletes are chunked (400-item SQLite batches) and the
   > due queue prefetches in bounded batches with refill thresholds, so startup
   > and session build do not deserialize the whole database.

## 3. The Invariant & The Challenge

`INV-051` exists to ensure that when a user starts or inspects a *scoped* review
session (e.g. 1 study with 50 decisions), the system does not load thousands of
unrelated review states from disk.

However, when `_loadReviewData` is called for the **whole library** (31,182
decisions), or when `ids.length` is far larger than the total number of rows in
the table, executing 143 chunked queries violates the spirit of performance and
saturates the SQLite driver.

Furthermore:
In `SqliteStudyRepository`:
- `getAllReviewStates()` loads the entire table and merges canonical states.
- But notice: `test/review/review_service_test.dart` has a guard test:
  `_FullTableReadRepository` verifies that `getAllReviewStates()` is not
  called when counting a scoped study.

## 4. Implementation Options for Agent

### Option A: Threshold-based adaptive query (Recommended)
In `getReviewStatesByIds(List<String> ids)` and
`getKnowledgeStatesByCanonicalIds(List<String> ids)`:
If `ids.length <= 400` (or `<= 800`), use the chunked `IN` queries as today
(preserving INV-051 for scoped lookups).

If `ids.length > 800` (or `ids.length >= kLargeQueryThreshold`):
Instead of 80 chunked queries of 400 parameters:
Query the table directly (`SELECT * FROM srs_review_state`), filtering in memory
against a `Set<String>` of the requested IDs:
```dart
if (ids.length > 800) {
  final idSet = ids.toSet();
  final rows = await _db.query(kTableSrsReviewState);
  return rows
      .where((r) => idSet.contains(r['decisionId'] as String))
      .map(_reviewStateFromRow)
      .toList(growable: false);
}
```
**Why this works:**
- If the table has 427 rows, `_db.query()` fetches 427 rows in **1 query** (~1 ms)
  and filters against `idSet` in microseconds.
- Compare: 1 query taking 1.5 ms vs 80 queries taking 45 ms.
- For small `ids` (e.g. 20 decisions in a chapter), it still does 1 chunked
  query and does NOT load the full table, keeping `INV-051` test completely green!

### Option B: Dedicated `getAllReviewStatesMap()` / Slim state loader for `getDueSummary`
For `getDueSummary()`, since it always needs all active review states across the
library, load the state map directly using a slim projection (see PERF-FIX-33/35)
rather than deriving 32,000 query IDs and chunking them.

## 5. Verification Steps

1. Verify INV-051 test passes:
   ```bash
   fvm flutter test test/review/review_service_test.dart --plain-name "getDueSummary reads review state by the ids it counts"
   ```
2. Verify all review tests pass:
   ```bash
   fvm flutter test test/review/review_service_test.dart
   ```
3. Run attribution test on real library copy:
   ```bash
   cp ~/.local/share/org.chesssrs.chess_srs/chess_srs.db{,-wal,-shm} /tmp/perf/
   CHESS_SRS_PERF_DB=/tmp/perf/chess_srs.db \
     fvm flutter test test/perf/due_summary_attribution_test.dart
   ```
   Verify `getKnowledgeStates` and `getReviewStatesByIds` times drop from
   ~80 ms to < 5 ms.

## 6. What counts as done

- Number of SQLite queries for whole-library review state loading reduced from 143 to ≤ 4.
- Scoped lookups (`ids.length <= 400`) still use bounded chunked queries per INV-051.
- All tests in `test/review/review_service_test.dart` pass unmodified.
- `./scripts/gates.sh t1` passes.
