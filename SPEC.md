# SPEC: what must always be true

Human-owned. Protected path: edits need a dedicated `spec-change` PR and human
review. Gates verify the code conforms to this spec; they cannot tell you the
spec is right, so read every line as a contract.

How to use
- One invariant = one falsifiable sentence with a stable ID (`INV-001`, never
  renumbered or reused). Retire with `RETIRED (reason, date)`, never delete.
- Every invariant names its oracle (how a violation is detected) and its gates.
- Tests cite the ID (`// SPEC INV-012.`) so `spec_trace_check.py` verifies
  coverage. The check proves coverage of intent, not test quality.
- Tier legend: T0 = loss/corruption/security, T1 = wrong behavior,
  T2 = degraded UX/perf.

The T0/T1 invariants below transcribe `QUALITY.md` (already
owner-authoritative) and mined regressions (see GATES_PLAN.md §1 and the
`History` notes). Merging this file is the owner's confirmation.

---

## A. Persistence and integrity (T0)

### INV-001 An acknowledged review answer survives process restart
A graded move persisted by `ReviewService` is present with identical state
after the database is closed and reopened.
- Oracle: durability test closing and reopening the sqflite store.
- Gates: persistence suite, G05 traceability.
- Tier: T0. Covering: `test/persistence/sqlite_study_repository_test.dart`.

### INV-002 Review writes are incremental
Answering a move writes review state and the review event only; the study
tree blob is never rewritten per move.
- Oracle: write-scope assertion on the repository.
- Gates: review service suite, persistence suite.
- Tier: T0. Covering: `test/review/review_service_test.dart`,
  `test/persistence/sqlite_study_repository_test.dart`.

### INV-003 Re-importing identical repertoire material creates nothing new
Importing a PGN whose canonical tree hash matches an existing study switches
to that study without inserting duplicate studies, chapters, or decisions.
- Oracle: duplicate-import tests incl. header-rename and FEN-start cases.
- Gates: import suite, persistence `getStudyByPgnHash` tests.
- Tier: T0. Covering: `test/import/pgn_importer_test.dart`,
  `test/review/review_controller_test.dart`.

### INV-004 Deleting a study never removes memory shared with survivors
`deleteStudy` cascades to its own decisions, states, and events, but keeps
canonical knowledge states and events still referenced by other studies
(transpositions) and cleans chapter deletes the same way.
- Oracle: cross-study delete tests with transposed positions.
- Gates: persistence suite.
- Tier: T0. Covering: `test/persistence/sqlite_study_repository_test.dart`.

### INV-005 Every shipped schema version upgrades without data loss
Migrations from each shipped version preserve all rows and derived
identities (`canonicalStateId`, difficulty, orientation, `pgnHash`).
- Oracle: migration tests per shipped version plus rekey/backfill tests.
- Gates: persistence suite (tier-2 on schema changes).
- Tier: T0. Covering:
  `test/persistence/sqlite_study_repository_test.dart`,
  `test/persistence/canonical_rekey_migration_test.dart`.

### INV-006 Authentication secrets never travel in URLs or logs
Email login code, email, and username are sent in the POST body, never as
query parameters, so they cannot land in proxy logs or the `http_log` table.
- Oracle: repository tests asserting request construction.
- Gates: auth suite.
- Tier: T0. History: PR #94 (query-string leak into 7-day log table).
- Covering: `test/model/auth/auth_repository_test.dart`,
  `test/view/auth/email_login_screen_test.dart`.

### INV-007 The startup session check only ever clears its own session
The `/api/token/test` result is fenced on controller generation and session
identity: a response that arrives after sign-in never signs out the newer
session, and in-memory auth state is cleared together with storage.
- Oracle: identity-fencing tests incl. sign-in-during-flight.
- Gates: auth suite.
- Tier: T0. History: unfenced startup check signed users straight back out.
- Covering: `test/model/auth/auth_identity_fencing_test.dart`,
  `test/model/auth/startup_token_check_test.dart`.

