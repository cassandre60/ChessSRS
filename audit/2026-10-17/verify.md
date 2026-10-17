# Verification — what this audit itself ran, everything else, honestly

Everything below was executed by the audit in this session against the primary
checkout at commit `a71a19096` (worktree `../chesssrs-test-audit`). No flutter
test was run for the audit itself. Spot-check runs for the one fix-PR are
recorded in the PR body.

## Machine enumeration (scripts/audit_2026-10/extract_tests.py)

- 1855 test declarations in 182 files. Committed scripts regenerate the
  inventory in one run: `python3 scripts/audit_2026-10/extract_tests.py`
  (`inventory.json` written next to the script, not committed: regenerable).

## Machine screening (scripts/audit_2026-10/smell_tests.py)

- 298 declarations flagged over raw patterns (bad-name 253, vacuous 23,
  wall-clock 13, try-catch 5, fixed-second-sleep 1). bad-name majority is a
  false-positive class (legit "empty/error throws" names manually reviewed and
  excluded); real signal classes: vacuous + wall-clock + try-catch.
- Duplicate test names (full-string match): pairs at
  `user_repository_test` (2 names x3), `opening_explorer_repository_test` (:parse json x3),
  `stockfish_nnue_service_test` (2 names), `analysis_screen_test` (2 names x2),
  `scheduler_test` (:287/:298 "equality and hashCode work correctly"),
  `auth_repository_test` ("throws EmailLoginRateLimitException on 429" x2),
  `node_test` ("mainline" x2), `game_repository_test` ("json read, full example" x2).
  Same-titled tests in one file without differentiating names is the actionable subset.

## Gate-pipeline health checks (read straight from this checkout)

- `python3 scripts/gates/spec_trace_check.py --spec SPEC.md --tests test` →
  **"44 invariants in spec, 44 referenced by tests"** (clean).
- `python3 scripts/gates/collect_metrics.py` →
  deps=65 | suppressions=17 | skips=10 | test_declarations=1858 | domain_loc=3761.
- `.gates/ratchet-baseline.json` test_declarations = **1509** vs today's 1858 —
  the metrics pass (higher-is-better), but the stored floor is stale by 349 tests;
  ratchet never fails until the count drops 25% below today, which is the
  drift-detection value it was written for. Suggests re-baselining discipline
  gap, not a product bug.
- `.gates/mutants.json` entry #2 (`occurrence: 2`) matches the exact identical
  string only ONCE per file (both `notification` occurrences use the same
  textual match string; the occurrences diverge elsewhere) — the runner reports
  it as SURVIVED "no numeric change" though it changed the second scheduler.
  Every other mutant in the file is valid. Fix: use a uniqueness-anchored
  longer match or occurrence counts.

## Wall-sleep inventory (rg, straight)

Files with hardcoded `Future.delayed(Duration(...))` in test bodies (count only,
not re-verified cluster-by-cluster): `test/utils/rate_limit_test.dart` (18),
`test/network/socket_test.dart` (8), `test/network/connectivity_test.dart` (6),
`test/model/engine/engine_providers_test.dart` (5),
`test/model/engine/stockfish_nnue_service_test.dart` (1),
`test/review/review_controller_test.dart` (2 — 752, 1430), plus scattered
single instances elsewhere (`connectivity` is the top). None of these files use
`fakeAsync`/`async.elapse` except known web-socket tests (spot-verified).

## Sound surface

`FakeSoundService` exists in test/model/common/service/fake_sound_service.dart and
records nothing (`Service.play` returns Future.value). `_RecordingSoundService`
exists in exactly one file (review_controller_test.dart). `test/sound/` does
not exist. Sound coverage = 2 tests completing on the fake (`sound_service_test:63`),
plus the 2 recording-style controller tests. No observed "played" state anywhere
in CI-visible tests — standing caveat docs/manual-test-log.md documents.

## Ledger / provenance cross-checks

- `docs/AUTONOMOUS_WORK_LEDGER.md` row for Stream 1 mutation on `scheduler.dart`
  says 10 mutants evaluated, 6 killed, 4 survived — the runner outputs are NOT
  committed (scripts/autonomous/ is untracked); the survival evidence is unreachable
  to review until those outputs or their hashes are committed.
- `docs/spec-conformance-audit-2026-10-16.md` still holds and this audit does not
  re-open F1-F6 (see dedup note in README).

## Not verified

- No `flutter test` for the audit itself (explicit user instruction or
  machine heat): all strength claims are from READ + MUTANT/SHELL作品展.
- Engine/socket/NNUE directories were not per-line walked; the timing-class
  findings about them are from `rg` counts + per-file reads of the two worst files only.
