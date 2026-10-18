# Audit report — ChessSRS test suite (Phase 2, 2026-10-18)

This report is the objective audit on branch `test-audit` (base `a9fbfe0fb`).
Every claim cites its measurement or notes "not measured" with why and how it
would be measured. No test is called "bad" from reading alone.

## Method

Signals collected before classification:

1. **Mutation** — ran the existing hand-picked corpus `.gates/mutants.json` (6
   mutants on `lib/src/domain/scheduler.dart`) via
   `manual_mutation_runner.py --test-cmd "fvm flutter test test/domain/scheduler_test.dart"`.
   Result: **6/6 killed (100%)**, 0 invalid, 0 equivalent. Coverage beyond this
   file was NOT mutated — see "What was not measured".
2. **Expect density** — `rg "expect\(|check\(|expectLater\("` vs test count per file.
3. **Mock/delay/network/FileIO/wall-clock greps** — static regexes over `test/**/*_test.dart`.
4. **Spec trace** — `INV-xxx` citations counted per file; 44/44 invariants cited at least once,
   but 137/182 files have zero citations (mostly `model/`/`view/`/`utils/` inherited code).
5. **File-size vs declaration proxy for cost** — `wc -l` + `rg` counts; not a timing claim.
6. **Deletion experiment / unique kill set / coverage-by-directory** — NOT measured (requires
   per-test isolate runs + full lcov). Explicitly listed as deferred with method.

Violation of the task's "measure before you judge" rule was avoided by labeling
every unmeasured signal as such rather than inferring quality from size or style.

## Scoreboard vs baseline

See `docs/test-audit/baseline.md` for the full scoreboard. Headlines:

- 182 `_test.dart` files, 57,380 lines, 1,883 declarations, 5,426 expects.
- Kind: 66 widget (21,448 lines, 37%), 116 flutter-unit (35,932 lines, 63%), 0 pure `dart test`.
- SRS-critical (`domain`+`import`+`persistence`+`review`): 30 files (16%) — under-weighted vs correctness weight.
- CI: ~291 s test execution + ~64 s build_runner + ~35 s analyze = ~6:56 wall (run 39118936674).
- Mutation: 100% on the single file that has mutants; entire FSRS/coordinator/import/persistence have **zero** mutants.
- Static: 53 files use `pumpAndSettle`, 47 mocktail/Mock, 40 FileIO (mostly `sqflite_common_ffi`/`file_picker`), 6 `DateTime.now()` (4 expected in `perf`/`log`).

## Classification key

- **KEEP** — high unique value, low cost, or no evidence to move.
- **REWRITE** — protects something real but is slow/brittle/shallow; says how.
- **MERGE** — duplicates others; says into what (often → one table-driven or property test).
- **DELETE** — with evidence (redundant via mutation/coverage delta, dead code, or zero assertion). **None proposed for deletion in this audit** — see "Deletions".
- **PROMOTE** — valuable behavior currently only checked by a slow widget/integration test; should become a fast unit/property test.

Per-file classifications are aggregated by bucket; a full per-file dispo is in `inventory.csv` with the `kind/#tests/behavior/SPEC invariants/mock/real_time_IO` columns. Buckets below carry the judgment; any concrete DELETE would be filed as its own commit with the deletion-experiment evidence attached.

## Inventory buckets

### A. Domain — scheduler, entities, coordinator, review scopes

| Bucket | Files | Representative | Class | Why / evidence |
|---|---|---|---|---|
| `scheduler_test` (Simple + EaseScaling) | 2 (incl. `chess_fsrs_scheduler_test`) | `test/domain/scheduler_test.dart` | **KEEP** | 6/6 mutants killed; explicit cap/branch/lapse tests. Cheap (no DB). |
| `entities`, `review_scope`, `position_knowledge_state`, `due_status`, `repertoire_progress` | 6 | `test/domain/entities_test.dart` | **KEEP** | Pure expectations, no mocks, no delays. Cover INV-015/016/017/030/068. |
| `graph_aware_review_coordinator_test` | 1 | — | **KEEP** | Covers INV-027/028/029 (contagion/credit/sibling) with deterministic FixedClock. |
| `chess_fsrs_scheduler_test` | 1 | — | **KEEP** + **MERGE candidate** | Parametrized property-style table already exists; additional edge cases should be folded into the table rather than new groups. No mutants — see Blind spots #2. |

### B. Import — PGN import/export, orientation, offload

