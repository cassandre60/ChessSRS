# Rest of the suite — wave 2, catch-up, and the author's walk (completes the per-test pass)

Wave 1 (the four committed chapters) walked the SRS core (~235 tests). The user
then asked whether *all* 1855 had been walked — they had not; only the core was.
Wave 2 + the catch-up walkers closed the gap: **every file on disk is now
attributed in `coverage.md` — 182 files / 1855 declarations, zero unattributed.**

## Walker sessions (rubric identical to wave 1; grades 0–3 on "would this fail if the code were wrong")

| Walker | Files | Tests walked | Histogram 0/1/2/3 |
|---|---:|---:|---|
| w2-review (review + view/review) | 11 | 163 | 2 / 2 / 34 / 125 |
| w2-engine (model/engine + offline_computer) | 10 | 186 | 1 / 2 / 32 / 151 |
| w2-network/analysis/utils | 14 | 283 | 0 / 0 / 38 / 245 |
| w2-widgets/view | 20 | 277 | 0 / 14 / 87 / 176 |
| w2-domain/persistence/import/gates | 35 | 373 | 1 / 34 / 174 / 164 |
| w2-design/perf/platform | 24 | 97 | 0 / 6 / 26 / 65 |
| catch-up A (account, auth, clock, engine leftovers, game, study) | 30 | 199 | 0 / 4 / 31 / 164 |
| catch-up B (utils, view screens, screenshot) | 27 | 146 | 11 / 0 / 16 / 119 |
| author's own walk (review_order, app_store_links, verified_link_claims) | 3 | 12 | 0 / 0 / 4 / 8 |
| wave-1-only files (8 files: scheduler, coordinator, controller, sqlite, db_config, lichess_study_importer, pgn_exporter, srs_settings_screen) | 8 | — | per-test tables already in the wave-1 chapters |

Nine walker sessions: 1736 rows counted walker-side + the wave-1 tables ≈ 1970
rows against 1855 declared tests — the surplus is loop-expanded invocations
(maia tiers ×3, tablebase groups ×3, screenshot captures ×10) and files that a
wave-1 chapter *and* a wave-2 walker both covered; per-file test counts in
`coverage.md` are the extractor's, not the walkers'.

## What the full pass changes in the picture

1. **The suite is stronger away from the SRS core than its reputation**: node
   protocol choreography (`model/engine/engine_test.dart` — 33/33 grade 3,
   comments bemoaning missing engine tests should be retired), chess_clock
   (12/13 grade 3, exact tick/flag/cooldown math), email login (25/25 grade 3 —
   the 11 negative-regex rows each pin zero-traffic + exact error copy, so this
   file *would* have caught the validation-shape defects of the documented
   login chain; a wrong `kLichessHost` stays invisible by construction),
   `account_preferences_test` (11/12 grade 3), `startup_token_check_test`
   (5/5 grade 3 — it defeats the `makeTestProviderScope` `preloadedDataProvider`
   stubbing limitation via provider overrides, so app-level startup-token
   coverage does exist where it counts).
2. **Grade 0 population is small and known**: 16 across the suite —
   `srs_toast_test:138` (wave 1), `review_service_test:43` (F2, 2026-10-16
   audit), `review_side_scope_test:103`, `stockfish_nnue_service_test:355`,
   `sound_service_test:50`, all 11 `screenshot_capture_test` declarations.
   The full grade-0/1 list with reasons is in `weak-rows-*.md`.
