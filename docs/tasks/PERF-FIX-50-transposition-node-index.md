# PERF-FIX-50 — A FEN→node index so a wrong move never decodes the library

Status: **implemented 2026-11-05** (v22 `srs_node`, backfill, import/save writes,
session lookup, boundedness + migration tests). Kept as the design record.
Read this before changing the index.

## 1. The symptom

`ReviewSession.submitMove` grades a move against the prompt synchronously. When
the played move matches no expected repertoire move, `_resolvePlayedMove` calls
`_findTransposedNode`, and a lapse also calls `_findSiblingGraphNodes`. Both
begin with `_ensureAllChaptersIndexed()`:

```dart
// review_session.dart
RepertoireNode? _findTransposedNode(...) {
  if (transposeScope == TransposeScope.off) return null;
  _ensureAllChaptersIndexed();   // decodes every chapter tree in the library
  ...
  final candidates = _nodesByFenKey[key];   // node-level FEN lookup
```

The session constructor only *queues* background indexing for large libraries
(`_indexRemainingNodesInBackground`). If the user answers a wrong move before
that pass finishes, the loop decodes every remaining chapter's `treeJson`
**synchronously inside the move handler** — on the owner's ~300-chapter library,
a visible stall on the one path where the user already knows they were wrong.
The INV-050 oracle (`test/review/move_latency_test.dart`) only submits correct
moves, so it never exercises this.

## 2. Why a decision-row index is not enough

`_nodesByFenKey` is keyed by *every* node's `fenKey`. The transposed target is
the position a played user move reaches — an **opponent-to-move** position.
`RepertoireDecision` rows are derived only for the trained side's turn, so a
`fenKey` index over `srs_decision` cannot find that node. A node-level index is
required.

## 3. Proposed schema (v22)

```sql
CREATE TABLE srs_node (
  chapterId TEXT NOT NULL,
  nodeId    TEXT NOT NULL,
  fenKey    TEXT NOT NULL,
  PRIMARY KEY (chapterId, nodeId),
  FOREIGN KEY (chapterId) REFERENCES srs_chapter(id) ON DELETE CASCADE
);
CREATE INDEX idx_srs_node_fenKey ON srs_node(fenKey);
```

- Written once per chapter import/save, in the same transaction as the tree
  (`saveImportResult`, `saveChapter`). `Chapter.root` is already walked on import,
  so this is one extra batch insert per node.
- Migration v22: create the table, then backfill from each chapter's `treeJson`
  (same walk as `canonical_rekey_migration`). Backfill is one-time; an empty
  `treeJson` chapter inserts nothing.
- Deletion follows the chapter FK (`ON DELETE CASCADE`), so `deleteStudy` /
  `deleteChapter` need no new code.

## 4. Session integration

Replace the node map lookup with a repository query, keeping grading synchronous
(INV-050 is a latency budget, not an async requirement):

```dart
// ReviewSession gains a `NodeIndex` dependency (injected by ReviewService).
final targets = nodeIndex.nodesAt(fenKey); // List<({chapterId, nodeId})>, sorted
```

- Order must stay identical to today's `_nodesByFenKey` ordering (chapter order,
  then DFS rank) so transposition choices do not drift; keep the existing
  `(chapterIndex, dfsRank)` sort over the query result.
- Only the chapters that actually hold a target node need their trees decoded —
  `_ensureChapterNodesIndexed(chapterId)` for those, not all chapters.
- `_findSiblingGraphNodes` becomes tree-free today: it only needs
  `_decisionsByFenKey`, which `_indexChapterDecisions` builds without decoding
  (v21 rows carry `fenKey`). Do that change first; it is independent and cheap.

## 5. What proves it

1. **Correctness:** `test/review/review_transposition_test.dart` must stay green
   unchanged (in-scope/within-study/off, identical grading).
2. **Boundedness:** a new test builds a session over N chapters with the
   background pass deliberately incomplete, submits a wrong move, and asserts the
   number of decoded chapter trees is small (e.g. ≤ the chapters holding a
   target node), not N. Add a `treeDecodes` counter to the test repository fake.
3. **Latency:** extend `move_latency_test.dart` to submit one wrong move per
   batch and keep the median under the INV-050 budget.
4. **Migration:** a v21 database with chapters backfills `srs_node` rows and the
   rekey/delete tests still pass (INV-005/069).

## 6. Cost and risk

- Medium: one schema version, one backfill, import/save write path, one
  repository query, and the session wiring.
- The domain budget (`domain_loc`, protected) is at its cap; the repository
  query and the session seam must be written within the existing line count or
  offset by removing equivalent domain code. Do **not** edit the ratchet.