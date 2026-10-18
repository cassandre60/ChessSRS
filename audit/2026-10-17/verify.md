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
  *(Figure corrected 2026-10-18: 349 deletions = 18.8% of 1858, not 25% — the
  tolerance is 0, so the floor trips only when the strict count falls below
  1509, i.e. after deleting the entire stale-by margin. The floor was
  tightened to the measured 2026-10-18 state in #209.)*
- `.gates/mutants.json` entry #2 (`occurrence: 2`) matches the exact identical
  string only ONCE per file (both `notification` occurrences use the same
  textual match string; the occurrences diverge elsewhere) — the runner reports
  it as SURVIVED "no numeric change" though it changed the second scheduler.
  Every other mutant in the file is valid. Fix: use a uniqueness-anchored
  longer match or occurrence counts.
  **Superseded 2026-10-18 by live mutant runs** (see PRs #210 and #211): this
  write-up is wrong in its mechanics. The find string of entries #1/#2 — the
  two byte-identical `_clamp` ternaries (SimpleScheduler and
  EaseScalingScheduler) — occurs **exactly twice** in scheduler.dart, so
  nothing was "matched only once"; the runner's occurrence targeting applied
  correctly and did mutate the second `_clamp`; and the quoted "no numeric
  change" phrasing does not exist in the runner's output. The verified defects
  instead: (a) the `>`-vs-`>=` clamp mutants are **semantically equivalent**
  at whole-millisecond granularity (both branches return equal-valued
  Durations at equality), so no test could ever kill them and the notes'
  kill-claims were false data; (b) `interval is capped at maximumInterval`
  accepted the drop-the-cap mutant because a broken-cap pump ends on an
  overflowed negative interval (~−13.5M days) satisfying `<= 30` — fixed in
  #210 by pinning exact cap equality; (c) the remaining four entries' claims
  verified true — 6/6 killed on the corrected referee file in #211. Entry
  #2's existence as a finding unit is itself dissolved: both clamp entries
  needed replacement, not occurrence-targeting changes.

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
  machine heat): all strength claims are from READ + MUTANT/SHELL evidence.
- Walker grade rows are transcribed digests from read-only walker sessions,
  not independently re-derived line-by-line by the author; spot-re-verified
  against source before committing: log_screens tautology (:52), screenshot
  golden comparator vs header (matchesGoldenFile :253, no
  flutter_test_config.dart, 120 committed PNGs), pgn_offload FLUTTER_TEST
  short-circuit (:15/:26), sound_service completes-only (:28/:50),
  engine_gauge text-only (:13), user_repository length-only (:408/:426),
  srs_toast tone loop never passing `type:` (:138 — overruling the design
  walker's 6/6 histogram). No test was executed to confirm any grade.
