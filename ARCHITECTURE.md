# Technical Architecture

> **Foundation reset**: this application is built on a fork of
> [lichess-org/mobile](https://github.com/lichess-org/mobile) (GPL-3.0).
> The previous standalone Flutter implementation is archived at git tag
> `legacy/pre-reset`. It is reference material only — the product and domain
> knowledge lives in the Markdown specifications, not in the old code.

## 1. What this application is

**A local-first chess repertoire + spaced-repetition trainer** built on the
Lichess Mobile application foundation. It is *not* "Lichess with modifications":
Lichess Mobile provides the technical/UI foundation (board, theme, navigation,
state management, persistence patterns); our product provides the domain
(repertoire, review, SRS).

```text
Lichess Mobile foundation (GPL-3.0 fork)
        |
        +-- application/product modules (Riverpod providers)
        |
        +-- OUR domain boundary (pure Dart: repertoire, review, SRS)
        |       |
        |       +-- Listudy-derived training semantics
        |       +-- chessrs-derived SRS/review semantics
        |
        +-- local persistence / import infrastructure (sqflite, dartchess PGN)
```

## 2. Layer boundaries

```text
┌────────────────────────────────────────────────────────────┐
│ Presentation — Lichess Mobile shell (Flutter + Riverpod)    │
│   Review scene (primary) · Repertoire selector · Import ·  │
│   Settings (Lichess settings framework)                    │
└──────────────────────────┬─────────────────────────────────┘
                           │ talks only to application providers
┌──────────────────────────▼─────────────────────────────────┐
│ Application — Riverpod providers/services orchestrating    │
│   use-cases (import study, start review, submit move)      │
└──────────────────────────┬─────────────────────────────────┘
                           │ repository interfaces only
┌──────────────────────────▼─────────────────────────────────┐
│ DOMAIN (ours) — pure Dart, no Flutter/chessground imports   │
│   Study · Chapter · repertoire tree · RepertoireDecision   │
│   ReviewSession engine · ReviewState · Scheduler contract  │
└──────────────────────────┬─────────────────────────────────┘
                           │ adapters only
┌──────────────────────────▼─────────────────────────────────┐
│ Infrastructure — Lichess-derived:                          │
│   dartchess (rules, FEN, SAN, PGN) · chessground widgets   │
│   sqflite local DB · settings/preferences · file import   │
│   (no network on any critical path)                        │
└────────────────────────────────────────────────────────────┘
```

### Boundary invariants

1. **Pure domain**: our domain code (`lib/src/domain/`, 23 files) contains pure
   Dart logic and entities. Zero imports of `package:flutter/...` widgets,
   chessground, or sqflite — enforced by inspection and by the banned-API gate
   (`scripts/gates/banned_apis_check.py`). Testable without a widget tree.
   The module's public surface is the barrel `domain/domain.dart`.
2. **One chess representation**: `dartchess` is *the* chess rules engine.
   Do not introduce a second chess library or reimplement move generation.
   Domain code may consume dartchess core types (`Position`, `Move`, `San`)
   through thin adapters; UI consumes chessground. Never create competing
   representations of moves/positions/games.
3. **Lichess UI is not our domain model**: Lichess `model/` classes for online
   features are presentation/application concerns of the foundation, not
   domain entities of our product. Our entities live in our domain module.
4. **Local-first critical path**: user move → legality (dartchess) → repertoire
   lookup → SRS update → board update runs entirely in memory, locally.
   Network access is never on this path.
5. **Isolated integrations**: Listudy-derived and chessrs-derived behavior
   live in isolated domain modules behind our contracts (see
   `docs/INTEGRATION_MAP.md`). No cross-cutting merges.
6. **Imported repertoires vs. online studies**: Repertoires imported into
   ChessSRS (from PGN or Lichess) are pure, local-first snapshots stored in
   SQLite. They have no live socket connection and never auto-sync with
   remote changes. Remote Lichess study browsing (`StudyScreen`/`StudyController`)
   operates strictly in-memory over WebSockets for live viewing; it never
   writes to the local database.

## 3. Component responsibilities

### Domain (ours)

- **`Study` / `Chapter`**: repertoire content containers (source PGN file →
  study; PGN game → chapter, honoring FEN headers).
- **Repertoire tree**: branching move tree of positions. Reuses the
  Lichess `Node`/`Branch` tree *pattern* where practical, but decision
  semantics are ours.
- **`RepertoireDecision`**: THE scheduled unit — a position (from the player's
  perspective) plus the expected repertoire move(s). Every branch the player
  must recall is a decision; opponent moves are not scheduled independently.
- **`ReviewState` / `ReviewEvent`**: SRS tracking — first/last review, next
  due, repetition count, lapses, stability — plus immutable review log.
- **`Scheduler`** (contract): interval computation, implemented three times and
  selected at runtime from settings (`SchedulerType` in
  `model/study/study_preferences.dart`, resolved by `schedulerProvider` in
  `review/review_service.dart`): `SimpleScheduler` (exponential ladder, the
  default), `EaseScalingScheduler` (chessrs-style ease and scaling), and
  `ChessFsrsScheduler` (binary FSRS, `targetRetention`, default 0.88). Adding a
  fourth means implementing the contract and extending the `switch` — nothing
  else in the domain knows which one is in use.
- **`ReviewSession` engine**: due-decision selection, move validation against
  *repertoire* (not engine truth), auto-traversal of non-due material,
  opponent-reply auto-play, correct/incorrect feedback semantics.
- **`Clock`** abstraction: deterministic time in tests.

### Infrastructure (Lichess-derived)

- **dartchess**: legality, SAN/UCI, FEN, and PGN parsing (`PgnParser`) —
  used by the import pipeline; PGN is an *input format*, never the domain model.
- **chessground**: board rendering, drag & drop, animation — presentation only.
- **sqflite (`db/`)**: local persistence for studies, trees, decisions, review
  states, events. Incremental writes; full study tree never rewritten per move.
- **settings/preferences**: board theme, piece set, sound — Lichess framework.
- **import**: PGN file import (multi-game, RAV variations, comments, NAGs,
  starting FENs) with graceful, structured degradation — never silent corruption.

### Presentation (Lichess-derived)

- App shell, tab navigation (reduced to: **Review** primary, settings in More),
  theming (`styles/`), reusable `widgets/`.
- **Review scene**: board-dominant screen; the board is the product.
- **Review modes**:
  - `ReviewMode.srs`: standard spaced-repetition training updating review states and logging events.
  - `ReviewMode.practice`: non-destructive rehearsal (cram mode) allowing active board testing without altering SRS intervals.
- **Review scopes** (`domain/review/review_scope.dart`, six constructors):
  - `ReviewScope.all()`: all active studies in the review pool.
  - `ReviewScope.white()` / `ReviewScope.black()`: one side of every study —
    the two sides of a repertoire carry separate review memory.
  - `ReviewScope.study(id)`: specific study.
  - `ReviewScope.chapter({studyId, chapterId})`: one chapter.
  - `ReviewScope.opening(name)`: virtual cross-study opening hub.
- **Review order** (`domain/review/review_order.dart`): `dueDate` (most
  overdue first), `byLine` (study → chapter → tree order, the default), or
  `random`. The due *set* is identical in all three; only presentation order
  changes.

## 4. Review state machine (preserved product semantics)

```text
                ┌───────────────┐
                │ Select Scope  │  (all active / one study / one opening)
                └───────┬───────┘
                        ▼
                ┌───────────────┐
                │ Due Decision? ├─── No ──► calm idle state (option: Explore / Practice)
                └───────┬───────┘
                        │ Yes
                        ▼
                ┌───────────────┐
                │ Show Position │  (board oriented; move comments strictly hidden)
                └───────┬───────┘
                        ▼
                  User plays move
                        │
          ┌─────────────┴─────────────┐
          ▼                           ▼
    [Repertoire move]           [Other move]
          │                           │
   • record success (if SRS)   • record lapse (if SRS)
   • reveal move comment       • reveal expected move & comment
   • auto-traverse non-due     • keep board interactive for reguess
   • opponent auto-reply       • re-queue failed item
          │                           │
          └─────────────┬─────────────┘
                        ▼
                Next Due Decision      (until nothing due)
```

Key semantics (from PRODUCT/QUALITY + reference projects):
- Any valid repertoire branch is accepted; the played branch is followed.
- Auto-traversal is **never permanent exclusion** — learned moves return when due.
- No session-complete screen; review is an ongoing utility.
- Move comments are withheld during recall to prevent spoilers, then displayed post-move.
- Wrong-move feedback leaves the board interactive so the user can immediately reguess.
- Practice mode traverses lines identically to SRS mode but performs zero database writes.

## 5. Identity & determinism

- Entities use stable unique IDs (sync-ready).
- Position identity = normalized 4-field FEN (placement, side to move,
  castling, en-passant) — the "clean FEN" concept.
- All time-dependent logic takes an abstract `Clock` for deterministic tests.

## 6. Licensing constraints (binding)

- The whole application remains **GPL-3.0** as a fork of Lichess Mobile.
  Preserve `LICENSE`, `COPYING.md`, and copyright notices verbatim when
  trimming code.
- chessrs (GPL-3.0): adaptation permitted with attribution; default is
  reimplementation.
- listudy (AGPL-3.0): **no code copying**; behavioral reference only.
- See `docs/INTEGRATION_MAP.md` for the extraction rules.

## 7. Related documents

- `PRODUCT.md` — product definition (authoritative)
- `MVP.md` — current scope
- `QUALITY.md` — invariants
- `TEST_STRATEGY.md` — how invariants are proven
- `CUT_PROPOSALS.md` — Lichess foundation trim map & status
- `docs/INTEGRATION_MAP.md` — Listudy/chessrs extraction plan
- `docs/decisions.md` — durable decision log
- `Chess_Repertoire_SRS_Product_Blueprint.md` — deep product philosophy (consult on demand)

## 8. Module map

Sizes are hand-written Dart (generated `*.freezed.dart` / `*.g.dart` are
gitignored and absent from a fresh clone). "Depends on" lists inward edges
only, i.e. what the module imports.

| Module | Files / lines | Role | Entry points | Depends on |
|---|---|---|---|---|
| `lib/src/domain/` | 23 / 3,153 | Pure-Dart domain: repertoire tree, decisions, SRS state, review engine, scheduler contract, clock | barrel `domain.dart`; `ReviewSession`, `ReviewEngine`, `Scheduler`, `PositionKnowledgeState` | `dartchess`, `meta`, `logging`, `uuid`, `crypto` — **no Flutter, chessground or sqflite** |
| `lib/src/review/` | 2 / 2,182 | Application layer: orchestrates sessions, persistence and SRS updates; Riverpod providers | `reviewServiceProvider`, `ReviewService.startSession` / `submitMove` / `retryMove` / `getDueSummary`; `ReviewController` | domain, persistence, `study_preferences` |
| `lib/src/persistence/` | 7 / 1,746 | SQLite schema, `StudyRepository` contract and its sqflite implementation, JSON adapters, two one-shot data migrations | `study_repository.dart` (contract), `sqlite_study_repository.dart`, `srs_schema.dart` | domain, `sqflite`, `dartchess` |
| `lib/src/db/` | 3 / 410 | Opens the one database, bundles the openings DB, secure storage | `database.dart` (`openDatabase`, schema v15) | sqflite, `sqflite_common_ffi` (desktop/tests) |
| `lib/src/import/` | 4 / 1,047 | PGN import/export, Lichess study import, opening-name derivation | `importPgn` / `importPgnAsync` → `ImportResult`; `pgn_exporter.dart` | dartchess, domain |
| `lib/src/network/` | 5 / 2,736 | Lichess HTTP, WebSocket, connectivity, server status — Lichess-derived | `http.dart` (`HttpClientFactory`), `socket.dart`, `server_status.dart` | `http`, `cronet_http`, `cupertino_http`, `web_socket_channel` |
| `lib/src/model/` | 111 / 22,504 | Lichess-derived feature models (games, studies, auth, engine, users) | `model/**/*_providers.dart` | everything above |
| `lib/src/view/` | 76 / 23,784 | Screens. `review/` is ours; the rest is the inherited Lichess surface | screen widgets | application layer, widgets, model |
| `lib/src/widgets/`, `styles/`, `design/` | 65 / 12,827 | Reusable widgets, tokens, and the design package | — | material_ui, chessground |
| `lib/` total | 329 / 73,557 | | `lib/main.dart` → `lib/src/app.dart` | |
| `test/` | 188 / 51,543 | 1,598 test declarations | see §13 | |

Dependency direction is inward-only **with three known exceptions**: three
screens import the persistence layer directly instead of going through an
application provider —
`view/settings/srs_settings_screen.dart` (`db/database.dart`),
`view/review/study_chapters_screen.dart` (`persistence/study_repository.dart`)
and `view/analysis/analysis_hub_screen.dart` (`persistence/persistence.dart`).
This is tracked as item 14 in `docs/tech-debt-inventory.md`, not an intended
shortcut. Five screens also import `domain/` directly, which is allowed for
value types but should not grow into orchestration.

## 9. Data flow

### Flow A — import a PGN, then review it

1. **Pick a file** (`view/more/import_pgn_screen.dart`, `file_picker`).
2. **Parse**: `ReviewController` calls `importPgnAsync` / `importPgn`
   (`import/pgn_importer.dart:198,358`), which uses dartchess for legality,
   SAN and FEN. Multi-game PGN, RAV variations, comments, NAGs and starting
   FENs are handled; malformed input yields a structured `ImportError` and is
   reported, never silently dropped.
3. **Persist**: `StudyRepository.saveImportResult`
   (`persistence/study_repository.dart:21`) writes `srs_study`,
   `srs_chapter` and one `srs_decision` row per recallable branch — the whole
   tree goes into `srs_chapter.treeJson`, and per-move writes never rewrite it.
4. **Start a session**: `ReviewController` → `ReviewService.startSession`
   (`review/review_service.dart:157`) reads active studies, filters decisions
   by the chosen `ReviewScope`, and constructs a `ReviewSession` with the
   selected `Scheduler` and `Clock`.

### Flow B — answering one move (the critical path)

1. `ReviewController` forwards the board's move to `ReviewService.submitMove`
   (`review_service.dart:270`).
2. The service takes a `checkpoint()` of the session and calls
   `ReviewSession.submitMove` (`domain/review/review_session.dart:302`) — pure
   Dart, no I/O: legality against dartchess, lookup in the repertoire tree,
   branch selection, and the SRS transition computed by the injected
   `Scheduler`.
3. It returns a `ReviewStepResult` (correct / incorrect, the expected move,
   the comment to reveal, plus `sideEffectStates` for graph effects such as
   contagion and sibling updates).
4. **In SRS mode only**, the service maps each updated state to a
   `PositionKnowledgeState` and writes it with the review event — incremental,
   per answer. In `practice` mode this step is skipped entirely and nothing is
   written.
5. The controller updates the board and prompts the next due decision.

No step on this path performs network I/O. This is the invariant that makes
review work offline, and it is why the scheduler and clock are injectable:
tests drive the whole path deterministically with a fixed clock.

## 10. Data model

One SQLite database (Lichess schema v15, opened in `db/database.dart`). SRS
tables are created by `createSrsTables` (`persistence/srs_schema.dart`):

| Table | Key columns | Notes |
|---|---|---|
| `srs_study` | `id`, `title`, `createdAt`, `updatedAt`, `isActive`, `pgnHash` | `pgnHash` (indexed) deduplicates re-imports |
| `srs_chapter` | `id`, `studyId` FK→study (cascade), `sourceOrder`, `title`, `startingFen`, `treeJson`, `opening`, `orientation` | one row per chapter; the move tree lives in `treeJson` so a single move never rewrites the tree |
| `srs_decision` | `id`, `studyId`, `chapterId`, `nodeId`, `expectedMoves`, `canonicalStateId` | **the scheduled unit**: one row per branch the player must recall. `expectedMoves` holds multiple accepted moves; `canonicalStateId` links a node to a position's knowledge state |
| `position_knowledge_state` | `nextDueAt` (indexed), … | knowledge keyed by canonical position, so the same position reached by different move orders shares one schedule |
| `srs_review_state` | `nextDueAt` (indexed), … | per-decision SRS counters (first/last review, interval, lapses) |
| `srs_review_event` | `decisionId` (indexed), `whenTimestamp` (indexed) | append-only review log |

Relationships: study 1→N chapters 1→N decisions; decisions reference a
canonical position state; review events reference the decision they came from.
Foreign keys cascade on study/chapter delete.

**Position identity** is the normalised four-field FEN (placement, side to
move, castling rights, en-passant) — the "clean FEN" of §5, which is what makes
cross-move-order knowledge sharing and transposition handling possible. A
decision's canonical knowledge ID is `sha1("<fenKey>|<every accepted move,
sorted>")`: the answer set is part of the identity, so two *different questions*
asked at the same position keep separate schedules instead of being merged.
(The earlier format used only the first accepted move and could not tell them
apart — see the migration below.)

Two **one-shot data migrations** run after the schema upgrade and read/write
rows, so they run outside the schema batch:

- `canonical_rekey_migration.dart` — rewrites persisted `canonicalStateId`
  values and `position_knowledge_state` rows from the old first-move key format
  to the complete-answer-set format, recomputing from each chapter's stored tree
  and reading the answer set back from `srs_decision.expectedMoves` so the
  rewrite cannot drift from what was actually persisted. Without it every
  position would look never-reviewed and a user's accumulated intervals, due
  dates and history would silently reset. Idempotent.
- `opening_name_repair_migration.dart` — erases chapter "openings" that were
  really just titles mentioning an opening, keeping genuine ones.

## 11. External dependencies and integration points

| Integration | Where | Failure handling |
|---|---|---|
| Lichess HTTP API — `lichess.org`, `lichess1.org` (`constants.dart`, overridable via `--dart-define`) | `network/http.dart`; `HttpClientFactory` prefers Cronet on Android, `CupertinoClient` on iOS/macOS, and falls back to `dart:io` `HttpClient` in a `catch` | offline-first: nothing on the review path calls it; failures surface as errors in the Lichess-derived screens, and the factory degrades to the plain HTTP client |
| Lichess WebSocket — `socket.lichess.org` | `network/socket.dart` | study browsing is strictly in-memory and read-only; it never writes to SQLite (§2 invariant 6) |
| Lichess OAuth (PKCE) | `flutter_appauth`, `model/auth/auth_repository.dart` | app remains fully usable signed-out; only the Lichess-specific screens need it |
| Lichess explorer / tablebase | `explorer.lichess.org`, `tablebase.lichess.org` | advisory lookups; absence degrades to "no data", not an error state |
| Server availability | `network/server_status.dart` derives `ServerStatus` from HTTP **503 = maintenance, 502 = down** | status is informational; the local review loop is unaffected. `connectivity_plus` gates network-only affordances |
| Chess engine | `model/engine/` — native Stockfish and Fairy-Stockfish via `multistockfish`, Leela via `lc0` (both git-pinned, see `docs/dependency-audit.md` §4) | advisory only, never the Review judge (decision D005); `engine_failure.dart`, `engine_budget.dart` and a slot model keep a missing or crashing engine from breaking review |
| Bundled assets | `assets/chess_openings.db` (1.1 MB, copied out of the bundle on first use), `assets/maia/`, `assets/images/stockfish/`, `positions.json`, `endgames.json` | no network needed; the openings DB is versioned by filename and replaced on mismatch |

## 12. Design decisions and tradeoffs

The durable log is `docs/decisions.md` (D001–D017) and it is the authority;
this is a map of the ones that shape the code most:

- **D002 local-first** — the review path never touches the network (§9).
  Tradeoff: no cross-device sync yet (D009 scopes it as future work).
- **D003 / D013** — PGN is an input format and dartchess is the only chess
  representation. Tradeoff: domain code may not use chessground types, so
  adapters exist at the boundary.
- **D005** — the engine is advisory: a position is judged against the
  *repertoire*, not engine truth.
- **D007 / D008** — "learned" is never permanent exclusion, and there is no
  session-complete screen; review is an ongoing utility.
- **D015** — FSRS is implemented as one of three schedulers rather than
  replacing the ladder outright, which keeps the algorithm a setting
  (§3, verified in code).
- **D016** — visual identity is deliberately independent of Lichess Mobile,
  which is why `design/` exists alongside the inherited `styles/`.

Inferred (from code, not written down): the schema stores the move tree as
`treeJson` on the chapter row and writes decisions separately, which trades
queryability of the tree for the guarantee that a move never rewrites the whole
study — consistent with the incremental-persistence invariant in `QUALITY.md`.
Marked as inferred because no document states the choice explicitly.

## 13. Known limitations and technical debt

Full detail lives elsewhere; this is the signpost.

- `docs/tech-debt-inventory.md` — the scanned inventory, with impact/effort/risk
  and what was deliberately left out.
- `docs/dependency-audit.md` — every dependency, advisory check, and the staged
  upgrade plan. Both engine git pins are behind the branches they were waiting
  for.
- Boundary erosion: the three presentation→persistence imports listed in §8
  (item 14), and the four remaining duplications item 21 did not collapse.
- Verification is CI's job by design (`AGENTS.md` §3.1): `flutter analyze` and
  `flutter test` are the authority, and the gates (`scripts/gates.sh t1`) cover
  what tests do not. Anything documented here as "verified" was checked against
  the tree in this repository, not against a running build.