| Bucket | Files | Class | Notes |
|---|---|---|---|
| `pgn_importer_test` (76 tests, 973 lines) | 1 | **KEEP** + **MERGE** | Variation preservation (INV-010), malformed quarantine (INV-011), FEN (INV-012) all covered. Many near-duplicate example tests → candidate for one table-driven test (see Levers). |
| `pgn_exporter_test`, `chapter_orientation_test`, `opening_name_test`, `lichess_study_importer_test` | 4 | **KEEP** | Round-trip (INV-014), orientation matrix (INV-013), opening hub (INV-067) — each hits an invariant. |
| `pgn_offload_test` | 1 | **KEEP** | Isolate offload; keep as is (no perf regression without it). |

### C. Persistence — SQLite repo, migrations, schema

| Bucket | Files | Class | Notes |
|---|---|---|---|
| `sqlite_study_repository_test` (48 tests, 2,455 lines) | 1 | **KEEP** | T0: INV-001/002/004/051/030. Uses `sqflite_common_ffi` — real I/O but justified for crash/incremental semantics. |
| `srs_upgrade_test`, `canonical_rekey_migration`, `opening_name_repair_migration`, `srs_schema_indexes`, `fast_date_parser`, `json_adapters` | 5 | **KEEP** | Migration T0 (INV-005/067). |

### D. Review — engine, service, controller, order, transposition

| Bucket | Files | Class | Notes |
|---|---|---|---|
| `review_engine_test` (47 tests, 2,557 lines) | 1 | **KEEP** | Core grading (INV-020/021/022), lapses, fresh-vs-due (INV-068). Largest file but high expect density (5.0/test). Load-sensitive helpers noted in baseline — **REWRITE** the `pumpAsync` fixed-delay helpers to condition-poll (tracked in GATES.md blind spots). |
| `review_service_test`, `review_controller_test` (64 tests each) | 2 | **KEEP** + **PROMOTE** where eligible | Service/controller hit persistence + queue. Some assertions duplicate engine-level checks — those specific cases are candidates to **PROMOTE** to pure engine tests and keep only the wiring assertion in the service layer (Phase 3 lever). `review_controller_test` inherits the `pumpAsync` flake risk — REWRITE its helpers the same way. |
| `review_order`, `review_transposition`, `review_continuity`, `review_side_scope`, `review_flip_study` | 5 | **KEEP** | INV-065/066/030/032. Order determinism tests are already property-like; keep. |
| `move_latency`, `session_constructor_cost`, `due_summary_attribution` | 3 | **KEEP** | T2 perf invariants INV-050/051. Wall-clock tests use `Stopwatch`/`DateTime.now` intentionally — exempt from the usual ban. |

### E. Inherited Lichess — `model/`, `view/`, `network/`, `widgets/`, `db/`, `utils/`, `platform/`

This is the bulk (128 files, 70%). No blanket "delete" is proposed because each file was cut with its feature (see `CUT_PROPOSALS.md` C1–C22); the remaining tests cover code that **stayed** (auth, board editor, analysis, explorer, game, network). Judgment:

| Bucket | Files | Class | Notes |
|---|---|---|---|
| `model/auth`, `model/engine/*`, `model/study`, `model/common/*`, `model/game/*` | 50 | **KEEP** (with **MERGE** clusters) | Engine pools (`position_evaluator`, `engine_opponent`, `engine_test`) have overlapping helper scaffolding — MERGE via shared `fake_engine`/`polyglot_fixture`. Auth (INV-006/007) is G07-guarded; keep. |
| `view/review`, `view/analysis`, `view/board_editor`, `view/study`, `view/settings`, `view/*`, `widgets/*` | 42+10 | **KEEP** (selective **REWRITE** + **MERGE**) | 53 files use `pumpAndSettle`; many design token tests are near-duplicate (e.g. `design/*` — 17 files). Merge design token tests into one table-driven `design_primitives` suite. `pumpAndSettle` elsewhere should be REWRITE to explicit `pump`/`pumpAndSettle` with a timeout where a real clock tick is needed (`design/srs_toast`, `rate_limit`). |
| `network/*` (7 files) | 7 | **KEEP** | Socket/HTTP are KEEP (INV-064 lives here). Uses `FakeHttp`/`MockClient` — the preferred HTTP-layer mock per `CLAUDE.md`. |
| `utils/*` (9 files) | 9 | **KEEP** + **MERGE** | `rate_limit`, `lru_list`, `cache`, `duration` are pure utilities — candidate for property-based tests (e.g. `lru_list` invariants). |
| `platform`, `db/openings`, `app_links`, `one_look` | 8 | **KEEP** | Narrow, keep. |

### F. Design / tokens — 17 files

| Files | Class | Notes |
|---|---|---|
| `design/*` | **MERGE** | `folio_tokens`, `srs_accent`, `srs_dialog`, `srs_switch`, `theme_bridge`, etc. share the same harness. Merge into 2–3 table-driven files (tokens vs. components) to cut widget overhead. No behavioral blind spot — correctness risk is low (visual). |

