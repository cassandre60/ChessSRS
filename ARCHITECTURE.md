# Technical Architecture

Authority: module boundaries, data flow, persistence arrangement and licensing.
`SPEC.md` owns exact behavioral invariants; QUALITY owns additional constraints.
Scheduling equations live in `ChessSRS Scheduling Architecture.md`.
See `docs/documentation-map.md` for scope, status and verification authorities.

## 1. Foundation

ChessSRS is a local-first repertoire/SRS trainer built as a GPL-3.0 fork of
[Lichess Mobile](https://github.com/lichess-org/mobile). The standalone predecessor
is archived at `legacy/pre-reset`: behavioral reference only, not code to restore.
Lichess supplies the technical foundation; Diagram supplies the visual identity
(`design/README.md`). Current features and deferred work live in MVP and the
implementation ledger, not in this architecture file.

## 2. Layer boundaries

```text
Presentation: view/, widgets/, styles/, design/ (Flutter/chessground)
       ↓ application providers; domain value types may be consumed directly
Application: review/, inherited model/ providers/services (Riverpod)
       ↓ domain engine + repository contracts
Domain: domain/ (pure Dart, dartchess core values)
Infrastructure: persistence/, db/, import/, network/ (adapters and I/O)
```

The domain computes; infrastructure fetches/persists; application orchestrates;
presentation renders and forwards input. Inherited online feature models are
not the local repertoire's domain entities. Constraints: QUALITY §1;
purity/I/O enforcement: INV-040/042 and G03.

The prior three presentation→persistence exceptions are no longer current:
`rg -n 'src/(db|persistence)/' lib/src/view` finds no imports in the reconciled
snapshot. The dated tech-debt inventory is not permission to reintroduce them.

## 3. Components and entry points

| Module | Responsibility / entry points |
|---|---|
| `lib/src/domain/` | Study, Chapter, RepertoireNode, RepertoireDecision, ReviewState, PositionKnowledgeState, ReviewSession/ReviewEngine, Scheduler, Clock; public barrel `domain.dart` |
| `lib/src/review/` | ReviewService and ReviewController: scope loading, answer orchestration, persistence, summaries and presentation state |
| `lib/src/persistence/` | StudyRepository contract, SqliteStudyRepository, SRS schema, JSON adapters and data migrations |
| `lib/src/db/` | Database open/upgrade, bundled openings database and secure storage; schema version lives in `database.dart` |
| `lib/src/import/` | PGN import/export, source normalization and opening classification; dartchess parses/validates chess |
| `lib/src/model/` | Inherited Lichess auth, studies, analysis, engines, preferences and related providers |
| `lib/src/network/` | HTTP/socket/connectivity adapters for optional online features |
| `lib/src/view/`, `widgets/`, `styles/`, `design/` | Screens, reusable UI and Diagram tokens/primitives |

File counts, line counts, method line numbers and toolchain pins are deliberately
not cached here. Inspect source/config instead. Dart/Riverpod conventions are
in CLAUDE, verification in TEST_STRATEGY.

## 4. Review orchestration

1. ReviewController receives PGN text/file or downloaded Lichess
   study PGN. `importPgn`/`importPgnAsync` normalizes it into the same local model.
2. `StudyRepository.saveImportResult` stores studies, chapter trees and derived
   decisions. PGN remains an interchange format, not the domain model.
3. `ReviewService.startSession` loads the chosen scope, its states and selected
   Scheduler/Clock, then constructs the pure ReviewSession. Chapter trees can be
   resolved lazily; bulk queries and a bounded prompt buffer reduce overhead.
   This does **not** mean the entire session loads only one buffer's worth of
   metadata. Loading guarantees: INV-051.
4. For an answer, the service checkpoints the session; the domain computes the
   grade, traversal and primary/graph state changes. `saveAnswerBatch` persists
   the canonical states, mirrors and event atomically in SRS mode. Failure
   restores the in-memory checkpoint; an acknowledged answer is durable.
5. The controller renders feedback and advances. Practice skips review-state
   and event writes. No network request participates in this loop.

Review behavior (grading/transpositions, lapse lifecycle, fresh introduction,
scopes, order, continuity and annotations) is specified in SPEC and PRODUCT,
not a second state-machine contract here.

## 5. Identity & determinism

Entities have stable UUID occurrence IDs. Position identity is normalized
four-field FEN (INV-015). Shared **memory identity** additionally includes the
trained side and the complete sorted accepted UCI answer set (INV-016/017/030):

```text
sha1("<repertoireSide.name>|<fenKey>|<sorted uci>|<sorted uci>|...")
```

The implementation is `canonicalKeyForPosition` in
`domain/position_knowledge_state.dart`. Two occurrences share a schedule only
when the entire question and trained side match. Different answer sets at the
same position are permitted independent questions, not rejected imports.
The older `canonicalKey(fenKey, expectedMoveUci)` is legacy compatibility,
not the format for new complete-set identities.

Scheduling/review time comes through Clock (INV-024/041); randomized session
choices use an injectable Random. These claims are scoped, not a claim that
all entity timestamp defaults throughout the domain are already clock-injected.

## 6. Licensing constraints (binding)

- Preserve GPL-3.0 `LICENSE`, `COPYING.md` and existing copyright notices.
- chessrs: GPL-compatible attributed adaptation is permitted; prefer independent
  reimplementation.
- Listudy: behavior only, no AGPL code copying into this GPL fork.
- Extraction sources and boundaries: `docs/INTEGRATION_MAP.md`.

## 7. Persistence arrangement

One SQLite database is opened/upgraded by `db/database.dart`; SRS table definitions
are in `persistence/srs_schema.dart`. Version/columns are source-owned, not a
hand-maintained second schema here.

| Table | Role |
|---|---|
| `srs_study` | Content container, active-pool flag, canonical PGN hash |
| `srs_chapter` | Study child, orientation/opening metadata and `treeJson` blob |
| `srs_decision` | Recallable occurrence and accepted moves; pointer `canonicalStateId` |
| `position_knowledge_state` | Shared question memory, including exposure throttle |
| `srs_review_state` | Compatibility mirror of review memory; canonical keys need not be decision row IDs |
| `srs_review_event` | Answer history; do not infer a decision foreign key from the name |
| `srs_study_remote` | Imported-study remote linkage/timestamp for explicit re-import checks, not live sync |

The chapter blob is stored once on import; answers update only review-related
rows (INV-002). Study/chapter deletion preserves memory shared with surviving
occurrences (INV-004). Schema upgrades and canonical rekeys preserve derived
identities and reachable mirrors (INV-005/069). Data migrations live alongside
the repository; inspect the actual upgrade path rather than a cached migration
count. Full PGN export is not a backup of this scheduling/history data.

## 8. External integrations

Lichess HTTP, OAuth, WebSocket, cloud evaluation, explorer/tablebase and native
engines are optional adapters outside local review. Hosts/defaults live in
`constants.dart`; dependency/toolchain pins in pubspec/lock/FVM config.
Auth transport/redaction: INV-006/007. Socket handshake: INV-064.

Imported studies are SQLite **snapshots**: no socket auto-sync or remote overwrite.
Remote StudyController browsing applies socket events in memory only. Explicit
re-import timestamp checks are not background synchronization. Firebase/FCM and
native home-screen widgets were removed (CUT_PROPOSALS); old descriptions are
historical, not current integration requirements.

## 9. Decisions, limitations and evidence

`docs/decisions.md` records rationale and supersession; it does not outrank the
current contract for a rule. `docs/tech-debt-inventory.md` and dependency audits
are dated evidence to re-check before acting. Delivery/runtime claims live in
IMPLEMENTATION_PLAN and `docs/manual-test-log.md`. This document is a source
inspection, not a new runtime pass.
