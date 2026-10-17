# Weak rows — catch-up walkers (verbatim digests; grade 3 rows counted per file in coverage.md)

## catch-up A (account, auth, clock, engine leftovers, explorer/game/study leftovers, network last-two, schema indexes) — 30 files, 199 tests, 0:0 / 1:4 / 2:31 / 3:164

Grade 1 verbatim:

- model/common/time_increment_test.dart:6 — "Initialization" — two getters echo the constructor args back; sees only gross constructor breakage.
- import/pgn_offload_test.dart:26 — "hash and import async helpers agree for the same input length" — under the env guard both helpers take the sync path by construction, so the 8 KB vs 64 KB divergence this regression existed for is structurally unreachable; the equality is near-tautological.
- model/engine/engine_availability_test.dart:50 — "is true in the test environment..." — documents the FLUTTER_TEST branch of platform detection; the real Android/iOS/web logic is unreachable, observes nothing beyond a wholesale inversion in-test.
- model/clock/chess_clock_test.dart:7 — "make clock" — echoes the constructor's own inputs through two getters.

Grade 2, one line each (file:line — title — the mutation it would miss):

- model/account/account_preferences_test.dart:70 — uses local defaults when nothing stored — exercises the empty-storage path but the final assert is default==default; catches wrong-key/crash, little else.
- model/account/account_repository_test.dart:11 — getPreferences — isA + one field of a ~40-field payload; endpoint breakage fails, a scramble of every other mapping passes.
- model/analysis/server_analysis_service_test.dart:99 — a study request that times out does not send on a disposed socket — waits a fixed real 4 s (file:120) against the lib's 3 s connect timeout, then asserts currentAnalysis is null; a socket-timeout change past 4 s silently redefines the window, and the "no unhandled async error" half is only implicit.
- server_analysis_service:194 — merges evaluation into existing node — only the merged comments list asserted; a mutation dropping the cp:42 eval passes.
- model/auth/auth_controller_test.dart:183 — signOut does not clear state if new sign-in completed during delay — right behavior but rendezvous with the lib's 500 ms delay via fixed real 50 ms sleep (file:203); lib constant below 50 ms breaks it.
- model/clock/chess_clock_test.dart:17 — start clock — asserts only isRunning after start().
- model/common/time_increment_test.dart:37 — Equality and HashCode — standard triple; generic value-class mutation coverage.
- model/engine/engine_factory_test.dart:41 — a create waits for the engine it replaces to finish exiting — right invariant (serialized start/quit) but the overlap window is built from a fixed real 50 ms quitDelay (fake_engine.dart:267).
- engine_factory:154 — a second create on one slot never runs beside the first — right refusal behavior but the window depends on a fixed real 50 ms startDelay (fake_engine.dart:137).
- model/engine/evaluation_mixin_test.dart:108 — a new eval request cancels the replaced subscription — listener-count is real, but the 250 ms debounce is advanced with a fixed real ~300 ms sleep (helper at file:91; used at 117 and 123).
- evaluation_mixin:134 — disposing the notifier cancels the eval stream subscription — same real-time debounce wait before the disposal asserts.
- model/game/game_storage_test.dart:29 — paginate games — exact page contents asserted, but the 100 saves are ordered with a fixed real 1 ms delay (file:36); lastModified ordering rides clock granularity under contention.
- model/game/game_test.dart:163 — is empty for a game without clocks — absence-only asserts (they do forbid fabricating clocks).
- game_test:230 — clocks null for a game without time control — null/empty absence asserts only.
- model/offline_computer/tablebase_eval_test.dart:153 — $category: cp=0, no mate (draw/cursedWin/blessedLoss rows) — single constant pair per category; catches cross-category sign/label mixups, little else.
- tablebase_eval:167 — $category returns null (unknown/maybeWin/maybeLoss) — null-only asserts.
- model/study/study_collaboration_test.dart:146 — an edit for a different chapter is ignored — absence-only (sanMoves unchanged), though it forbids cross-chapter grafting.
- study_collaboration:268 — the chapter you asked for last is the one you get — right race asserted but ordering forced with a fixed real 150 ms hold (file:276).
- model/study/study_preferences_test.dart:26 — current preferences round-trip unchanged — defaults round-trip only.
- study_preferences:31 — review order defaults to by-line — single-value pin.
- network/aggregator_test.dart:41 — one request within 5ms makes an atomic request — a degenerate always-batch-of-one aggregator would also pass; weakest of the aggregator group.
- network/default_client_deadline_test.dart:36 — passes a request through when the server answers — single pass-through assert.
- default_client_deadline:48 — defaults to the same deadline LichessClient uses — equality pin between two constants (drift either way fails, nothing else).

TOP5 (walker): time_increment:6, pgn_offload:26, engine_availability:50, chess_clock:7, account_repository:11.

TIMING (walker): server_analysis:120 (real 4 s), auth_controller:203 (50 ms vs 500 ms), study_collaboration:276 (150 ms), evaluation_mixin:91 (elapseEvalDebounce ~300 ms real; used at 117, 123), game_storage:36 (1 ms per save), fake_engine.dart:137-138/:267-268 (50 ms start/quit, used at engine_factory :42/:155); benign: default_client_deadline:26 (the 50 ms timeout IS the subject).

