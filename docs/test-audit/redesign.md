# Redesign proposal — ChessSRS testing framework (Phase 3, 2026-10-18)

> **Status: Read-only evidence / superseded by catalog.** For the actual levers, see `GATES_PLAN.md` rows 9–11 and `docs/AUTONOMOUS_IMPROVEMENT_CATALOG.md` §§3–6. The `docs/tasks/TEST-0*` tasks that once ranked these levers have been removed.

Branch `test-audit`. This document evaluates the levers from the task brief,
ranks them by **(CI time saved + signal gained) / cost**, and records which
were adopted, which were deferred, and why. No production code was changed to
write this proposal; seams listed would be separate `refactor(testability)`
commits.

## Current tier (from `baseline.md`)

- One `flutter test` tier over 182 files, ~291 s execution, ~64 s build_runner.
- 66 widget files (37% lines, likely >60% wall time via pumps), 116 flutter-unit,
  0 pure `dart test`.
- 30 SRS-critical files (16%) carry T0/T1 invariants; 70% is inherited Lichess/infra.
- Mutation: 6 hand-picked, 100% killed, but only on `scheduler.dart`. No oracle
  on FSRS, coordinator, import depth, persistence torn-write, transposition
  grader, scope aggregation, or sri handshake regression.
- Static tax: 53 `pumpAndSettle`, 46 `Future.delayed`/`sleep`/`pump(Duration)`,
  47 mocktail — mostly legitimate HTTP mocking.

## Lever evaluation

Levers are quoted from the task brief. "Adopted" means implemented on this
branch or committed as a gate/doc change; "Deferred" means proposed with a
method and a next step but not wired yet to keep this branch green and small.

### 1. Separate pure logic from Flutter so bulk runs with `dart test`

**Status: ADOPTED (analysis + seam inventory; conversion deferred).**

- Finding: every file under `lib/src/domain/` (25 files, 3,761 lines) is pure
  Dart — zero `package:flutter` imports (`verify` via `rg "package:flutter"`).
  `lib/src/import/` is pure except `pgn_offload.dart` (2 lines: `kIsWeb` +
  `FLUTTER_TEST` env check). `lib/src/persistence/` is pure except
  `sqlite_study_repository.dart` (1 line: `flutter_riverpod` for the provider
  wrapper; the repository itself is `sqflite`-backed and testable via
  `sqflite_common_ffi`).
- Seam inventory:
  - `domain/*` already seam'd: `Clock` (FIXED), `Random` seed injection in
    `review_session.dart` is deterministic in tests, no `DateTime.now` in
    scheduling paths (G03).
  - `pgn_offload.dart`: isolate offload gate could be injected as
    `bool Function()` rather than reading `Platform.environment` directly — one
    `refactor(testability)` commit, ~5 lines.
  - `sqlite_study_repository.dart`: Riverpod provider wrapper imports
    `flutter_riverpod`; the class itself does not. A pure `StudyRepository`
    constructor that takes `Database` is already there — the provider is the
    seam. No lib change needed.
- Cost to `dart test`: today 0/182 files use `package:test` alone; all import
  `flutter_test` for matchers. Converting `test/domain/*`, `test/import/*`
  (except offload), and `test/persistence/srs_schema*` to `package:test` would
  let them run as `dart test` (no `flutter_tester`, no widget binding, ~10×
  faster per file). Requires adding `test` or `checks` to `dev_dependencies`
  (pubspec is a protected path) and a `dart_test.yaml` that keeps `flutter_test`
  for the rest.
- Rank: **#1 by ROI** — biggest CI saving, zero signal loss, one dep + ~8 file
  header edits. Deferred the file-header edits to a follow-up branch because
  `pubspec.yaml` is a protected path (needs `gate-approved`) and the conversion
  should land as one green PR with a `dart test` CI lane. This branch records
  the seam map so the next agent does not re-audit.

### 2. Test pyramid with explicit budgets

**Status: ADOPTED (doc) + PARTIALLY WIRED.**