3. **New whole-test defects found by the full walk** (each verified against the
   source before being recorded here):
   - `test/view/settings/log_screens_no_horizontal_scroll_test.dart:52` — the
     horizontal-Scrollable guard `anyOf(isNot(right), isNot(left))` is a
     tautology: for `right` the second branch is true, for `left` the first is
     true, vertical both true. The regression named in the title can never be
     caught; the test survives on its origin-geometry checks alone. Fix: assert
     the axis is vertical (`anyOf(isNot(right), isNot(left))` is true for every
     direction — the correct assertion is `axisDirection, vertical`).
   - `test/view/screenshot_capture_test.dart:253` vs its own header — the file
     claims "it writes files and passes... nothing here compares anything", but
     there is no `test/flutter_test_config.dart`, so with
     `SRS_CAPTURE_SCREENSHOTS=1` the `matchesGoldenFile` calls pixel-compare
     against the 120 committed PNGs (unless `--update-goldens` is passed). A
     deliberate decision is owed: either commit the comparator-is-writer config
     the header promises, or say in the header that enabled runs compare.
   - `test/import/pgn_offload_test.dart:26` — the "hash and import async
     helpers agree" test cannot exercise its own reason: the FLUTTER_TEST env
     guard the sibling test pins (`:15`) forces both helpers onto the sync path
     in the test environment, so the 8 KB/64 KB divergence the regression
     existed for is structurally unreachable here. Only the constant pin at
     `:11` has teeth.
   - `test/view/review/library_sheet_test.dart:36/:58` — four absence-only
     assertions could survive an emptying of the sheet, and ":58 reachable"
     asserts source substrings, not reachability (passes while a route is dead,
     strikes on harmless refactors).
   - `test/view/review/review_screen_test.dart:2053` — narrow-layout
     overflow test: the harness swallows exceptions and `takeException` is
     near-vacuous; a RenderFlex overflow rejects nothing.
   - `auth_repository_test.dart:240/:388` — `throwsA(isA<Exception>())` is
     toothless on the auth error paths (any throw passes).
   - misc thin payload contracts: `user_repository` get/getPerfStats/statuses
     (length-only), `game_repository` clocks/threeCheck (a 38-entry clock
     fixture, one-two fields asserted), `app_test.dart:26` brightness-only.
4. **Timing inventory (widens issue #197 beyond its original 8 files)**, from
   the hooks the walkers collected: `server_analysis_service_test:120` (a fixed
   real 4 s wait), `practice_analyser_test` settleEvals helper (~400 ms ×26 sites),
   `position_evaluator_test` (a 2.1 s fixed sleep at :305 + unbounded 5–10 ms
   real polls), `engine_providers_test` (≈2.05 s ×4), `opening_book_test:284`
   (3 s mock + stopwatch), `evaluation_mixin_test:91` debounce helper (~300 ms
   real), `review_screen_test` (~30 sites of the deprecated fixed-pump
   `pumpAsync` inside `test_helpers.dart:267`), `scope_split_drawers_test`
   (pumpAsync ×7; `:241` search windows make the negative asserts vacuous under
   load), `auth_controller_test:203` (50 ms racing a 500 ms lib delay),
   `study_collaboration_test:276` (150 ms ordering hold), `game_storage_test:36`
   (1 ms clock-granularity ordering), `engine_factory_test` windows built on
   `fake_engine.dart:137/:267` (50 ms), engine_opponent stopwatch bounds
   (≥180/340 ms), `repertoire_import_dialog_test:113/:126` (20/200 ms),
   `stockfish_nnue_service_test:234` (100 ms), plus the previously known
   rate_limit/socket/connectivity populations. The in-repo replacement
   primitives exist (`fakeAsync` in cache/clock/engine_test,
   `pumpUntilFound`/`pumpUntil` in test_helpers) — the retrofit needs no new
   infrastructure.
5. **Perf files are measurement harnesses, not regression guards** (all three
   `perf/*` tests assert `<2000ms` against ~16–39 ms implementations they print
   themselves, and skip without `CHESS_SRS_PERF_DB`). Legitimate as tools; not
   gates; user-report that the benchmark itself misdetects stands.
6. **Architecture gates are live but hand-listed** (`gates/domain_boundary_test`
   would catch real violations, with a hand-maintained clock-file list +
   substring-only I/O scan as its two escapes; `reachability` genuinely strong
   with ratchet/anti-rot/anti-vacuity tripwires; `enforcement_matrix` coarse at
   a 10/13 row floor).

## Where the weak rows live

`weak-rows-review.md` (review + the author's three files), `weak-rows-net.md`
(network/analysis/utils), `weak-rows-widgets.md` (widgets/view),
`weak-rows-domain-1.md` + `weak-rows-domain-2.md` (domain/persistence/import/
model/gates), `weak-rows-design.md` (design/perf/platform), and
`weak-rows-catchup.md` (catch-up A + B). Grade-3 tests are *not* individually
recorded: they are counted per file in `coverage.md`, and their strength notes
survive in the walker transcripts and the wave-1 chapters.
