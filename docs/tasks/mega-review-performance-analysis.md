# Performance & Scalability Analysis — ChessSRS

**Date**: 2026-11-17  
**Scope**: Full codebase, all performance-critical paths  
**Reference library**: 63 studies, 312 chapters, 33,784 decisions, 71,359 `srs_node` rows, 34 MiB  
**Existing measurements**: `docs/performance-handoff.md` §9–§13

> [!IMPORTANT]
> This is an **analysis** document with proposals; none of these changes have been
> measured or benchmarked. Per the performance-handoff's rules, every hypothesis
> here must be **measured before acting on it**. Some of the existing
> measurements already refute directions that look plausible; those are noted
> explicitly.

---

## Table of Contents

1. [Session Start Latency](#1-session-start-latency)
2. [Move Response Path (INV-050)](#2-move-response-path-inv-050)
3. [SQLite Query Analysis](#3-sqlite-query-analysis)
4. [Memory Allocation Hotspots](#4-memory-allocation-hotspots)
5. [Widget Rebuild Analysis](#5-widget-rebuild-analysis)
6. [Import / PGN Parsing](#6-import--pgn-parsing)
7. [Lazy Loading Opportunities](#7-lazy-loading-opportunities)
8. [Build-Time Analysis](#8-build-time-analysis)
9. [Summary Priority Table](#9-summary-priority-table)

---

## 1. Session Start Latency

### Current state

Measured at §13 of `performance-handoff.md` (2026-11-05, 33.8K decisions):

| Config | Median |
|---|---|
| whole-library `startSession()` | 1077 ms |
| `loadSessionAndSummary()` | 1369 ms |
| owner config (`transposeScope: off`) | 487 ms → **138 ms** (after fix) |
| `transposeScope: inScope` | 490 ms |
| `repo.getNodeIndex(active chapters)` | 376 ms |

The node-index skip for `transposeScope: off` already landed (`e95eae93b`).

### Remaining bottlenecks (transposeScope: inScope)

**Finding 1-A: Three separate `srs_chapter` queries for metadata**

[review_service.dart#L981-L983](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/review/review_service.dart#L981-L983) in `loadSessionAndSummary()`:

```dart
final chapterOpenings = await repository.getChapterOpenings();        // SELECT id, opening FROM srs_chapter
final chapterSides = await repository.getChapterOrientations();       // SELECT id, orientation FROM srs_chapter
final chapterStudyIds = await repository.getChapterStudyIds();        // SELECT id, studyId FROM srs_chapter
```

Three full-table scans of `srs_chapter` for three separate column projections. At 312 chapters this is ~3 round-trips over FFI for work that is a single `SELECT id, opening, orientation, studyId FROM srs_chapter`.

- **Estimated impact**: ~1–3 ms saved (small), but it's a no-risk change.
- **Priority**: 🟢 Quick win
- **Proposal**: Add `getChapterMetadata()` returning all three maps from one query:

```dart
Future<({Map<String, String?> openings, Map<String, Side> orientations, Map<String, String> studyIds})>
    getChapterMetadata() async {
  final rows = await _db.query(kTableSrsChapter, columns: ['id', 'opening', 'orientation', 'studyId']);
  final openings = <String, String?>{};
  final orientations = <String, Side>{};
  final studyIds = <String, String>{};
  for (final r in rows) {
    final id = r['id']! as String;
    openings[id] = r['opening'] as String?;
    orientations[id] = (r['orientation'] as String?) == 'black' ? Side.black : Side.white;
    studyIds[id] = r['studyId']! as String;
  }
  return (openings: openings, orientations: orientations, studyIds: studyIds);
}
```

**Finding 1-B: `getDueSummary()` standalone path duplicates these three queries**

[review_service.dart#L1099-L1101](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/review/review_service.dart#L1099-L1101) — same three queries again, not shared with `loadSessionAndSummary`.

- **Priority**: 🟢 Quick win (same fix as 1-A)

**Finding 1-C: `loadSessionAndSummary` wide-scope double-reads decisions**

For wide scopes, [review_service.dart#L1027-L1033](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/review/review_service.dart#L1027-L1033):

```dart
final allDecisions = wideScope ? await repository.getAllDecisions() : null;
final List<TallyDecision> tallyDecisions = allDecisions != null
    ? [for (final d in allDecisions) (id: d.id, ...)]  // O(31K) allocation
    : await repository.getTallyDecisions();
```

When `allDecisions` is loaded, the code creates 31K TallyDecision tuples from the already-loaded RepertoireDecision list. This is correct (it avoids a second query), but the intermediate TallyDecision list is an unnecessary copy. The tally loop could iterate `allDecisions` directly with a simple adapter.

- **Estimated impact**: ~5–15 ms (31K allocations saved)
- **Priority**: 🟢 Quick win
- **Proposal**: Accept `Iterable<TallyDecision>` from a view/adapter instead of materializing a full list.

**Finding 1-D: Node index load dominates `inScope` sessions**

§13 measured `getNodeIndex(active chapters)` at 376 ms. The query maps 71K rows from `srs_node`. With `transposeScope: inScope` (the default), this is unavoidable per current design. Options already recorded in §13:

- Lazy per-chapter loading (decode chapter tree only on first transposition hit)
- Background indexing with progressive decode during think-time

These are **Major refactor** territory and require their own brief. No new finding.

- **Priority**: 🔴 Major refactor (already identified)

---

## 2. Move Response Path (INV-050)

INV-050 requires legality + lookup + grading + persistence in <16 ms. The oracle is `test/review/move_latency_test.dart`.

### Trace: `ReviewService.submitMove()`

[review_service.dart#L843-L896](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/review/review_service.dart#L843-L896):

1. `session.submitMove()` — in-memory: position lookup, grading, state update. **Pure computation, expected <1 ms.**
2. `PositionKnowledgeState.fromReviewState()` + `.copyWith()` — object construction. **<0.1 ms.**
3. `repository.saveAnswerBatch()` — single DB transaction:
   - Upsert `position_knowledge_state` (1 row)
   - Insert-or-replace `srs_review_state` for canonical id
   - `INSERT OR REPLACE INTO srs_review_state ... SELECT id FROM srs_decision WHERE canonicalStateId = ?` — per-occurrence mirrors
   - Insert `srs_review_event` (1 row)
4. Optional: `repository.unlockDecisions()` — batch insert

**Finding 2-A: `exposureThrottle` getter copies the entire map on every move**

[review_session.dart#L664](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/domain/review/review_session.dart#L664):
```dart
Map<String, DateTime> get exposureThrottle => _coordinator.snapshotExposureThrottle();
```

[graph_aware_review_coordinator.dart#L146](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/domain/graph_aware_review_coordinator.dart#L146):
```dart
Map<String, DateTime> snapshotExposureThrottle() => Map<String, DateTime>.of(_lastExposedAt);
```

This copies the entire exposure map (up to ~500 entries for in-scope items) on every `submitMove` call. The comment at line 924 says "the getter copies the throttle map, so calling it per element would copy it once per side effect" — but it's already called once in `submitMove` and the copy is used only for single-key lookups.

- **Estimated impact**: ~0.1–0.5 ms per move (87 entries × ~20B = small but measurable in a 16 ms budget)
- **Priority**: 🟢 Quick win
- **Proposal**: Add a `getExposureTime(String canonicalId)` method that reads directly from the coordinator's internal map without copying:

```dart
DateTime? getExposureTimeFor(String canonicalId) => _lastExposedAt[canonicalId];
```

**Finding 2-B: Per-occurrence mirror write in `saveAnswerBatch`**

[sqlite_study_repository.dart#L986-L1006](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/persistence/sqlite_study_repository.dart#L986-L1006):

The `INSERT OR REPLACE INTO srs_review_state ... SELECT id FROM srs_decision WHERE canonicalStateId = ?` runs a subquery per knowledge state. For a typical position with 1–3 transpositions this is fast, but a highly-transposed position (e.g., a common opening tabia with 10+ occurrences) would generate 10+ INSERT statements in one batch.

The mirror write is **deliberate** (documented rationale at line 953–965). The question is whether the SELECT can be avoided by caching the decision→canonical mapping. This requires careful measurement first.

- **Estimated impact**: ~0.5–2 ms for multi-transposition positions
- **Priority**: 🟡 Medium effort (need to measure the actual transposition distribution)

**Finding 2-C: Review event JSON encoding on the move path**

[sqlite_study_repository.dart#L1530-L1531](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/persistence/sqlite_study_repository.dart#L1530-L1531):

```dart
'oldStateJson': jsonEncode(reviewStateToJson(event.oldState)),
'newStateJson': jsonEncode(reviewStateToJson(event.newState)),
```

Two `jsonEncode` calls on the move-critical path. Each encodes a ReviewState with 8 fields. The JSON is small (<200 bytes), so encoding itself is fast, but it's work inside the 16 ms budget.

- **Estimated impact**: ~0.1–0.3 ms (probably noise)
- **Priority**: ⚪ Probably noise — measure before acting

---

## 3. SQLite Query Analysis

### Index coverage

[srs_schema.dart](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/persistence/srs_schema.dart) defines these indexes:

| Table | Indexed columns | Coverage |
|---|---|---|
| `srs_study` | `pgnHash` | ✅ Adequate |
| `srs_study_remote` | `remoteStudyId` | ✅ |
| `srs_chapter` | `studyId` | ✅ |
| `srs_decision` | `studyId`, `chapterId`, `canonicalStateId` | ✅ |
| `position_knowledge_state` | `nextDueAt` | ⚠️ See 3-A |
| `srs_review_state` | `nextDueAt` | ⚠️ See 3-A |
| `srs_review_event` | `decisionId`, `whenTimestamp` | ✅ |
| `srs_unlocked_decision` | `decisionId` | ✅ (redundant with PK) |
| `srs_node` | `fenKey` | ✅ |

**Finding 3-A: `nextDueAt` indexes exist but unused by hot queries**

The `idx_position_knowledge_state_nextDueAt` and `idx_srs_review_state_nextDueAt` indexes exist, but the hot due-counting queries (`getChapterDueCounts`, `getActiveSideDueCounts`) join through `srs_decision` and use LEFT JOINs that don't leverage these indexes as leading columns. The indexes are mainly useful for a hypothetical `SELECT WHERE nextDueAt <= ?` query that the code **does not use** (it always joins from decisions).

- **Impact**: No actual problem, but the indexes consume write-side overhead on every answer.
- **Priority**: ⚪ Not actionable (removing them risks future queries)

**Finding 3-B: `srs_unlocked_decision` has a redundant index**

[srs_schema.dart#L156-L159](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/persistence/srs_schema.dart#L156-L159):

```sql
CREATE INDEX IF NOT EXISTS idx_srs_unlocked_decision_decisionId
ON srs_unlocked_decision(decisionId);
```

But `decisionId` is already the PRIMARY KEY (line 150-151). SQLite automatically creates an index on the primary key. This index is redundant and wastes write-time on every unlock/lock operation.

- **Estimated impact**: Negligible but technically waste
- **Priority**: 🟢 Quick win (drop it in next schema version)

**Finding 3-C: `getChapterDueCounts` complex SQL is efficient**

[sqlite_study_repository.dart#L735-L771](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/persistence/sqlite_study_repository.dart#L735-L771): The query joins `srs_decision` → `position_knowledge_state` and `srs_review_state` with GROUP BY `chapterId`. This uses `idx_srs_decision_chapterId` effectively. No N+1 pattern detected.

**Finding 3-D: `deleteChapter` / `deleteStudy` per-canonical-id loop**

[sqlite_study_repository.dart#L570-L595](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/persistence/sqlite_study_repository.dart#L570-L595):

```dart
for (final canonicalId in canonicalIds) {
  await txn.delete(kTablePositionKnowledgeState, ...);
  await txn.delete(kTableSrsReviewState, ...);
  await txn.delete(kTableSrsReviewEvent, ...);
}
```

This is an N-query pattern: each canonical id fires 3 DELETE statements with a correlated subquery. For a chapter with 100 decisions, that's 300 round-trips. The study delete path at [line 370-405](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/persistence/sqlite_study_repository.dart#L370-L405) already chunks, but `deleteChapter` does not.

- **Estimated impact**: 100–500 ms for large chapter deletes
- **Priority**: 🟡 Medium effort
- **Proposal**: Batch the canonical-id deletes with `IN (?)` clauses (chunked at 400), mirroring `deleteStudy`:

```dart
for (var i = 0; i < canonicalList.length; i += 400) {
  final chunk = canonicalList.sublist(i, min(i + 400, canonicalList.length));
  final p = List.filled(chunk.length, '?').join(',');
  await txn.delete(kTablePositionKnowledgeState,
    where: 'canonicalId IN ($p) AND NOT EXISTS (...)',
    whereArgs: [...chunk, chapterId]);
  // same for review_state and review_event
}
```

**Finding 3-E: `getReviewStatesByIds` full-table scan threshold**

[sqlite_study_repository.dart#L1257-L1264](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/persistence/sqlite_study_repository.dart#L1257-L1264):

```dart
if (ids.length > 800) {
  final idSet = ids.toSet();
  final rows = await _db.query(kTableSrsReviewState);  // full table scan
  return rows.where((r) => idSet.contains(r['decisionId']! as String))...;
}
```

When >800 ids are requested, this reads the **entire** `srs_review_state` table and filters in memory. The comment says "scanning the ~400-row table avoids dozens of redundant SQLite round-trips over FFI." But the table is **not** ~400 rows in the real library — it has 33K+ mirrored rows (every decision has a mirror). This full-table scan at 33K rows is fast (~2–5 ms), but the assumption in the comment may be stale.

Same pattern at [line 1060](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/persistence/sqlite_study_repository.dart#L1060-L1067) for `getKnowledgeStatesByCanonicalIds`.

- **Estimated impact**: ~2–5 ms (the full scan may actually be faster than chunked IN queries for the real workload — **measure first**)
- **Priority**: ⚪ Measure to validate the threshold

---

## 4. Memory Allocation Hotspots

**Finding 4-A: `_DueTally.add()` per-decision map lookups with `putIfAbsent` closures**

[review_service.dart#L260-L392](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/review/review_service.dart#L260-L392):

The `add()` method is called once per decision (31K–34K times). Each call does:
- 6+ `containsKey()` + nullable lookup pairs
- Multiple `putIfAbsent()` with closure allocations: `() => {Side.white: 0, Side.black: 0}` creates a new map object on every first-encounter

These closures allocate even on the "absent" branch. For 60+ studies × 2 sides, it's ~240 closure-to-map allocations total — not huge, but measurable cumulatively.

- **Estimated impact**: ~1–3 ms across 31K calls
- **Priority**: 🟢 Quick win
- **Proposal**: Pre-allocate the per-study side maps in the `_DueTally` constructor instead of `putIfAbsent` during iteration.

**Finding 4-B: `_loadReviewData` creates intermediate sets and lists**

[review_service.dart#L624-L646](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/review/review_service.dart#L624-L646):

```dart
final distinctCanonical = canonicalIds.toSet().toList();     // 31K → Set → List
final allQueryIds = {...decisionIds, ...distinctCanonical}.toList();  // 62K spread → Set → List
```

Three collection copies before the query even fires. The IDs are UUIDs (~36 chars each), so this is ~2 MB of string allocations for the intermediate containers.

- **Estimated impact**: ~3–8 ms (GC-sensitive)
- **Priority**: 🟡 Medium effort
- **Proposal**: Build the combined set directly:

```dart
final queryIds = <String>{};
for (final d in decisions) {
  queryIds.add(d.id);
  queryIds.add(d.canonicalId);
}
// Use queryIds.toList() only where the chunked query needs it
```

**Finding 4-C: Exposure throttle map copied on `checkpoint()` and `submitMove()`**

As noted in Finding 2-A, `snapshotExposureThrottle()` creates a full copy. During a session:
- `checkpoint()` copies it at [review_session.dart#L679](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/domain/review/review_session.dart#L679)
- `submitMove()` reads the getter at [review_service.dart#L861](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/review/review_service.dart#L861)

Two copies per move. The checkpoint copy is needed for rollback; the submitMove copy is for single-key reads only.

- **Priority**: 🟢 Quick win (the submitMove copy can be replaced with direct lookups)

**Finding 4-D: `decodeExpectedMoves` JSON parsing in hot row mapper**

[json_adapters.dart#L58-L82](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/persistence/json_adapters.dart#L58-L82):

A smart fast path already handles ~88% of single-move rows without JSON parsing. The fallback for multi-move decisions (`jsonDecode`) allocates a `List<dynamic>` + per-entry `Map<String, dynamic>`. At 31K decisions, ~12% (3.7K) hit the JSON path.

> [!NOTE]
> Performance-handoff §11 measured this path: only ~52 ms of `getAllDecisions`'s
> 145 ms is move parsing. The fast path already handles the dominant case.
> Further optimisation here is bounded by ~52 ms in a path that is **not on the
> move-response critical path**.

- **Priority**: ⚪ Already optimized — unlikely to yield further gains

---

## 5. Widget Rebuild Analysis

**Finding 5-A: `_ActiveReviewView` watches 5 provider selectors individually**

[review_screen.dart#L742-L749](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/view/review/review_screen.dart#L742-L749):

```dart
final boardPrefs = ref.watch(boardPreferencesProvider);
final showComments = ref.watch(studyPreferencesProvider.select((p) => p.showPgnComments));
final showAnnotations = ref.watch(studyPreferencesProvider.select((p) => p.showAnnotations));
final showDiagnostics = ref.watch(studyPreferencesProvider.select((p) => p.srsDiagnostics));
final showMoveHistory = ref.watch(studyPreferencesProvider.select((p) => p.showMoveHistory));
final compactReviewHud = ref.watch(studyPreferencesProvider.select((p) => p.compactReviewHud));
```

Good practice: `.select()` is used on 5 of 6 watches. However, `boardPreferencesProvider` is watched **without** a selector, so any board preference change (piece set, theme, haptics, coordinates) rebuilds the entire active review view.

- **Estimated impact**: Unnecessary rebuild on board settings change during review
- **Priority**: 🟢 Quick win
- **Proposal**: Select only the fields actually used in the build:

```dart
final pieceSet = ref.watch(boardPreferencesProvider.select((p) => p.pieceSet));
final boardTheme = ref.watch(boardPreferencesProvider.select((p) => p.boardTheme));
// etc.
```

**Finding 5-B: `ReviewScreen` top-level watches the entire controller**

[review_screen.dart#L33](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/view/review/review_screen.dart#L33):

```dart
final reviewStateAsync = ref.watch(reviewControllerProvider);
```

This is unavoidable — the top widget must decide between loading/error/data. The state is a comprehensive `ReviewScreenState` containing the entire session, prompt, board position, feedback, etc. Any field change triggers a full rebuild of the top-level `ReviewScreen`.

**However**, the internal sub-widgets (`_ActiveReviewView`, `_NothingDueView`, etc.) are stateful and only receive the state via constructor — which is correct Riverpod architecture.

The concern is `_ActiveReviewView` being a `ConsumerStatefulWidget` at 1655 LOC with many child widgets inlined. Breaking it into smaller `ConsumerWidget` children with targeted watches could reduce rebuilds, but this is a refactoring task, not a quick win.

- **Priority**: 🟡 Medium effort (view refactoring)

**Finding 5-C: `review_scope_drawer.dart` watches only 3 providers**

3 `ref.watch` calls for a 1366-line drawer is well-controlled.

**Finding 5-D: Missing `const` constructors on inner widgets**

The review screen has 90 `const` occurrences — good density for a 1655-line file. Most inner widgets use `const` constructors. No systemic issue found.

---

## 6. Import / PGN Parsing

**Finding 6-A: PGN import already offloads to isolate**

[pgn_importer.dart#L446-L465](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/import/pgn_importer.dart#L446-L465): `importPgnAsync()` checks `shouldOffloadPgnWork()` and runs in an isolate for large inputs. Same for `computePgnHashAsync()`. This is well-designed.

**Finding 6-B: Tree building is recursive with per-move `position.play()`**

[pgn_importer.dart#L667-L751](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/import/pgn_importer.dart#L667-L751): `_buildChildren()` calls `position.parseSan()` and `position.play()` for every move. These are dartchess operations (~10–50 µs each) which are inherent to building a legal move tree. No shortcut exists without breaking correctness.

**Finding 6-C: Hash computation walks the tree twice for PGN with pre-parsed games**

[pgn_importer.dart#L240-L242](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/import/pgn_importer.dart#L240-L242):

```dart
final hash = pgnHash ??
    (parsedGames != null ? computePgnHash(pgnText, parsedGames) : computePgnHash(pgnText));
```

When `parsedGames` is provided but `pgnHash` is not, `computePgnHash` walks the entire AST to build a canonical string, then SHA-256 hashes it. This duplicates work that `_buildRoot` also does (walking every move). But the hash function uses PGN SAN strings while the builder uses parsed positions, so they're fundamentally different traversals.

- **Priority**: ⚪ Architecturally necessary duplication

**Finding 6-D: `_countDescendantMoves` recursive count on error only**

[pgn_importer.dart#L658-L664](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/import/pgn_importer.dart#L658-L664):

This recursive count runs only when a move fails to parse — an error path. No hot-loop concern.

**Finding 6-E: Import persistence is well-batched**

[sqlite_study_repository.dart#L108-L136](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/persistence/sqlite_study_repository.dart#L108-L136): Chapters, nodes, and decisions are each inserted in a single batch within one transaction. Good.

---

## 7. Lazy Loading Opportunities

**Finding 7-A: Chapter trees are already lazy (PERF-FIX-46)**

[sqlite_study_repository.dart#L1420-L1422](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/persistence/sqlite_study_repository.dart#L1420-L1422):

```dart
rootResolver: treeJson != null && treeJson.isNotEmpty
    ? () => repertoireNodeFromJson(jsonDecode(treeJson) as Map<String, dynamic>)
    : null,
```

Trees are decoded on first access via a lazy resolver. **However**, `_chapterRow()` at [line 1441](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/persistence/sqlite_study_repository.dart#L1441) eagerly encodes the tree:

```dart
'treeJson': chapter.root != null ? jsonEncode(repertoireNodeToJson(chapter.root!)) : null,
```

Accessing `chapter.root` on write triggers the lazy resolver. This is **correct** behavior for writes (you need the tree to serialize it), but it means that `getChaptersByStudyIds()` queries that return rows with `treeJson` column are carrying the blob in memory even though the caller may never access `root`. The blob is a string in the row map, not decoded — the closure captures it.

- **Priority**: ⚪ No issue — the closure captures the string, not the parsed tree

**Finding 7-B: `getAllDecisions()` deserializes all `expectedMoves` eagerly**

[sqlite_study_repository.dart#L709-L712](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/persistence/sqlite_study_repository.dart#L709-L712):

```dart
Future<List<RepertoireDecision>> getAllDecisions() async {
  final rows = await _db.query(kTableSrsDecision);
  return rows.map(_decisionFromRow).toList(growable: false);
}
```

Every decision's `expectedMoves` JSON is decoded during row mapping. This was measured in §11 at ~52 ms for the JSON portion. The decision objects are needed with their moves for the session constructor's queue-building loop, so laziness would only relocate the cost (§11 conclusion).

> [!WARNING]
> Performance-handoff §11 explicitly refuted lazy `expectedMoves`:
> "Laziness would relocate the parse from `getAllDecisions` into the constructor,
> not remove it." **Do not reopen without a larger library.**

- **Priority**: ⚫ Closed direction (measured, refuted)

**Finding 7-C: `getAllReviewStates()` loads two full tables and merges**

[sqlite_study_repository.dart#L1235-L1248](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/persistence/sqlite_study_repository.dart#L1235-L1248):

```dart
Future<List<ReviewState>> getAllReviewStates() async {
  final rows = await _db.query(kTableSrsReviewState);       // full scan of 33K+ rows
  final kRows = await _db.query(kTablePositionKnowledgeState);  // full scan of ~87 rows
  final map = <String, ReviewState>{};
  for (final row in rows) { ... }
  for (final row in kRows) { ... }  // knowledge state overwrites
  return map.values.toList(growable: false);
}
```

This method is used only for the performance harness, not in production paths (the production path uses `getReviewStatesByIds`). No action needed.

- **Priority**: ⚪ Not on production path

**Finding 7-D: `treeJson` blobs carried through `getChaptersByStudyIds`**

The chapters query returns `SELECT *` including `treeJson`, which at 312 chapters carries ~34 MB of JSON through FFI into Dart's heap. The lazy resolver captures the string — the string is in memory regardless. For `loadSessionAndSummary`, the trees are needed for the node index (via `_replaceChapterNodes` on save, but on read the node index comes from `srs_node`).

For `loadSessionAndSummary`, chapters are loaded for the session constructor, which reads `chapter.root` for chapters with queued items. The closure closure holding `treeJson` as a string is the full 34 MB sitting in the Dart heap until GC.

- **Estimated impact**: ~34 MB peak heap for chapter blobs
- **Priority**: 🟡 Medium effort
- **Proposal**: For read-only paths (session building), use a column projection that excludes `treeJson` and loads the tree lazily from a separate query when needed. This requires a `Chapter.withLazyDbLoader(chapterId, db)` pattern.

---

## 8. Build-Time Analysis

**Finding 8-A: Freezed/json_serializable scoped properly**

`build.yaml` limits generators to `lib/src/model/**/*.dart`, `lib/src/**/*_models.dart`, and `lib/src/**/*_providers.dart`. This prevents unnecessary codegen on `domain/`, `persistence/`, `review/`, `import/`, and `view/`.

**Current generated file count**: 52 `.freezed.dart` files, 28 `.g.dart` files = 80 generated files.

**Finding 8-B: Freezed `from_json: false` and `to_json: false` are set**

```yaml
freezed:
  options:
    from_json: false
    to_json: false
```

This avoids generating unused JSON serialization for Freezed classes. Good.

**Finding 8-C: Largest generated files**

| File | Lines |
|---|---|
| `user.freezed.dart` | 5,058 |
| `study.freezed.dart` | 2,022 |
| `game.freezed.dart` | 1,577 |
| `analysis_controller.freezed.dart` | 1,363 |
| `chess.freezed.dart` | 1,086 |

The `user.freezed.dart` at 5K lines is the largest. It's a Lichess inherited model. These files are in `.gitignore` and regenerated — no action possible without removing Freezed from these models.

- **Priority**: ⚪ Structural — no quick wins

---

## 9. Summary Priority Table

| # | Finding | Impact | Priority | Effort |
|---|---|---|---|---|
| 1-A | Three separate `srs_chapter` metadata queries → merge into one | ~1–3 ms | 🟢 Quick win | 1 hour |
| 1-B | `getDueSummary()` duplicates the same three queries | ~1–3 ms | 🟢 Quick win | Same as 1-A |
| 1-C | Unnecessary 31K TallyDecision intermediate list | ~5–15 ms | 🟢 Quick win | 30 min |
| 2-A | `exposureThrottle` map copied on every move | ~0.1–0.5 ms/move | 🟢 Quick win | 30 min |
| 3-B | Redundant index on `srs_unlocked_decision.decisionId` | Negligible | 🟢 Quick win | 5 min |
| 3-D | `deleteChapter` per-canonical N-query loop | 100–500 ms on delete | 🟡 Medium effort | 2 hours |
| 4-A | `_DueTally.add()` putIfAbsent closure allocations | ~1–3 ms | 🟢 Quick win | 1 hour |
| 4-B | `_loadReviewData` intermediate collection copies | ~3–8 ms | 🟡 Medium effort | 1 hour |
| 4-C | Exposure throttle copied twice per move | ~0.2–0.5 ms/move | 🟢 Quick win | Same as 2-A |
| 5-A | `boardPreferencesProvider` watched without selector | UI jank on settings change | 🟢 Quick win | 15 min |
| 5-B | `_ActiveReviewView` monolithic — many inlined children | Excess rebuilds | 🟡 Medium effort | Half day |
| 7-D | `treeJson` blobs carried through chapter queries | ~34 MB peak heap | 🟡 Medium effort | Half day |
| 1-D | Node index load 376 ms for `inScope` sessions | ~376 ms | 🔴 Major refactor | Multi-day |

### Top recommendations (measure-first order)

1. **Merge chapter metadata queries** (1-A/1-B) — no-risk, verifiable in existing harness
2. **Replace throttle map copy with direct lookup** (2-A/4-C) — on the 16 ms critical path
3. **Pre-allocate `_DueTally` side maps** (4-A) — shaves allocation pressure on session start
4. **Eliminate TallyDecision intermediate list** (1-C) — reduces session-start GC
5. **Add selector to `boardPreferencesProvider` watch** (5-A) — trivial correctness fix
6. **Batch `deleteChapter` canonical cleanup** (3-D) — user-visible on large study deletions
7. **Exclude `treeJson` from read-only chapter queries** (7-D) — biggest memory win

> [!CAUTION]
> The node index load (1-D, 376 ms) is the largest remaining session-start cost
> for the default `inScope` setting. It is a **design-level** problem already
> identified in §13 that requires its own brief — not a patch. The existing
> perf-handoff explicitly says "not a patch."
