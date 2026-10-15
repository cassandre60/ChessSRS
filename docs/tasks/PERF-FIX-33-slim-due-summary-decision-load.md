# PERF-FIX-33 — Slim decision loading in due summary

## 1. Why this is a brief at all

Following the bulk study import feature (#131, #134), the owner's library grew
from **528 decisions** to **31,182 decisions** across 63 studies and 312 chapters.

At 31,182 decisions, `getDueSummary()` wall-clock time increased from ~20 ms to
**~512 ms**. Profiling the calls inside `getDueSummary()` reveals that one call
alone takes **186 ms** (66% of the SQL+mapping time):

```
getAllDecisions            186.22 ms  (66%)
```

### The root cause
`getAllDecisions()` executes:
```sql
SELECT * FROM srs_decision
```
and maps each row via `_decisionFromRow(row)`:
```dart
static RepertoireDecision _decisionFromRow(Map<String, Object?> row) {
  final rawMoves = row['expectedMoves']! as String;
  return RepertoireDecision(
    id: row['id']! as String,
    studyId: row['studyId']! as String,
    chapterId: row['chapterId']! as String,
    nodeId: row['nodeId']! as String,
    expectedMoves: decodeExpectedMoves(rawMoves),
    canonicalStateId: row['canonicalStateId'] as String?,
  );
}
```
`decodeExpectedMoves(rawMoves)` parses JSON-like string representations of move
lists into `List<RepertoireMove>` for all 31,182 decisions, allocating tens of
thousands of objects.

### What `_DueTally` actually uses
Inspect `_DueTally.add` in `lib/src/review/review_service.dart`:
```dart
void add(
  RepertoireDecision d, {
  ...
}) {
  final state = reviewStates[d.canonicalId] ?? reviewStates[d.id];
  ...
  studyTotals[d.studyId] = ...;
  chapterTotals[d.chapterId] = ...;
  ...
}
```
`_DueTally` **never reads `nodeId`** and **never reads `expectedMoves`**. It
only needs four fields:
1. `id` (String)
2. `studyId` (String)
3. `chapterId` (String)
4. `canonicalStateId` (String?, to derive `canonicalId = canonicalStateId ?? id`)

Selecting only those 4 columns without move decoding measures **~50 ms**
instead of 186 ms — saving **over 130 ms** on every review screen load.

## 2. Read before touching anything

1. `lib/src/review/review_service.dart` — `getDueSummary`, `_DueTally`, and
   `startSessionAndSummary`.
2. `lib/src/persistence/sqlite_study_repository.dart` — `getAllDecisions`,
   `_decisionFromRow`, and `srs_decision` queries.
3. `lib/src/domain/repertoire_decision.dart` — definition of `canonicalId`.
4. SPEC **INV-016** (transpositions share one memory), **INV-030** (scopes
   filter exactly), **INV-051** (bulk lookups stay bounded).
5. `AGENTS.md §3` — one worktree per task, commit locally, verify before
   pushing.

## 3. The Contract & Invariants

1. **Byte-identical summary output**: `getDueSummary` must produce the exact
   same `DueCountsSummary` object (total counts, per-study counts, per-chapter
   counts, opening counts, side progress).
2. **`startSession` is separate**: `startSession` actually needs full
   `RepertoireDecision` objects with `expectedMoves` for the review session
   engine to validate user moves. Only `getDueSummary` (and the summary half of
   `startSessionAndSummary` before handoff to session) can use the slim
   projection.
3. **No test deletion or weakening**: G08 watches for any loosened assertions.

## 4. Implementation Plan for Agent

### Step 1: Create a lightweight tally model or interface
In `lib/src/domain/repertoire_decision.dart` or `lib/src/review/review_service.dart`:
Define a lightweight record or class:
```dart
typedef TallyDecision = ({
  String id,
  String studyId,
  String chapterId,
  String canonicalId,
});
```
Or an abstract interface/base class if preferred to match repository style.
Note: `canonicalId` is computed as `canonicalStateId ?? id`.

### Step 2: Add repository method
In `lib/src/persistence/study_repository.dart` and
`lib/src/persistence/sqlite_study_repository.dart`:
Add:
```dart
Future<List<TallyDecision>> getTallyDecisions();
```
Querying:
```dart
final rows = await _db.query(
  kTableSrsDecision,
  columns: ['id', 'studyId', 'chapterId', 'canonicalStateId'],
);
return rows.map((r) {
  final id = r['id']! as String;
  final canonical = (r['canonicalStateId'] as String?) ?? id;
  return (
    id: id,
    studyId: r['studyId']! as String,
    chapterId: r['chapterId']! as String,
    canonicalId: canonical,
  );
}).toList(growable: false);
```

### Step 3: Update `_DueTally` and `getDueSummary`
Update `_DueTally.add` to accept `TallyDecision` (or keep a generic/overloaded
signature that works with both `RepertoireDecision` and `TallyDecision`).
In `ReviewService.getDueSummary`:
Call `repository.getTallyDecisions()` instead of `repository.getAllDecisions()`.

### Step 4: Verification
1. Run targeted tests:
   ```bash
   fvm flutter test test/review/review_service_test.dart
   ```
2. Measure before and after with the real library attribution harness:
   ```bash
   cp ~/.local/share/org.chesssrs.chess_srs/chess_srs.db{,-wal,-shm} /tmp/perf/
   CHESS_SRS_PERF_DB=/tmp/perf/chess_srs.db \
     fvm flutter test test/perf/due_summary_attribution_test.dart
   ```
3. Run static analysis:
   ```bash
   fvm flutter analyze lib/src/review/ lib/src/persistence/
   ```
4. Run gates:
   ```bash
   ./scripts/gates.sh t1
   ```

## 5. What counts as done

- `getDueSummary` uses the slim decision projection.
- `getAllDecisions()` is left intact for `startSession()`.
- Benchmark shows `getAllDecisions` / `getTallyDecisions` reduced from ~186 ms to < 60 ms.
- All existing tests in `test/review/review_service_test.dart` pass unmodified.
- `./scripts/gates.sh t1` passes after commit.

## 6. What would make this brief wrong

- If `_DueTally` is found to require `expectedMoves` or `nodeId` for any valid calculation
  (verify with `git grep -n "expectedMoves\|nodeId" lib/src/review/review_service.dart` inside `_DueTally`).
- If `getAllDecisions` is already avoided in `getDueSummary` on `origin/main`.
