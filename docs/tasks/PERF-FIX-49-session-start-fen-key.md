# PERF-FIX-49 — Fen key on decision rows (whole-library review opens fast)

**Status: open.** Owner decision Q15 answered 2026-10-24: option A. Evidence
base: `docs/performance-handoff.md` §10 (the 0.8 s attribution), §11 (the
refuted lazy-moves direction), §12 (this decision). One worktree, one PR.

## The goal, in one sentence

Opening whole-library review (~0.8 s at 31k decisions) stops decoding the
whole library's opening trees, by storing each decision's position identity
(the "fen key") on its database row instead of only inside the chapter tree.

## Premise (re-runnable before starting)

```bash
git grep -n "_indexChapter\|_ensureAllChaptersIndexed" -- lib/src/domain/review/review_session.dart
git grep -n "version: 20" -- lib/src/db/database.dart
```

Session start decodes nearly every chapter tree because the constructor's
`_indexChapter` needs `node.fenKey` (only in the tree) to build
`_decisionsByFenKey` and `_canonicalByFenMove`, and because the node maps for
prompts are built for every queued chapter up front. Verify both still hold —
line numbers drift; symbols do not.

## Design (settled 2026-10-24 from the access-site pass)

1. **Schema v21** (`lib/src/db/database.dart`): `ALTER TABLE srs_decision ADD
   COLUMN fenKey TEXT` (nullable), following the v10 column precedent.
   `createSrsTables` gains the column for fresh installs. Then bump
   `version: 20` → `21` with a data migration that backfills it.
2. **Backfill** (the v16 `rekeyCanonicalReviewState` is the model): decode
   each chapter tree once, map `nodeId → fenKey`, update decision rows;
   per-chapter try/catch skip; rows whose node is missing stay **null**.
   Null means "fall back to the tree path" everywhere — no row is ever wrong,
   only sometimes slow.
3. **Model**: `RepertoireDecision` gains `final String? fenKey`. Written by
   the importer (it already computes `fenKey(...)` per node), mapped by
   `_decisionFromRow`/`_decisionRow`. **Do not add it to `==`/`hashCode`** —
   it is derived state like `expectedMoves`, and touching equality would
   churn ~150 test fixtures.
4. **Session split** (`review_session.dart`): `_indexChapter` becomes two
   concerns —
   - `_indexChapterDecisions`: tree-free; fills `_decisionsByFenKey` and
     `_canonicalByFenMove` from `d.fenKey` (falling back to
     `_nodesById[d.nodeId]?.fenKey` when the row's is null). Runs at
     construction for every queued chapter, as today.
   - `_indexChapterNodes`: the tree walk (`_indexNodes` + `_nodeCountCache`);
     runs only for the first prompt's chapter at construction, and otherwise
     through `_ensureAllChaptersIndexed`.
5. **Self-healing lazy node index**: every reader that needs node data either
   already calls `_ensureAllChaptersIndexed` (`_findTransposedNode` :1153,
   `_findSiblingGraphNodes` :1373) or gains the call (`_advanceToNextDue`,
   `_continueWithCorrectMove` entry). A background pass started after
   construction progressively decodes remaining chapters between event-loop
   yields so the ~350 ms overlaps think-time; the synchronous calls find it
   complete or finish it themselves. Correctness never depends on the
   background pass having run.
6. **Flag discipline**: `_allChaptersIndexed` may only be set true AFTER the
   last chapter is indexed (today it is set before, :375-376 — safe only
   while everything is synchronous). The background pass must not let a
   synchronous reader observe a half-truth.
7. **byLine order** keeps its full decode at construction (tree order is its
   definition; replacing it is out of scope).

## Equivalence rules

- Behavior byte-identical: same prompts, same grading, same transposition
  acceptance (INV-065 fail-closed `incomingMove` check untouched), same
  counts. The fen key column is redundant data, not new truth.
- No invariant test weakened, skipped or deleted (G08); new tests cite the
  stable IDs they guard (INV-065, INV-020, INV-023/028/030-032/068 where
  touched).
- The migration must be idempotent and crash-safe (INV-005, INV-002; fault
  patterns live in `test/persistence/crash_consistency_test.dart`).

## Steps, each with its verification

1. Schema + migration + backfill, with a v20 fixture test (pattern:
   `migration_fixtures_test.dart` strip-to-version) and a crash-consistency
   test. Verify: persistence suite green on the touched files.
2. Model + import + row mapping. Verify: repository round-trip test asserting
   the column survives; existing import tests untouched and green.
3. Session split + self-healing readers + background pass. Verify: new test
   that a null-fenKey row and a filled row grade identically; INV-065
   transposition tests green; a scheduling test where the background pass has
   NOT finished and a synchronous reader still sees a complete index.
4. Harness before/after on the real DB copy (fresh `/tmp/perf/` copy
   including `-wal`/`-shm`): `real_library_session_cost_test.dart`,
   `session_start_attribution_test.dart`,
   `session_start_move_list_ceiling_test.dart`. Expected: whole-library
   startSession drops from ~800 ms toward ~450-500 ms (the remaining cost is
   row mapping + queue work, measured in §11). Quote bands, not points.
5. `fvm dart format` + one `fvm flutter analyze` after the last edit;
   `./scripts/gates.sh t1` post-commit. Full suite belongs to CI.
6. Runtime validation per TEST_STRATEGY §4 **against a copy of the app data,
   never the original read-write** — the migration writes on first launch.
   If the app cannot be pointed at a copy, record the gap in
   `docs/manual-test-log.md` instead of running it on the real data.

## What would make this brief wrong

- A chapter-tree editor landing in `lib/` (any tree mutation must now also
  rewrite the affected rows' fen keys — re-search decision write sites).
- The attribution numbers moving (re-run the harnesses; the shape line in
  their output is the truth).
- A reader of the node maps found outside the list in step 5 (re-run the
  access-site pass; the symbol set is in §11's enumeration).

## Out of scope

The byLine ordering source, off-isolate decoding, any change to grading
semantics, and release tagging (AGENTS §11 decides that after merge).
