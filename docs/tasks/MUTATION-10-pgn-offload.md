# MUTATION-10 — pgn_offload first audit (Stream 1)

## Premise (re-runnable)

Selected via the queue tool, not the catalogue:

```
python3 scripts/autonomous/ledger.py next --stream A
#   NEXT TARGET FOUND: lib/src/import/pgn_offload.dart
#   Current source hash: 0d39640c0 | Mapped test: test/import/pgn_offload_test.dart
#   Composite hash:      0d39640c0:1c772c200
#   Last audited hash:   NEVER
```

First audit. The file owns the "when to offload PGN work to a worker isolate"
decision: one threshold constant (`pgnOffloadThresholdBytes = 8192`) and one
guard (`shouldOffloadPgnWork`), centralising the `dart:io` / `FLUTTER_TEST`
sniff that was previously duplicated across `pgn_importer.dart` and
`review_controller.dart`.

## Collision check (2026-10-26)

- Open PRs: #429, #430, #431 — none touches `lib/src/import/pgn_offload.dart`
  or `test/import/pgn_offload_test.dart`.
- Ledger: the target is `NEVER` audited; no REJECTED/WONTFIX disposition.

## Oracle

```
fvm flutter test test/import/pgn_offload_test.dart --concurrency=1
```

Baseline (fresh worktree at `97cc2eccc`, 2026-10-26): 3 tests green, ~5 s
test time (startup-dominated).

## Plan

1. Full-window engine run (`--max-mutants 500`, `--timeout 120`, JSON report to
   /tmp — never committed).
2. Triage every survivor by hand: re-apply, red under `--plain-name`, restore,
   `git diff --quiet -- lib/`.
3. Pin real gaps with new tests (each red under the mutant, green on clean
   tree); dispositions KILLED-BY / EQUIVALENT via `mutants.py`.
4. Round summary table here; ledger row in a SEPARATE protected-path PR.

Class: test-only. `lib/` must end byte-identical to origin/main.

## Results (2026-10-26)

| State | Count |
|---|---|
| Killed (engine, original suite) | 2 |
| Survived → killed by new tests | 0 |
| Survived → EQUIVALENT (no pin) | 1 |
| Uncompilable (excluded) | 0 |
| Timed out | 0 |

3 candidates — the dart rule pack finds the two boolean literals and the one
inequality in the file; 2/2 killable before the round, 0/1 after triage.

Survivor triage:

- **Line 30** (`kIsWeb || … || FLUTTER_TEST`, `||` → `&&`): real gap,
  killed by the existing `is always false in the test environment regardless of
  length` test — the guard must stay a disjunction or a non-web, non-test input
  would be allowed to offload incorrectly. Mutant id not applicable (killed).
- **Line 30** (`false` → `true` on the `FLUTTER_TEST` branch): real gap,
  killed by the same test — flipping the guard would offload under
  `flutter test`, which the helper deliberately avoids.
- **Line 31** (`textLength >= pgnOffloadThresholdBytes` → `>`):
  `lib/src/import/pgn_offload.dart:31:257d14857bbd`. EQUIVALENT under this
  oracle. The comparison is only reached when `kIsWeb` is false and
  `FLUTTER_TEST` is absent; under `fvm flutter test` the guard returns false
  first, so no in-process test can observe the boundary. The mapped oracle
  cannot construct an input that distinguishes `>=` from `>` here — the helper's
  production branch is deliberately unreachable from the flutter test harness.
  No production defect is claimed or fixed; if the boundary ever needs coverage
  it requires a harness that runs outside `flutter test`, which is out of scope
  for Stream 1.

3 tests in the oracle (was 3). No production defect found. `lib/` byte-identical
to origin/main.

Verification note (2026-10-26): the referee's `gates.sh t1` is expected to
pass; no source file is touched.