### INV-008 Only the configured host is treated as first-party
App links whose host merely shares a prefix with the Lichess host are not
handled as trusted navigation.
- Oracle: hostile-prefix link tests.
- Gates: app-links suite.
- Tier: T0. Covering: `test/app_links_service_test.dart`.

## B. Import pipeline (T0/T1)

### INV-010 Variations are preserved as first-class branches
Recursive annotation variations become sibling children under their parent
node; import never flattens or silently drops a branch at any depth.
- Oracle: variation-structure tests (children counts, order, subtrees).
- Gates: import suite, exporter round-trip.
- Tier: T0. Covering: `test/import/pgn_importer_test.dart`,
  `test/domain/entities_test.dart`, `test/import/pgn_exporter_test.dart`.

### INV-011 Malformed input is quarantined, never half-applied
An illegal move or bad FEN yields a typed error naming chapter title and move
index, truncates only the affected chapter, and leaves later valid chapters
imported; empty or non-PGN input is refused outright.
- Oracle: malformed-PGN and empty-input tests.
- Gates: import suite, controller import tests.
- Tier: T0. Covering: `test/import/pgn_importer_test.dart`,
  `test/review/review_controller_test.dart`.

### INV-012 Custom starting positions are honored and normalized
`SetUp`/`FEN` headers set the chapter root; the root identity is the
dartchess-normalized FEN and legality is judged from that position.
- Oracle: custom-FEN import tests.
- Gates: import suite.
- Tier: T1. Covering: `test/import/pgn_importer_test.dart`.

### INV-013 Each chapter trains from its own side
Orientation resolves per chapter: explicit `Orientation` header first, then
title keywords, then player tags with placeholder opponents, defaulting to
White; an explicit side choice overrides the heuristic.
- Oracle: orientation matrix tests plus multi-chapter mixed-side import.
- Gates: import suite.
- Tier: T1. Covering: `test/import/chapter_orientation_test.dart`,
  `test/import/pgn_importer_test.dart`.

### INV-014 Export then re-import preserves repertoire identity
Serializing a study or chapter to PGN and importing it back keeps chapters
distinguishable with their titles, openings, orientations, and variations.
- Oracle: exporter round-trip tests.
- Gates: import/export suites.
- Tier: T0. History: titles collapsed to one name, `[Opening]` dropped.
- Covering: `test/import/pgn_exporter_test.dart`,
  `test/import/pgn_importer_test.dart`.

### INV-015 Position identity is the normalized 4-field FEN
Placement, side to move, castling rights, and en-passant square define a
position; clocks and move counters do not.
- Oracle: `fenKey` stripping tests and canonical-key determinism tests.
- Gates: domain suite, import suite.
- Tier: T0. Covering: `test/import/pgn_importer_test.dart`,
  `test/domain/position_knowledge_state_test.dart`.

### INV-016 Transpositions share one memory
Two studies reaching the same position with the same accepted replies review
a single canonical state: progress in one is visible in the other and the
all-studies queue asks it once.
- Oracle: cross-study transposition sharing tests.
- Gates: domain suite, review service suite.
- Tier: T1. Covering: `test/domain/position_knowledge_state_test.dart`,
  `test/review/review_service_test.dart`,
  `test/review/review_engine_test.dart`.

### INV-017 Accepted-reply sets distinguish memories
The same position with different expected replies is a different question
with independent history; scheduling follows the asked question, never a
colliding single-move lookup.
- Oracle: accepted-set separation and scheduled-against-asked tests.
- Gates: domain suite, review engine suite.
- Tier: T1. History: shared history last-write-wins across two questions.
- Covering: `test/domain/position_knowledge_state_test.dart`,
  `test/domain/graph_aware_review_coordinator_test.dart`,
  `test/review/review_engine_test.dart`.

## C. Review engine and SRS (T1)

