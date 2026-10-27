# MUTATION-12 — forecast first audit (Stream 1)

## Premise (re-runnable)

Selected via the queue tool, skipping `pgn_offload.dart` which already has an
open in-flight PR (#432):

```
python3 scripts/autonomous/ledger.py next --stream A
#   NEXT TARGET FOUND: lib/src/model/analysis/forecast.dart
#   Current source hash: (see ledger) | Mapped test: test/model/analysis/forecast_test.dart
```

First audit. `Forecast` is the correspondence-game conditional-premove ("forecast")
model: it stores premoves, detects collisions between candidate lines, truncates
lines to a sane length, and advances them when a move is played.

## Collision check (2026-10-26)

- Open PRs: none touching `lib/src/model/analysis/forecast.dart` or
  `test/model/analysis/forecast_test.dart`.
- Ledger: the target is `NEVER` audited; no REJECTED/WONTFIX disposition.

## Oracle

```
fvm flutter test test/model/analysis/forecast_test.dart --concurrency=1
```

Baseline (fresh worktree at `97cc2eccc`, 2026-10-26): 12 tests green.

## Plan

1. Full-window engine run (`--max-mutants 500`, `--timeout 120`, JSON report to
   /tmp — never committed).
2. Triage every survivor by hand: re-apply, red under the mutant, restore,
   `git diff --quiet -- lib/`.
3. Pin real gaps with new tests (each red under the mutant, green on clean
   tree).
4. Round summary table here; ledger row in a SEPARATE protected-path PR.

Class: test-only. `lib/` must end byte-identical to origin/main.

## Results (2026-10-26)

| State | Count |
|---|---|
| Killed (engine, original suite) | 7 |
| Survived → killed by the new tests | 1 |
| Survived → EQUIVALENT (no pin) | 2 |
| Uncompilable (excluded) | 1 |
| Timed out | 0 |

11 candidates total. 7/11 killable before the round, 8/11 after (one survivor
pinned).

Survivor triage:

- **Line 30** (`i < min(...)` → `i <= min(...)`): EQUIVALENT. The extra
  iteration only happens when one line is a prefix of the other, but that case
  is already handled by the `contains` short-circuit in `add` before
  `_collides` is ever called; the prefix branch of `_collides` is dead.
- **Line 41** (`return false` → `return true`): EQUIVALENT. Same dead branch as
  above — the prefix return in `_collides` is unreachable in `add`.
- **Line 85** (`line.head == ...` → `line.head != ...` in
  `linesStartingWith`): real gap, pinned. `playMove` must keep only the forecast
  lines beginning with the played move (and trim them); the inversion kept the
  wrong set. Killed by `keeps only lines starting with the played move and
  trims them` — red under the mutant, green on clean source.

No production defect found. `lib/` byte-identical to origin/main. 13 tests in
the oracle (was 12).