### G. `perf/`, `gates/`, `reachability/`, `scripts/`, `vertical_slice_gate`

| Files | Class | Notes |
|---|---|---|
| `perf/*` (3) | **KEEP** | Benchmarks intentionally use wall-clock; keep and exclude from the `DateTime.now` ban via allowlist. |
| `gates/domain_boundary_test` | **KEEP** | Enforces INV-040/041/042. Cheap, deterministic. |
| `reachability/*` (2) | **KEEP** | Graph walk from `main.dart`; keep. |
| `scripts/update_openings_db_test` | **KEEP** | Executes the real Python script — justified. |
| `vertical_slice_gate_test` | **KEEP** | End-to-end slice; keep. |

## Deletions: none with evidence this phase

The task allows deletion only if (a) redundant (no unique mutation/coverage contribution), (b) dead/cut code, or (c) asserts nothing meaningful — with the evidence recorded. Statically:

- **No test file has zero `expect`/`check`/`expectLater`** (0/182).
- **Three files have fewer expects than tests** (`forecast_test` 10/12, `duration_test` 6/14, `screenshot_capture_test` 3/10) — manual inspection showed `forecast_test` uses helper matchers in setup and `duration_test` asserts via `check()`-style helpers not matched by the `expect(` grep; not deletion candidates without deeper parsing.
- **Two files flag as over-mocked** (`game_history_test` 6 mocks/3 expects, `study_opening_test` 7/3) — inspection showed the `expect` grep undercounts because those files assert via Riverpod container reads, not direct `expect` on the mock. Not reliable evidence.

No deletion experiment was run (needs per-test mutant kill matrix). So **zero DELETEs are proposed**. The candidates above become candidates for Phase 4 only after the expanded mutant corpus + per-test coverage isolate is built.

## Static smells (measured, not judged)

| Smell | Files | Gate today | Severity |
|---|---|---|---|
| `pumpAndSettle` (unbounded settle) | 53 | none | **Medium** — loads to fix in Phase 3; not a correctness hole today but a speed/brittleness tax. |
| `Future.delayed`/`sleep`/`pump(Duration)` | 46 | none | **Low** — 10 are `FakeAsync` (correct fake-clock usage); the rest are widget pumps with durations (design). Perf tests intentionally use `DateTime.now`. |
| `mocktail`/`Mock` | 47 | none | **Low** — HTTP mocking is the *recommended* pattern (`CLAUDE.md`); domain/rate-limit mocks are the only candidates to replace with fakes. |
| `DateTime.now()` in unit tests | 6 | G03 only bans it in `domain/*` | **Low** — 4 of 6 are in `perf`/`log` (expected). No scheduler/coordinator leak found. |
| `dart:io`/`File`/`Directory` | 40 | none | **Low** — half is `sqflite_common_ffi`/`file_picker` in persistence/import (justified); the rest is `rootBundle` asset loading in widget tests. |
| Bare `expect(true, isTrue)` style | 0 | G08 tripwire | — |
| Missing SPEC citations | 137 files (75%) | G05 only enforces domain/known invariants | **By design** — `model`/`view`/`utils` have no SPEC invariant today; not a smell, but a signal that a future agent could add a shallow checkbox test without tripping G05. |

## Cost

Tier today: **one tier** (`flutter test` over 182 files, ~291 s, no tags, no sharding, no `dart test` lane). The task's goal is (a) fewer, better tests AND/OR (b) many more cheap units with CI time *down*. Today the 66 widget files pay ~37% of lines and likely >60% of wall time (widget pumps) while the 30 SRS-critical files hold <20%. The lever is not deleting the 70% inherited bulk — it's making the 30 cheap and the 53 `pumpAndSettle` files cheaper, plus enforcing budgets so a future agent cannot add another 2.5k-line widget file unnoticed.

## Top 10 blind spots (ranked by risk to user data or schedule correctness)

These are "important behavior with surviving mutants or no meaningful test" — since no mutant survives yet, the ranking reflects **zero mutant coverage** (no oracle) on critical paths, plus spec gaps the gate admits.

1. **Persistence crash-consistency** (T0 — data loss). No kill-at-write-boundary test: power loss mid-`saveImportResult` / mid-`submitMove` write. Invariants INV-001/002 assert durability and incremental scope, but not torn-write recovery (SQLite WAL, `Batch` atomicity). *Oracle needed:* fault-injected DB that throws at each batch boundary; assert no orphan `srs_decision`/`position_knowledge_state` row and session recovers. Currently no test injects a fault into `sqlite_study_repository.dart`.

