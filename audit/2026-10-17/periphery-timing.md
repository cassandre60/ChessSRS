# Periphery & timing audit (digest)

Source: full read of test/sound (absent), test/view/engine, test/view/analysis,
test/widgets, test/utils, test/network, test/model/engine, test/perf.
Full per-test text was skipped (breadth pass); the verbatim walk quoted below is
external-model shell and the machine screens in `verify.md` agree with it.

## HIGHLIGHTS (top 5 quoted)

1. `test/model/common/service/sound_service_test.dart:63` — no `test/sound/` exists;
   only two `completes`-only tests remain, and the "disabled" one cannot observe
   silence — the Future.value-sound-service pattern that docs/ESCAPE_TO_GATE.md
   flags as unverifiable. Quote: `await expectLater(soundService.play(Sound.move), completes);`
2. `test/model/engine/position_evaluator_test.dart:1035` — "Engine evaluation with fake
   stockfish" asserts the fake's own hardcoded answer back
   (`fake_engine.dart:186` `session.emit('bestmove e2e4 ponder e7e5')`): it proves
   plumbing routed the fake's string, nothing about evaluation.
3. `test/perf/due_summary_attribution_test.dart:150` — sole assertion is a ceiling ~10x
   the printed number on a harness that skips unless `CHESS_SRS_PERF_DB` is set; the
   prints are the deliverable, the pass/fail carries no signal.
4. `test/model/engine/position_evaluator_test.dart:178` — unbounded real-time polling
   loops with no timeout, under CPU contention they hang, not fail.
5. `test/utils/rate_limit_test.dart:43` — the whole Debouncer/Throttler file waits
   real wall-clock sleeps instead of `fakeAsync`/`async.elapse`; ~2s of pure sleep
   per run, load-sensitive at exactly the 50ms/100ms boundaries it asserts.

## GAPS (near-zero tests found)

- `engine_gauge_test` has no test for a nonzero eval readout, black flip, or gauge geometry.
- `clock_test` never tests "<1s shows milliseconds" while `active: true`.
- `EngineButton` has no test of its tap path (enable/disable), only long-press popup and absence.
- `rate_limit_test` never exercises concurrent callers interleaved across the trailing window.
- No l10n coverage for any analysis/engine screen string (hardcoded-English convention,
  but with zero guard that keys exist when the pipeline lands).

## DENSITY (mergeable/parametrizable whole groups)

- `analysis_screen_test:1095-1277` — three groups (11 testWidgets) are the same scaffold
  differing only in a pref flag and one widget type; collapses to 2 loops.
- `clock_test:88-256` — five CountdownClockBuilder tests repeat the same
  `pump(100ms)/pump(100ms)/0:09.9→0:09.8→0:09.7` triple; one ticking helper + 3 focused cases covers it.
- `rate_limit_test:60-160` — six copies of "call n times, sleep 150, expect count"; a
  table of (calls, delays, expected) halves the file and fixes the wall-clock issue.
- `engine_gauge_test:13-106` — three near-identical ~30-line blocks; parametrize over
  (position, cp, expected text).
- `feedback_test:11-76` — 8 tests where two size-cases and two assertion-cases collapse to loops.
- `analysis_screen_test:1279-1357` — 'show threat button' = 6x the same tap-Menu-scaffold;
  parametrize over (PGN x expected visibility).
- `json_test:171-285` — Duration readers assert the same matrix four times over parallel
  `OrNull` variants; one table covers the pair.