### INV-020 Correctness means matching the repertoire
A played move is correct exactly when it matches a repertoire child of the
prompt position (castling forms equivalent per INV-033); engine-optimality
never judges, and opponent inaccuracies remain valid content.
- Oracle: correct/incorrect grading tests against repertoire trees.
- Gates: review engine suite, controller suite.
- Tier: T1. Covering: `test/review/review_engine_test.dart`,
  `test/review/review_controller_test.dart`.

### INV-021 A lapse is recoverable in place
A wrong move records a lapse, reveals the expected move and comment, keeps
the board interactive for an immediate reguess, and requeues the item; the
item is not dropped at lapse or at retry-correct, only on re-test pass.
- Oracle: lapse/reguess/re-test lifecycle tests.
- Gates: review engine suite, controller suite.
- Tier: T1. Covering: `test/review/review_engine_test.dart`,
  `test/review/review_controller_test.dart`.

### INV-022 Traversal is never exclusion
Learned non-due moves auto-traversed during review become active questions
again once due; due-aware opponent-branch choice steers toward due material
without starving any branch.
- Oracle: auto-traversal and due-aware-branch tests with a fixed clock.
- Gates: review engine suite.
- Tier: T1. Covering: `test/review/review_engine_test.dart`.

### INV-023 Practice mode writes nothing
Review in practice (rehearsal) mode grades and traverses identically to SRS
mode but performs zero writes to review states and logs zero events.
- Oracle: practice-mode no-mutation tests at engine and controller level.
- Gates: review engine suite, controller suite.
- Tier: T1. Covering: `test/review/review_engine_test.dart`,
  `test/review/review_controller_test.dart`.

### INV-024 Scheduling is a pure function of state, event, and time
The same review history replayed through a scheduler yields byte-identical
state; schedulers never read the wall clock or unseeded randomness.
- Oracle: FixedClock replay tests; G03 clock rule; boundary test.
- Gates: scheduler suites, G03, G02 boundary test.
- Tier: T1. Covering: `test/domain/scheduler_test.dart`,
  `test/domain/chess_fsrs_scheduler_test.dart`,
  `test/gates/domain_boundary_test.dart`.

### INV-025 Success grows the interval, lapses restart it
Successful recalls lengthen the interval along the scheduler curve; a lapse
resets the streak and schedules a short-interval retry with recovery.
- Oracle: interval-ladder and lapse-recovery tests.
- Gates: scheduler suites.
- Tier: T1. Covering: `test/domain/scheduler_test.dart`,
  `test/domain/chess_fsrs_scheduler_test.dart`.

### INV-026 Intervals stay within configured bounds
No interval exceeds `maxInterval`; ChessFSRS parameters compare by value so
settings changes reload the active session.
- Oracle: clamp tests and params-equality tests.
- Gates: scheduler suites, controller scheduler-reload test.
- Tier: T1. History: `ChessFsrsScheduler==` ignored params, reload never fired.
- Covering: `test/domain/scheduler_test.dart`,
  `test/domain/chess_fsrs_scheduler_test.dart`,
  `test/review/review_controller_test.dart`.

### INV-027 Lapse contagion is bounded and skips the unlearned
An incorrect move softens stability of learned descendants along the line
only, by a decaying factor; cold or never-reviewed nodes are untouched.
- Oracle: contagion scope tests.
- Gates: coordinator suite, engine suite.
- Tier: T1. Covering:
  `test/domain/graph_aware_review_coordinator_test.dart`,
  `test/review/review_engine_test.dart`.

### INV-028 Traversal credit is micro, throttled, and never for due items
Auto-traversed moves earn at most a bounded micro-stability bump, at most
once per calendar day, and already-due items are refused outright.
- Oracle: credit/throttle/refusal tests.
- Gates: coordinator suite, engine suite.
- Tier: T1. Covering:
  `test/domain/graph_aware_review_coordinator_test.dart`,
  `test/review/review_engine_test.dart`.