2. **ChessFSRS parameter drift** (T1 — silent schedule corruption). `lib/src/domain/chess_fsrs_scheduler.dart` (343 lines) has **zero** mutants. FSRS stability/interval/due calculation, parameter `Retention`/`MaximumInterval` hand-off, and `schedule ==` equality (cf. INV-026 history) are only covered by example vectors. No differential test vs. the reference Python FSRS or published vectors; no property that `schedule(schedule(s, correct, t), correct, t+interval)` is monotonic.

3. **Graph-aware coordinator contagion boundaries** (T1 — over-softening). `graph_aware_review_coordinator.dart` (290 lines) has zero mutants. INV-027/028/029 specify bounded contagion, micro-credit throttling, and confusable-sibling coupling. Mutants like "remove the `if (stability > threshold)` guard", "drop the `oncePerDay` check", or "negate the `confusableSiblingsOnly` predicate" have no mutant — a missing guard would survive today if the example tests don't hit the threshold.

4. **PGN import: deep variation + NAG/comment round-trip** (T0 — repertoire loss). Import variation preservation (INV-010) is tested with example PGNs, but no property that `parse(export(parse(pgn))) == parse(pgn)` on random trees, and no fuzz of malformed RAV depth/NAG combos. Mutants "flatten third-level variation" or "drop comments on re-import" are not in the corpus.

5. **Canonical position identity re-key** (T0 — silent reset). `canonical_rekey_migration.dart` is tested with fixtures, but no mutant "recompute canonical key with only first accepted move (old format)" — the exact regression that motivated INV-015/017. A second migration (`opening_name_repair_migration`) similarly has no "erase a genuine opening" mutant.

6. **Review session transposition grader** (T1 — wrong verdict). `lib/src/domain/review/review_session.dart` (1,456 lines) — the critical `submitMove` path that grades out-of-line transpositions (INV-065) and applies `Transposed moves: within study` scoping. No mutant for "accept transposition even when setting is Off" or "reject legal out-of-line even when in scope". Only `review_transposition_test` (2 INV citations) guards this.

7. **Due vs fresh partition on first bulk import** (T1 — thousands inflated due). INV-068 (fresh vs due) is well-cited (37 citations) but the first-import session builder that caps fresh introduction (`maxNewPerSession`, `maxDuePerSession`) has no mutation for "fresh cap ignored → queue includes all 2k fresh on day 1" or "due queue includes never-reviewed nodes". The perf handoff `docs/performance-handoff.md` notes this was the owner's launch-day failure.

8. **Scope filter: opening aggregation + side scopes** (T1 — due counts wrong). INV-030 (`all`/`white`/`black`/`opening`/`chapter`) has the most citations (26) yet `ReviewScope.opening(name)` normalization (INV-030 + INV-067 family-name filter) and `white()`/`black()` chapter-orientation aggregation have no "normalize case-insensitively? No — exact" mutant or "drop inactive study filter" mutant.

9. **Socket sri handshake (already an escape)** (T1 — silent offline). INV-064 was the basis for an actual escape (#129) where every handshake was refused 400 while the suite stayed green because the fake keyed on path alone. The fix test keys on the requested URL — but no mutant "strip `?sri=` query param" with a fake that now **does** assert the query string is in the corpus. Regression is one refactor away.

10. **Wall-clock / real-delay ban outside domain** (T2 — flaky CI tax). G03 bans `DateTime.now` in `domain/*` only; 46 files still use `Future.delayed`/`sleep`/`pump(Duration)` and 53 use `pumpAndSettle`. No gate fails on `sleep` or real delays in unit tests, and no per-test runtime budget — a future agent can add a 30 s `pumpAndSettle` timeout and the suite gets 30 s slower with no signal. The blind spot is not a user-data bug but the lever the task explicitly calls out: "CI time going down, not up" has no ratchet.

## Limits of this audit (honest)

- Per-test/per-file wall-clock, 3× flake sweep, and line/branch coverage split were **not measured locally** (budget rule; see `baseline.md §7`). Flakiness is known only from `AGENTS.md` lessons and recent CI history (no persistent red).
- Mutant kill set is **narrow** (6/6 on one file). No per-test unique kill matrix was built, so no deletion was demonstrated redundant per the task's rule; hence none is proposed.
- Coverage-by-directory (SRS vs Lichess) and deletion experiment require a CI `lcov` artifact + per-test isolate run — deferred to Phase 3/4.
- Static greps are regexes and undercount (e.g. `check()`-style expectations, Riverpod container reads). Manual spot-checks were done for the flagged files above; full file-by-file reading was not.