Note: startup_token_check is NOT confined by the makeTestProviderScope lesson — it overrides authStorageProvider/authRepositoryProvider and awaits the real startupTokenCheckProvider.future directly (auth_controller.dart:165); all five tests observe the check running.

## catch-up B (utils leftovers, view screens, screenshot) — 27 files, 146 tests, 0:11 / 1:0 / 2:16 / 3:119

Grade 0 verbatim (all screenshot capture):

- test/view/screenshot_capture_test.dart:262/274/301/330/363/378/419/437(quiet)/437(private-404)/475/489 — all 11 testWidgets declarations carry `skip: !_enabled` (SRS_CAPTURE_SCREENSHOTS), so in CI they never execute — grade 0 across the board. When enabled, asserts are blank-frame guards (capture key present, a Scaffold exists) plus the golden write — which per the header claim was intended to write-and-pass, but with no flutter_test_config.dart the default comparator actually compares against the 120 committed PNGs; the header's "nothing here compares anything" is contradicted on disk. Verdict on the machine flag "benign": holds in intent (a review tool), but by the rubric every test here is 0 in the runs that matter.

Grade 2, one line each (file:line — title — the mutation it would miss):

- utils/lru_list_test.dart:36 — starts empty — single trivial assert, no plausible mutation targeted (walker noted the label is honest; counted thin).
- view/engine/engine_gauge_test.dart:13 — shows 0.0 when eval is 0 — only the literal text '0.0'; gauge fill, side/orientation, eval resolution never asserted.
- engine_gauge:44 — 0.0 (no sign) for small positive eval — adds '...+0.0' findsNothing (a sign-format bug is caught), still text-only.
- engine_gauge:77 — shows 0.0 when game is a draw — same thinness.
- view/engine/engine_line_semantics_test.dart:43 — empty engine line renders nothing to announce — widget exists + no semantics; behavioral but shallow.
- view/review/about_page_test.dart:42 — uses the Diagram head — SrsPageHead present / AppBar absent; would fail on removal but says little else.
- view/review/export_pgn_dialog_test.dart:33 — renders title, subtitle, selectable PGN — rendering solid, but "Copy" asserts only dismissal; a copy that no-ops yet dismisses passes.
- export_pgn_dialog:84 — tapping Share triggers graceful share and dismisses — "triggers share" unobservable; crash-freeness + dismissal only.
- view/review/library_sheet_test.dart:36 — the sheet does not offer Analysis or the tools it contains — four absence-only assertions; an emptied sheet passes.
- library_sheet:58 — the destinations the sheet gave up are still reachable — reads lib/ as text and asserts substrings; passes while the route is dead, strikes on harmless refactors (title overshoots).
- view/review/scope_split_drawers_test.dart:128 — neither drawer spells out the colour or offers an everywhere row — absence-only ×4; no positive assertion.
- scope_split_drawers:241 — searching only matches within the drawer's own colour — deprecated fixed-delay pumpAsync (real 120 ms, test_helpers.dart:267-274); under load the filter may not be applied and the absence asserts pass vacuously.
- view/settings/board_and_sound_screens_test.dart:84 — piece set shows only the curated sets — count-only (5 rows), no labels; swapping one curated set for an uncurated one passes.
- board_and_sound_screens:113 — the volume slider is notched, so its label is reachable — single divisions isNotNull assert; the label-reachable promise only indirect.
- view/settings/board_thumbnail_test.dart:39 — no theme previews a stock photo — absence-only (Image findsNothing per theme); catches jpg reintroduction only.
- view/settings/log_screens_no_horizontal_scroll_test.dart:19 — the app log category filter fits the width — width assertions are real, but the horizontal-Scrollable guard at :52 is a tautology (anyOf(isNot(right), isNot(left)) is true for EVERY axis direction) — the named regression can never fail; survives on origin checks alone.

TOP5 (walker): screenshot_capture all 11 (skip-gated; blank-guards + goldens), log_screens:52 (tautology guard), library_sheet:58 (static substrings as "reachability"), library_sheet:36 (absence-only ×4), engine_gauge:13 (literal text only). Runners-up in the 2s.

TIMING (walker): screenshot_settle: a real 300 ms sleep inside tester.runAsync (capture test — skip-gated); scope_split_drawers pumpAsync ×7 (:97, 146, 163, 189, 213, 245, 255) each a real 120 ms sleep + fixed pumps; no other fixed real sleeps (cache/email_login/perf_stats timers are fake-clock; update_openings_db is a blocking subprocess).

Login-chain note: email_login_screen_test (25/25 grade 3) pins validation regex boundaries, exact request shapes with no query leak, fail-open existence checks and the full token round trip — it would have caught the regexp/parameter-shape/handler-flow defects of the documented five-defect chain; it could not have caught a wrong default LICHESS_HOST (expectations build from the same kLichessHost constant) or anything on the startup /api/token/test path under the makeTestProviderScope harness (see startup_token_check note in catch-up A).
