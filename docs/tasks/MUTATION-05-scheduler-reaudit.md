# MUTATION-05 — scheduler re-audit after the lapse-caps change (Stream 1)

## Premise (re-runnable)

The ledger's composite hash for `lib/src/domain/scheduler.dart` drifted:

```
python3 scripts/autonomous/ledger.py next --stream 1 --limit 12
#   lib/src/domain/scheduler.dart | current e91aa7578 | last audited 20046b4b6
```

The drift is #383 (fix(scheduler): apply interval caps to lapse retries, merged
2026-10-23), which changed both lapse-retry behavior and the source hash. The
ledger's Re-Audit Trigger for this file ("any modification to scheduler.dart")
is therefore satisfied: the file's behavior changed since the last round.

## Collision check (2026-10-24)

- Open PRs: #415 (ledger row, docs-only), #416 (app_links tests) — neither
  touches scheduler files.
- Local in-flight branches: `fix/audit-lapse-interval-bounds` (the change that
  caused the drift) is MERGED, its PR #383 is closed; no open branch touches
  `lib/src/domain/scheduler.dart` or `test/domain/scheduler_test.dart`.
- `test/domain/scheduler_lapse_bound_test.dart` (added by #383) is included in
  the oracle so the round measures the honest kill rate against the new
  behavior, not just the pre-#383 suite.
- Queue order: `openings_database` (dedup-stale: #409 merged, row #415 pending)
  and `srs_toast` (seven in-flight branches touched its test file at #409 time;
  `auth_controller` / `server_analysis_service` claimed by polls branches) are
  skipped; this target is next unclaimed with real drift.

## Oracle

```
fvm flutter test test/domain/scheduler_test.dart test/domain/scheduler_lapse_bound_test.dart --concurrency=1
```

Baseline (fresh worktree, 2026-10-24): 32 tests, ~26 s wall (startup-dominated).

## Plan

1. Full-window engine run (`--max-mutants 500`, `--timeout 300` ≈ 10× baseline,
   JSON report to /tmp — never committed).
2. Triage every survivor by hand: re-apply, red under `--plain-name`, restore,
   `git diff --quiet -- lib/`.
3. Pin real gaps with new tests (each red under the mutant, green on clean
   tree); dispositions KILLED-BY / EQUIVALENT via `mutants.py`.
4. Round summary table here; ledger row in a SEPARATE protected-path PR
   (owner approval per AGENTS §10; the row is not in this PR).

Class: test-only. `lib/` must end byte-identical to origin/main.
