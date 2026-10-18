# Baseline scoreboard — ChessSRS test audit (2026-10-18)

> **Status: Read-only evidence. Do not dispatch agents from this directory.**  
> For work queue, streams, and dispatch order, use `docs/AUTONOMOUS_IMPROVEMENT_CATALOG.md` (catalog) and `docs/AUTONOMOUS_WORK_LEDGER.md` (ledger). The eight files that were briefly in `docs/tasks/TEST-0*` have been removed — they were a duplicate queue.

Branch: `test-audit` (off `main` at `a9fbfe0fb`). Measurements taken on the
developer's machine (Arch Linux, Dart 3.13.5, Flutter 3.47.3) and from GitHub
Actions history. Every number below states its source; numbers prefixed with
"~" are rounded or estimated and explain how.

## 1. Suite size

| Metric | Value | How |
|---|---|---|
| `_test.dart` files | **182** | `find test -name '*_test.dart' \| wc -l` |
| Helper/fake/fixture `.dart` files under `test/` | **26** | `find test -name '*.dart' \! -name '*_test.dart'` — see `test/binding.dart`, `test/test_*.dart`, `test/**/fake_*.dart`, `test/**/polyglot_fixture.dart` |
| Total `.dart` files under `test/` | **208** | sum of the two above |
| Lines in `_test.dart` files | **57,380** | `wc -l` over the 182 files |
| Lines in helpers/fakes | **3,331** | `wc -l` over the 26 files |
| Total lines under `test/` | **60,711** | sum; generated `*.freezed.dart`/`*.g.dart` are gitignored and excluded |
| Test declarations (`test(` + `testWidgets(`) | **1,883** | `rg -c "^\s*(test\|testWidgets)\("` summed; `.gates/ratchet-baseline.json` records `test_declarations: 1886` (measured 2026-10-01) — drift of 3 is within normal file churn |
| `expect(` calls | **5,426** | `rg --count "expect\("` |
| `group(` declarations | **~307** | `rg -c "^\s*group\("` summed (≈ 2190 − 1883) |

### Split by kind (heuristic: presence of `testWidgets`/`pumpWidget`/`WidgetTester`)

| Kind | Files | Lines in `_test.dart` | Declarations |
|---|---|---|---|
| **Widget** (uses `testWidgets`/`pumpWidget`) | **66** | **21,448** (37%) | ~700 (see per-file CSV) |
| **Flutter unit** (`flutter_test` but no widget pump) | **116** | **35,932** (63%) | ~1,180 |
| **Pure `dart test` (no `flutter_test`)** | **0** | 0 | 0 |

> Finding: 100% of tests run through `flutter_tester` (the `flutter test`
> runner). No test uses plain `dart test` alone. This is the primary lever for
> Phase 3: the domain, import, and persistence code is pure Dart and can be
> exercised without a widget binding.

### Split by directory

| Directory | `_test.dart` files | Notes |
|---|---|---|
| `test/domain` | 8 | SRS scheduler, entities, coordinator |
| `test/import` | 6 | PGN import/export, orientation, offload |
| `test/persistence` | 6 | sqflite repo, migrations |
| `test/review` | 10 | engine, service, controller, order, transposition |
| **Subtotal SRS (domain/import/persistence/review)** | **30** | **Product-critical** |
| `test/model` | 50 | Inherited Lichess models (engine, auth, game, study, etc.) |
| `test/view` | 42 | Widget tests for screens |
| `test/network` | 7 | HTTP/socket/connectivity |
| `test/widgets` | 10 | Reusable widgets |
| `test/db` | 3 | DB config, openings DB, upgrade |
| `test/utils` | 9 | caches, strings, durations, etc. |
| `test/platform` | 4 | App links, OAuth, verified links |
| **Subtotal inherited Lichess/infra** | **~128** | |
| `test/design` | 17 | Design tokens, sheets, colors |
| `test/perf` | 3 | Latency / attribution benchmarks |
| `test/gates` | 1 | Domain boundary |
| `test/reachability` | 2 | Reachability / enforcement matrix |
| `test/scripts` | 1 | `update_openings_db` script |
| **Subtotal design/perf/gates/reachability** | **24** | |
| `test/` root (`app_test`, `app_links`, `vertical_slice_gate`) | 3 | |

