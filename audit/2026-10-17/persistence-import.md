# Persistence & import chapter (digest)

Source: full per-test walk of test/persistence/sqlite_study_repository_test.dart
(24 tests), test/db/database_config_test.dart (1), test/db/srs_upgrade_test.dart
(2), test/import/pgn_importer_test.dart (about 45), lichess_study_importer_test.dart
(13), pgn_exporter_test.dart (15). The originally-requested names
pgn_tree_repository_test / review_state_repository_test / srs_database_test do not
exist; their contracts live in the paths above.

## Grade distribution (81 graded by the walk, all counted here)

36 grade 3, 31 grade 2, 2 grade 1, 0 grade 0.

## What is strong here

- Real end-to-end SQLite durability: close and reopen against a temp-dir file, two level tree, decisions, states and events (`sqlite:55`).
- Latent-column preservation tested by pre-seeding (`sqlite:335`): an `INSERT OR REPLACE` regression fails at `expect(readAnswered?.latencyEmaMs, 1234.5)`.
- THE hencethe migration fixtures are real on-disk bundles (v12, v13, v16, v17) with v17→18 reproducing a production outage (owner log 2026-10-14, `srs_upgrade:92`).
- Deletion matrix: canonical-row preservation across studies (INV-031/033) with both directions (`sqlite:551/600/931/1019`).
- Atomicity-forcing trigger test: `RAISE(ABORT, 'forced mirror failure')` on the second mirror write (`sqlite:853`) — the only torn-write forcing on the write path.
- Hash-backfill equivalence: the two hash functions agree across normalisation hazards (`pgn_importer:704/732`), and a NULL pgnHash column is backfilled to a participant (`importer:764`).
- Real isolate work (`pgn_importer:803`).

## Top 3 weakest (with quotes)

1. `pgn_importer_test.dart:51` — 'whitespace-only string returns empty result' has a
   single assert, `expect(result.chapters, isEmpty)`, and a whitespace-only importer
   that emitted zero chapters AND zero errors would leave it green — the exact
   silent-good behaviour of the sibling test at :41 which does check `errors.isNotEmpty`.
2. `pgn_importer_test.dart:39` — 'chapters have independent root node instances' is
   untested (and trip-wiring): identical root ids; fails only if implemented as
   children not being hand-haver nodes.
3. `sqlite_study_repository_test.dart:246` — only ONE row is in the DB, at index 42
   of an 850-element id list; a chunking bug that loses the second chunk (ids
   800-849) is invisible while nothing is in that range.
   (the chunk test at :1745 is a separate record to the 2026-10-16 conformance audit as F4.)

## Gaps (none of this suite covers)

- NAG glyphs (`$1`, `!?`) and inline `[%eval]`/`[%clk]`/`[%mt]`: no domain representation
  exists (rg returns nothing), so either silently stripped or appended into comments — not
  even pinned. No test.
- Export round-trip through comments: importer keeps both pre/post comments (`pgn_importer:921`),
  but the exporter emits no comments (`pgn_exporter` first test) — the contract
  `importPgn(exportStudy(chapter))` preserving annotations is not covered.
- Remote study handalong: the fetch/materialize path reuses no test at all — the lichess_study_importer
  file covers regex/title helpers only; nothing covers the store-remote-study flow end-to-end.
- Corrupt stored treeJson (position tree from a truncated file on disk): failure mode
  is not pinned.
- Downgrade path, DB older than v6, empty-library upgrade.

## Scaffolding observability

All persistence-context scaffolding has proven itself worth keeping. All sqlite tests
are actual calls with cleanup; no single test uses pure MockClient and no sqlite path
avoids the standalone DB instance. `_BackfillCountingRepository` subclasses the real
class and counts fetches — distinguishes batched from N+1 by design (sqlite:1208).
