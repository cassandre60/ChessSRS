# 2026-10-17 — Test suite audit

Per-test audit of the suite at `a71a19096`. Read-only audit: no `flutter test`
run for the audit itself (targeted machine heat), all strength claims from
reading plus the machine screens committed alongside.

## Files

| File | Content |
|---|---|
| `scheduler-review.md` | scheduler (26), coordinator (14), controller (64) — per-test grades + weak set |
| `persistence-import.md` | sqlite repository (24), db config/upgrades (3), import/export (~73) |
| `design-settings.md` | design suite + settings screens (~49 walked, graded table) |
| `periphery-timing.md` | sound/engine/socket/perf breadth pass + density list |
| `verify.md` | what the audit itself ran: screens, gates, metrics — with the numbers |
| `findings.md` | top 13 findings + dedup against 2026-10-16 audit and work ledger |

Machine scripts (committed): `scripts/audit_2026-10/extract_tests.py`,
`smell_tests.py`. Provenance gap recorded as an issue: the autonomous
catalog/ledger (`docs/AUTONOMOUS_IMPROVEMENT_CATALOG.md`,
`docs/AUTONOMOUS_WORK_LEDGER.md`, `scripts/autonomous/`) are untracked local
files at audit time — the ledger's Stream 2 row records this audit
IN_PROGRESS with the same numbers as this report's screens.

## Method

1. Enumerate every test declaration (script, 1855 in 182 files).
2. Machine-screen every declaration for the audit classes: vacuous,
   try-catch-empty, tautology, fixed sleep/wall-clock, broad-mock stubs, and
   duplicate/identical names. 298 raw flags; manual adjudication dropped the
   false-positive classes (most "bad-name" hits are legitimately-named error
   tests; real signal classes: vacuous, wall-clock, try-catch).
3. Per-test read of the flagged tests plus representative samples per area,
   concentrated on the SRS core (scheduler, coordinator, controller,
   persistence, import). Areas only breadth-walked are stated in each chapter.
4. Cross-check external evidence: `docs/AUTONOMOUS_WORK_LEDGER.md` rows,
   `docs/spec-conformance-audit-2026-10-16.md` F1-F6 (not re-opened), and
   `.gates/mutants.json` validity.

## Headlines

1. Three tests fail their own titles by asserting nothing of the mechanism
   (controller prewarm 2194, settings smoke 40, page-head 37, toast tone 138).
2. Scheduler lapse branch stability: set in lib, never asserted in tests —
   the one finding with a committed fix PR (mutant-proven).
3. Timing: ~35 fixed wall-clock sleeps across 8 files; biggest flake machine
   (`rate_limit_test` 18, `socket_test` 8, `connectivity` 6, `engine_providers` 5,
   `nnue_service` 1, controller 2).
4. Sound surface: `test/sound/` absent; everything CI-visible asserts completion
   on a fake; the recording-fake pattern exists in exactly one file.
5. Duplicate test names within files (8 files) and a mergeable-density list of
   7 extractable parametrize tables (three groups of 11 in analysis_screen alone).
6. Pipeline hygiene: spec trace 44/44 clean; ratchet floor stale (1509 vs 1858);
   one inconsistent `.gates/mutants.json` entry; Stream-1 mutation evidence
   uncommitted.