Library comparison (from `lib/src` line counts, hand-written Dart only):

| Module | `lib` lines | `test` files | Ratio |
|---|---|---|---|
| `domain` (pure SRS) | ~3,761 | 8 | thin |
| `review` (application) | ~3,089 | 10 | better |
| `import` | ~1,371 | 6 | dense |
| `persistence` | ~2,288 | 6 | — |
| `model` (Lichess) | ~22k | 50 | inherited |
| `view` | ~23k | 42 | inherited |

Weights: schedule/persistence/import is correctness-weighted per the task brief,
but holds only ~16% of test files and ~25% of test lines.

## 2. Wall-clock time

### CI (GitHub Actions — workflow `Tests`, runner `ubuntu-latest`)

Source: latest green run `39118936674` (PR #222, 2026-10-18). Times from the
job's `startedAt`/`completedAt` per step; cache hit for Flutter.

| Step | Wall time | Notes |
|---|---|---|
| `Install dependencies` (`flutter pub get`) | **~5 s** (10:22:07→10:22:12) | cached pub, no network cold start |
| `Code generation` (`dart run build_runner build`) | **~64 s** (10:22:12→10:23:16) | dominates fixed overhead |
| `Verify formatting` | **~3 s** | — |
| `Analyze` (`flutter analyze`) | **~35 s** (10:23:19→10:23:54) | |
| `Run unit tests` (`flutter test`) | **~291 s** (10:23:54→10:28:45) | **4 min 51 s** |
| **Total workflow** (checkout → done) | **~416 s** (10:21:49→10:28:45) | **~6 min 56 s** wall |

Two recent runs on `main` showed the same split (±10 s). "Tests" is the
required status check; docs-only PRs now trigger it intentionally (see
`.github/workflows/test.yml` header comment) at the same ~7 min cost.

Local full-suite run was **not executed** per `AGENTS.md §3.1` (the machine is
not a build server). One file probe was run locally to validate the JSON
reporter (`test/domain/entities_test.dart`: 23 tests, ~2 s wall incl. ~2 s
compile — see §3).

### Fixed overhead vs. test execution

| Bucket | CI time | Share |
|---|---|---|
| Fixed: checkout + Flutter setup + `pub get` + `build_runner` | **~75 s** | ~18% |
| Lint/format/analyze | **~38 s** | ~9% |
| **Actual `flutter test` execution** | **~291 s** | **~70%** |
| Gaps/queue | ~12 s | ~3% |

Within `flutter test`, fixed per-suite compilation (`loading <file>` hidden
test) accounts for roughly **~2 s per file** on first compile (measured on
`entities_test.dart`). For 182 files that is ~360 s of compilation that CI
amortizes via parallel isolates — the observed 291 s is the parallel
completion, not the serial sum. The remaining gap is why `--no-pub` locally is
cheaper but still not a substitute for sampling.

### 20 slowest individual tests / files

> **Not measured locally at this file granularity** — a per-test wall-clock
> list requires `flutter test --reporter=json` over the full 1,883 tests and
> parsing. Running that locally violates the budgeted loop (it pins all cores
> for ~5 min). CI logs do not emit per-test timing by default. This will be
> collected in Phase 2 via a single JSON run on CI (or one local run after
> explicit approval), then ranked and committed as an addendum.

Heuristic ranking by **file size × declaration density** (proxy for cost,
not a timing claim) — biggest files first:


| Rank | File | Lines | Decls | Likely cost driver |
|---|---|---|---|---|
| 1 | `test/review/review_engine_test.dart` | 2,557 | 47 | review loop, scheduler |
| 2 | `test/view/offline_computer/offline_computer_game_screen_test.dart` | 2,531 | 85 | widget pumps, engine |
| 3 | `test/persistence/sqlite_study_repository_test.dart` | 2,455 | 48 | sqflite FFI, 48 cases |
| 4 | `test/view/review/review_screen_test.dart` | 2,338 | 45 | board, pumps |
| 5 | `test/review/review_controller_test.dart` | 2,301 | 64 | controller + DB |
| 6 | `test/model/engine/position_evaluator_test.dart` | 2,016 | 64 | engine eval |
| 7 | `test/network/socket_test.dart` | 1,911 | 47 | socket fakes, timers |
| 8 | `test/view/analysis/analysis_screen_test.dart` | 1,708 | 58 | analysis widgets |
| 9 | `test/review/review_service_test.dart` | 1,403 | 21 | service + repo |
| 10 | `test/view/user/user_screen_test.dart` | 1,009 | 2 | widget, large helper |
| 11 | `test/import/pgn_importer_test.dart` | 973 | 76 | PGN parsing (76 cases) |
| 12 | `test/view/study/study_screen_test.dart` | 960 | 14 | study widgets |
| 13 | `test/review/review_continuity_test.dart` | 940 | 12 | session continuity |
| 14 | `test/view/board_editor/board_editor_screen_test.dart` | 902 | 33 | board editor |
| 15 | `test/model/common/node_test.dart` | 784 | 53 | tree/Node suite |
| 16 | `test/model/engine/engine_opponent_test.dart` | 727 | 32 | opponent logic |
| 17 | `test/view/study/study_list_screen_test.dart` | 713 | 2 | list + pumps |
| 18 | `test/model/engine/engine_test.dart` | 691 | 33 | engine integration |
| 19 | `test/domain/graph_aware_review_coordinator_test.dart` | 633 | 16 | coordinator |
| 20 | `test/network/http_test.dart` | 630 | 25 | HTTP client |

This ranking is **not** a measured timing ranking — see the note above. It
will be replaced with measured per-test/per-file timing in Phase 2.

## 3. Flakiness

> **Not fully measured yet** — the task asks for 3 full runs or CI history.
> Local 3× full run was not attempted (budget rule). CI history was probed
> via `gh run list -L 20`: recent `Tests` runs on `main` and PRs show
> **0 outright test failures** in the last 10 green runs (only `Gates`
> failures on referee edits, e.g. `fix/mutation-engine-instrument` failing
> G07). This is evidence of no persistent red, not a full flake sweep.

Known load-sensitive area (from `AGENTS.md` lesson 2026-09-28 and
`GATES.md` blind spots): `test/review/review_controller_test.dart` and
helpers using `pumpAsync` with a fixed 80 ms `Future.delayed` window — these
flake under CPU contention in wide runs and pass in isolation. No new flakes
were introduced in this baseline.

A 3× CI sampling will be filed as a Phase 2 addendum rather than running
three 7-minute suites locally today.

## 4. Coverage

| Signal | Value | How | Caveat |
|---|---|---|---|
| `flutter test --coverage` on 2 files | Produced an `lcov.info` (≈132 lines found) but mis-attributed (showing 0 hits for the domain file under test) | `fvm flutter test test/domain/entities_test.dart test/domain/scheduler_test.dart --coverage` locally; the hit map was 2/132, which is clearly wrong for a passing suite — likely a `build_runner`/`--coverage` interaction | **Needs a CI coverage artifact**, not a local ad-hoc run |
| Line/branch split by directory | Not instrumented locally | Requires `lcov` tool + `genhtml` or `dart` coverage service; not run to avoid local heat | Deferred to Phase 2 (single CI coverage job) |
| Mutation score (existing gate) | **6/6 = 100%** on `lib/src/domain/scheduler.dart` | `python3 scripts/gates/manual_mutation_runner.py --mutants .gates/mutants.json --test-cmd "fvm flutter test test/domain/scheduler_test.dart"` — all 6 hand-picked scheduler-boundary mutants killed | Narrow scope (one file, 6 mutants); not a whole-domain score |

The existing mutation corpus (`.gates/mutants.json`, 6 entries) covers only
`SimpleScheduler`/`EaseScalingScheduler` cap removal, off-by-one, lapse reset,
double-count, and `dueItems` negation. ChessFSRS, coordinator, import, and
persistence have no mutants — that is the blind spot to fill in Phase 2.

## 5. Cut-list overlap

| Check | Result |
|---|---|
| Test files whose **filename** contains an already-cut keyword (`puzzle`, `watch`, `tournament`, `broadcast`, `clock_tool`, `blog`, `recap`, `announce`, `lobby`, `challenge`, `correspondence`) | **0** — those suites were already removed with their features (see `CUT_PROPOSALS.md` completed cuts 1–22) |
| Tests exercising **inherited Lichess UI** (model/view/network/widgets/utils) that the fork is cutting incrementally | **~128 files** (70% of `_test.dart`) — see §1 split. These are not "cut now" but are the pool to shrink as `CUT_PROPOSALS.md` steps advance. The per-file `cut_list` column in `inventory.csv` is `n` for all today because no further file-level cut is staged; the useful signal is the directory bucket. |
| Tests under code paths **listed for removal** but not yet staged | None individually flagged; the bucket to watch is `test/view` + `test/model` (Lichess-derived) vs. `test/domain`/`import`/`persistence`/`review` (SRS-critical). |

## 6. Mock / time / I/O signals

Static greps over `test/**/*_test.dart` (no execution; file may match multiple
patterns):

| Pattern | Files matching | Interpretation |
|---|---|---|
| `mocktail` or `\bMock\w+` | **47** | mocktail/Mock usage |
| `pumpAndSettle` | **53** | widget settle helper (often slower) |
| `Future.delayed` / `sleep(` / `pump(...Duration` | **46** | real delays or duration-bearing pumps |
| `FakeAsync` / `fakeAsync` | **10** | proper fake-clock usage |
| `DateTime.now()` | **6** | wall-clock time (see `test/perf/*`, `test/model/log/*`, `test/view/offline_computer/offline_computer_game_screen_test.dart`) — 4 of 6 are in `perf`/`log` and expected |
| `dart:io` / `File(` / `Directory(` | **40** | real filesystem (some via `sqflite_common_ffi`/`file_picker` helpers) |
| `MockClient` / `FakeHttp` / `http.Response` | **36** | HTTP-layer mocking (the preferred pattern per `CLAUDE.md`) |
| `MockClient` etc. that hit real network (no `Fake`/`Mock`) | **0 found** by grep | No test appears to hit the live network; verify with an outbound-firewall probe in Phase 2 |

Composition: perf tests (`test/perf/*`) legitimately use wall-clock; persistence
tests use `sqflite_common_ffi` (in-memory file-backed SQLite) rather than a
hand fake — acceptable for T0 durability, but worth noting because it adds
setup cost per file.

## 7. What was NOT measured (honest)

| Gap | Why not now | How it will be measured |
|---|---|---|
| Per-test/per-file wall-clock ranking (the 20 slowest) | Requires a full `flutter test --reporter=json` run (~5 min, saturates the machine) — skipped per `AGENTS.md §3.1` local budget | Single CI run with `--reporter=json` artifact, parsed offline; or one approved local run with `fvm flutter test --reporter=json > /tmp/timing.json` |
| 3× flake sweep | Three full runs would triple the heat; CI history was sampled instead | CI: re-run the `Tests` workflow 3× via `gh workflow run` or read 3 consecutive `main` runs |
| Line + branch coverage by directory (SRS vs Lichess) | `flutter test --coverage` locally produced a mis-attributed lcov (2/132) and heats the machine; correct coverage needs a clean CI artifact | Add a CI coverage job (or `lcov --capture` from the `Tests` run) and split with `lcov --extract` per directory |
| Per-file mutant kill set / unique coverage contribution | Needs the expanded mutant corpus (Phase 2) — current corpus is 6 mutants on one file | After the expanded corpus is built, rerun `manual_mutation_runner.py` per test file |

## 8. Sources & reproducibility

- File/line counts: `find`/`wc -l`/`rg -c` commands logged above; rerun
  `cat docs/test-audit/inventory.csv` for the per-file table.
- CI timing: `gh run list --workflow Tests -L 5 --json ...` and
  `gh run view <id> --json jobs`; run ID `39118936674` (2026-10-18).
- Mutation: `python3 scripts/gates/manual_mutation_runner.py --mutants .gates/mutants.json --test-cmd "fvm flutter test test/domain/scheduler_test.dart --no-pub --force"`.
- Analysis baseline: `.gates/ratchet-baseline.json` (17 suppressions, 65 deps, 10 skips, 1886 decls).
- Spec citations: `rg -o "INV-\\d+"` over `SPEC.md` and `test/**/*_test.dart`.