### INV-029 Siblings couple only on genuine confusion
A wrong move that matches an alternative repertoire continuation raises that
sibling's difficulty; other wrong moves cause no coupling.
- Oracle: confusable-sibling tests.
- Gates: coordinator suite, engine suite.
- Tier: T1. Covering:
  `test/domain/graph_aware_review_coordinator_test.dart`,
  `test/review/review_engine_test.dart`.

### INV-030 Scopes filter exactly
`all()` and the due count see active studies only; `opening()` aggregates
across studies with name normalization; `chapter()` isolates one chapter;
inactive studies stay openable directly.
- Oracle: scope-filter and normalization tests.
- Gates: review service suite, scope suite, controller toggle tests.
- Tier: T1. Covering: `test/review/review_service_test.dart`,
  `test/domain/review_scope_test.dart`,
  `test/review/review_controller_test.dart`.

### INV-031 The daily quota counts positions, not guesses
Distinct positions reviewed today (local-midnight boundary) count once each
toward `maxDailyReviews`; mistakes and reguesses add nothing further, while
an in-flight lapse may always conclude.
- Oracle: quota-counting and midnight-edge tests.
- Gates: review engine suite, persistence suite, controller cap test.
- Tier: T1. Covering: `test/review/review_engine_test.dart`,
  `test/persistence/sqlite_study_repository_test.dart`,
  `test/review/review_controller_test.dart`.

### INV-032 Stale sessions never take over
A session whose scope changed or whose generation was superseded mid-flight
resolves without activating and without writing another scope's dues.
- Oracle: generation/staleness tests.
- Gates: controller suite, service ownership tests.
- Tier: T1. History: one scope's dues written onto another after a switch.
- Covering: `test/review/review_controller_test.dart`,
  `test/review/review_service_test.dart`.

### INV-033 Castling notations are equivalent
Standard UCI (`e1g1`, `e1c1`, …) and king-takes-rook (`e1h1`, `e1a1`, …) forms
of the same castling match each other in grading and tree lookup.
- Oracle: castling-equivalence and on-board O-O acceptance tests.
- Gates: entities suite, engine suite, controller suite.
- Tier: T1. Covering: `test/domain/entities_test.dart`,
  `test/review/review_engine_test.dart`,
  `test/review/review_controller_test.dart`.

### INV-065 A repertoire move played out of line is accepted when its position is in scope
A legal move that matches no expected continuation is still graded correct
when the position it reaches exists in the active scope's repertoire tree;
review continues from the transposed line. Out-of-scope targets and illegal
moves stay incorrect, exactly as before.
- Oracle: transposition acceptance tests in
  `test/review/review_transposition_test.dart`.
- Gates: review engine suite, G05 traceability.
- Tier: T1. Covering: `test/review/review_transposition_test.dart`.
- History: 2026-10-03, owner-requested review-time transposition support
  (P-TRANSPOSE); memory sharing across transpositions already existed (R2),
  grading did not.

## D. Architecture and determinism (T1)

### INV-040 The domain layer is pure Dart
`lib/src/domain/` imports no Flutter, chessground, sqflite, or I/O
libraries; dartchess core types arrive through thin adapters only.
- Oracle: import-boundary scan (G03) plus the in-suite boundary test.
- Gates: G03, G02 boundary test, analyzer.
- Tier: T1. Covering: `test/gates/domain_boundary_test.dart`.

### INV-041 Scheduling and review paths take time only through Clock
No `DateTime.now` appears in schedulers, the graph coordinator, review
state, or the review session; production time enters via `Clock`.
- Oracle: clock-rule scan (G03) plus FixedClock tests.
- Gates: G03, scheduler suites.
- Tier: T1. Covering: `test/gates/domain_boundary_test.dart`,
  `test/domain/scheduler_test.dart`,
  `test/review/review_engine_test.dart`.

### INV-042 The domain layer performs no I/O
No `dart:io`, HTTP, or socket import appears in `lib/src/domain/`; the
domain computes, adapters persist and fetch.
- Oracle: import-boundary scan plus the in-suite boundary test.
- Gates: G03, G02 boundary test.
- Tier: T1. Covering: `test/gates/domain_boundary_test.dart`.