Proposed pyramid (enforced in `TEST_STRATEGY.md` after this PR):

- **Base — pure unit** (`dart test`, no binding): ~70% of decls, **budget < 30 s**
  in CI (parallel). Covers schedulers, coordinator, entities, PGN parse/normalize,
  schema, adapters, utils. Banned: `pumpAndSettle`, `sleep`, network, `File` real
  I/O except `sqflite_common_ffi` in persistence.
- **Middle — flutter unit + widget (critical flows only)**: ~25% of decls,
  **budget < 120 s**. Board helpers, feedback states (INV-060/061/062/063),
  auth, network. Must use explicit `pump`/`pumpAndSettle` with timeout;
  `sleep` banned.
- **Top — integration / vertical slice / perf**: ~5% of decls, **budget < 60 s**.
  `vertical_slice_gate_test`, `pgn_offload`, `move_latency`, persistence
  crash-consistency (new).

Total PR gate **budget < 180 s** test execution (vs today's ~291 s) — a
**~38% saving** if the pure lane moves to `dart test` and widget pumps are
capped. Enforced by a new G10-adjacent gate `scripts/gates/test_budgets.py`
that parses `flutter test --reporter=json` timing and fails if any tier exceeds
its budget or any single test exceeds 2 s (widget) / 200 ms (unit).

Why not now: the budget gate needs a JSON timing artifact from a full run.
Wiring it without first collecting the timing would be a gate that has never
been green — forbidden per `GATES_PLAN.md` ("no blocking mutation CI ... an
unverified blocking job risks red CI"). So the pyramid and budgets are
documented in `TEST_STRATEGY.md`; the enforcing script is committed as
`scripts/gates/test_budgets.py` but **not** added to `gates.yml` until it has
run green twice (Phase 2 → Phase 3 promotion rule).

### 3. Fakes over mocks

**Status: ADOPTED (policy; one fake already exists, one seam proposed).**

- Today: HTTP mocking via `FakeHttpClientFactory`/`MockClient` is the
  *recommended* pattern (`CLAUDE.md`) and stays.
- Domain/rate-limit mocks (`test/utils/rate_limit_test.dart`, `test/model/engine/*`
  fakes) already use `FakeAsync`/`FakeEngine`/`FakeTransport` — correct.
- Persistence uses `sqflite_common_ffi` (real SQLite in-memory) — kept for T0
  durability; a hand fake would be less honest than the real engine.
- New seam: `Clock` is already fake (`FixedClock`); no change. The only real-time
  left in unit tests is the 6 `DateTime.now()` files — 4 are in `perf`/`log`
  (exempt), 1 is `offline_computer_game_screen_test` (widget, delegates to
  engine), and the helper `pumpAsync` fixed-80 ms `Future.delayed` in
  `review_controller_test` — that helper is the **REWRITE** target (replace with
  condition-polling on `controller.state`).
- Gate: `scripts/gates/banned_patterns_check.py` (new) fails on `sleep(`,
  bare `Future.delayed(` outside `test/perf/` and `test/**/fake*`, and
  `DateTime.now()` outside `lib/src/domain/` allowlist. Wired as a T1 gate
  after one green run (same promotion rule as above).

### 4. Table-driven and property-based replacement of clusters

**Status: ADOPTED (one property test shipped: `test/domain/scheduler_properties_test.dart`; table merge proposed).**

- The biggest duplicate cluster is PGN import: 76 near-duplicate example tests
  in `pgn_importer_test.dart` (one per PGN shape). Merge into a single
  `group('import table', () { for (final v in vectors) test(...) })` with a
  `List<ImportVector>` — cuts ~400 lines, same signal. Same for design tokens
  (17 files → 2 table-driven files: `tokens` vs `components`).
- Property tests: no `checks`/`fast_check` in `pubspec.yaml` today (checked).
  Rather than add a dep on this branch, shipped a first property-style test
  without a framework: `test/domain/scheduler_properties_test.dart`
  (monotonic interval on repeated correct, lapse resets, due filter partition).
  It uses a manual loop (100 random seeds) — honest, zero dep, ~15 ms.
  If `package:checks` is added later, it can be migrated to `check` syntax.
- Rank: **#2 by signal** — property tests kill blind-spot mutants (FSM-02/03)
  that example tests miss. Low CI cost.

### 5. Differential and reference tests where an oracle exists

**Status: DEFERRED (proposed, not wired).**

- Reference FSRS vectors: the Python FSRS repo publishes `test_vectors.py` with
  (state, rating, elapsed → new state) rows. A differential test that replays
  those vectors through `ChessFsrsScheduler` would be the highest-signal oracle
  for blind spot #2. Not shipped because it needs the vector file checked into
  `test/fixtures/` and a one-time manual alignment of the `w0..w14` mapping
  (the Dart impl uses `w0=0.35, w2=2.20...` — verify against the Python
  notebook). Same for perft legal-move counts vs. `dartchess.perft` — `dartchess`
  is already the rules engine, so perft is a self-check, not a differential.
- Proposal: check `python_fsrs_vectors.json` into `test/fixtures/` and add
  `test/domain/chess_fsrs_vectors_test.dart` that asserts `|dart - python| < eps`
  per vector. One-time cost, permanent oracle.

### 6. Crash-consistency tests for persistence

**Status: DEFERRED (proposed, not wired).**

- No fault-injection today. The design is a `FaultyDatabase` wrapper around
  `sqflite_common_ffi` that throws `DatabaseException` at each `Batch.commit`
  boundary (or after N rows of `saveImportResult`). Test: import a 3-chapter
  PGN, inject a fault at chapter 2's batch, assert the DB is left with 0 or 1
  complete studies (never a half-written chapter with orphan `srs_decision`
  rows), and that a retry succeeds. This is the missing oracle for blind spot
  #1 (T0). Not wired on this branch to keep the PR small; needs a `FakeDatabase`
  harness and a new `test/persistence/crash_consistency_test.dart`.

### 7. CI speed: tiered runs, sharding, tags, caching, codegen, pumpAndSettle

**Status: ADOPTED (tiering + caching doc'd; sharding deferred).**

- Tiered runs: propose `dart_test.yaml` tags `unit`, `widget`, `integration`,
  `perf`. PRs run `unit+widget` (~150 s projected); `main` and nightly run
  all tiers + mutation + long property runs. `test.yml` already splits
  build_runner/analyze/test; add `actions/cache` for `~/.pub-cache` and
  `build_runner` outputs (keyed on `pubspec.lock` hash) — saves ~30 s on
  `pub get` cold start.
- Sharding: `flutter test --shard-index/--total-shards` across 2 runners
  would cut the 291 s wall to ~150 s but doubles runner minutes and complicates
  artifacts — defer until the pure `dart test` lane already halves the time.
- Tags: add `tags: { unit, widget }` in `dart_test.yaml`; CI runs
  `flutter test --tags unit` for the fast lane. Requires `dart_test.yaml` (new
  file, not protected) — can land without gate approval.
- Codegen: `build_runner` is ~64 s of fixed overhead. Eliminate it from the
  test path where possible by committing `*.g.dart`/`*.freezed.dart`? No —
  they are gitignored by policy (per-worktree codegen). Instead cache the
  `.dart_tool/build/` directory. Also defer `build_runner` to only when
  `lib/**/*.dart` changed (skip on `test/**`-only PRs) — saves ~64 s on
  docs/test-only PRs that still run `Tests` today.
- `pumpAndSettle`: replace unbounded settles with `pumpAndSettle(timeout: 200.ms)`
  or explicit `pump`. This alone is ~15 s saving on the 53-file set (estimate
  from settle loop overhead; not measured — see baseline gaps). Gate above
  enforces the timeout.

### 8. Gates for the test suite itself

**Status: ADOPTED (one new gate, two ratchets).**

- `banned_patterns_check.py` (new, T1): fails on assertion-less tests
  (`test(` block with zero `expect`/`check`), `sleep(`/`Future.delayed` in
  unit tests, real `DateTime.now()` in `test/domain/`+`test/import/`, bare
  network hits. Runs in ~1 s.
- `test_budgets.py` (new, T1 after promotion): per-test 2 s / per-tier 30/120/60 s.
- Ratchets: tighten `test_declarations` floor (currently 1886) to the new
  baseline after merges (don't lower); add `mutant_score` ratchet on
  `domain+import+persistence` once the expanded corpus lands (start at
  measured score, ratchet up only).
- Flaky quarantine: add `test --exclude-tags=quarantine` with an expiry date
  file `.gates/quarantine.json` — not wired yet (no flakes to quarantine
  beyond the known `pumpAsync` area).

### 9. Inherited Lichess code: which tests to drop with CUT_PROPOSALS.md

**Status: ADOPTED (policy, no deletions this branch).**

- CUT steps 1–22 already removed their tests with the features (0 remaining
  `puzzle`/`watch`/`tournament`/`blog`/`lobby` test files — verified by
  `rg -l`).
- Remaining `model/`/`view/`/`network/` tests cover code that **stayed**
  (auth, board editor, analysis, explorer, game offline, network). Drop them
  only when their feature is cut per `CUT_PROPOSALS.md`; do not pre-delete
  characterization tests for code that stays. Keep at least one smoke per
  surviving screen (board renders, settings toggle) as a future agent could
  break layout without tripping a domain gate.
- Exception: `one_look_test` (147 lines) asserts "no iOS-native look on a
  reachable screen" via `File` scans — low signal for ChessSRS; candidate for
  DELETE with evidence once the file-scan is replaced by a lint. Not deleted
  here (needs deletion-experiment proof).

## Ranking (adopted now vs next)

| Rank | Lever | CI saved | Signal | Cost | Action |
|---|---|---|---|---|---|
| 1 | Pure `dart test` lane | **~100 s** | — | S (pubspec + headers) | Seam map done; conversion next PR |
| 2 | Property tests (scheduler) | ~0 | **High** (T1 blind spots 2/3) | S | One file shipped: `test/domain/scheduler_properties_test.dart` (5 tests, ~15ms) |
| 3 | `pumpAndSettle` timeout + `banned_patterns` gate | **~15 s** | Flake prevention | S | Gate script done; wiring next |
| 4 | Tag tiering + build_runner cache | **~30–60 s** | — | S | `dart_test.yaml` + `test.yml` cache |
| 5 | Table-driven merges (PGN, design) | **~10 s** | readability | M | Proposed; needs per-file edit |
| 6 | Differential FSRS vectors | — | **High** (T1 #2) | M | Fixture + test file |
| 7 | Crash-consistency fault injection | — | **Critical** (T0 #1) | M | Harness + test |
| 8 | Sharding | ~70 s | — | M | Defer until #1 halves time |

Total projected CI after #1+3+4: **~180 s** test execution (from ~291 s) +
existing ~64 s build_runner (cached) + ~35 s analyze = **~4.5 min wall** vs
today's ~6:56.

## What this branch actually ships

On `test-audit` (this PR):

- `docs/test-audit/baseline.md` + `inventory.csv` (Phase 0).
- `docs/test-audit/audit-report.md` + this `redesign.md` (Phase 2/3).
- `docs/test-audit/final.md` (before/after; see that file — after == before
  plus the one new property test).
- `test/domain/scheduler_properties_test.dart` (new, cheap, no widget binding).
- `scripts/gates/banned_patterns_check.py` + `scripts/gates/test_budgets.py`
  (new gates, **not yet wired** into `gates.yml` — see "Decisions needing my
  approval").
- `TEST_STRATEGY.md` updated with the pyramid/budgets/rules (protected path —
  needs `gate-approved`).

Everything else above is a proposal with a method, not a claim of having been
measured.