### INV-064 Every socket handshake carries the session sri
`SocketClient` appends the session `sri` to the connect URL as a query
parameter on every connection attempt, so the server attributes the socket
to the session instead of refusing the handshake.
- Oracle: `connects with the sri in the query string` in
  `test/network/socket_test.dart`, which records requested URLs — the fake
  channels key on path alone and cannot see a missing query string.
- Gates: network suite (G04), G05 traceability.
- Tier: T1. Covering: `test/network/socket_test.dart`.
- History: 2026-10-02, every handshake refused with HTTP 400 while the suite
  stayed green (#129); the invariant itself was blocked until G-BASEINV was
  fixed (#135/#137).

## E. Performance budgets (T2)

### INV-050 A graded move settles within one frame
Move legality, repertoire lookup, grading, and persistence apply inside a
single display frame on the reference path.
- Oracle: wall-clock assertion over a graded-move batch.
- Gates: latency suite; future pinned-benchmark ratchet.
- Tier: T2. Covering: `test/review/move_latency_test.dart`.

### INV-051 Bulk lookups stay bounded
Review-state reads and deletes are chunked (400-item SQLite batches) and the
due queue prefetches in bounded batches with refill thresholds, so startup
and session build do not deserialize the whole database.
- Oracle: chunked-delete, targeted-loading, and prefetch/refill tests.
- Gates: persistence suite, review engine suite.
- Tier: T2. Covering:
  `test/persistence/sqlite_study_repository_test.dart`,
  `test/review/review_service_test.dart`,
  `test/review/review_engine_test.dart`.

## F. Review UX contract (T1/T2)

### INV-060 Every verdict is announced to screen readers
Correct answers announce `Correct. {san}.` and lapses announce
`Not this move. The repertoire move is {san}.`; silence holds before grading
and the announcement clears on advance.
- Oracle: live-region widget tests for both verdicts, silence, and clearing.
- Gates: review screen suite.
- Tier: T2. History: correct answers announced nothing at all.
- Covering: `test/view/review/review_screen_test.dart`.

### INV-061 Feedback stays readable in both themes
Filled controls render label ink readable on their fill, and board light/dark
squares keep their ordering in dark mode.
- Oracle: contrast and square-order widget tests.
- Gates: design suites.
- Tier: T2. History: ink-on-ink pill label; swapped dark-mode squares.
- Covering: `test/design/design_primitives_test.dart`,
  `test/design/board_squares_test.dart`.

### INV-062 Interactive targets stay tappable
Controls meet the 44px minimum and survive narrow viewports without clipping
(e.g. the practice-exit target, pill heights, action sheets scroll).
- Oracle: size/viewport widget tests.
- Gates: design suites, review screen suite.
- Tier: T2. History: 12px exit label, 23px pills, clipped delete action.
- Covering: `test/design/practice_exit_test.dart`,
  `test/design/design_primitives_test.dart`,
  `test/view/review/review_screen_test.dart`.

### INV-063 Comment shapes never leak during recall
PGN arrows and circles are withheld from the board while the prompt is open
and appear only after grading (or never, when annotations are disabled).
- Oracle: pre-guess empty-shapes and post-lapse shape assertions.
- Gates: review screen suite.
- Tier: T1. Covering: `test/view/review/review_screen_test.dart`.

---

## Change log
| Date | Invariant | Change | Reviewer |
|------|-----------|--------|----------|
| 2026-10-01 | all | Initial SPEC transcribed from QUALITY.md + mined regressions | (owner, on merge) |
| 2026-10-03 | INV-064 | Added: socket handshake carries session sri (escape #129) | (owner, on merge) |
| 2026-10-03 | INV-065 | Added: out-of-line repertoire moves accepted when in scope (P-TRANSPOSE) | (owner, on merge) |
