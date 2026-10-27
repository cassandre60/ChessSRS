# MUTATION-11 — account_repository first audit (Stream 1)

## Premise (re-runnable)

Selected via the queue tool, not the catalogue:

```
python3 scripts/autonomous/ledger.py next --stream A
#   NEXT TARGET FOUND: lib/src/model/account/account_repository.dart
#   Current source hash: a2d51b8bb | Mapped test: test/model/account/account_repository_test.dart
#   Composite hash:      a2d51b8bb:c8def723a
#   Last audited hash:   NEVER
```

First audit. The file owns the account data layer: the `accountProvider` /
`kidModeProvider` Riverpod providers and the `AccountRepository` (profile read/write,
preferences, bookmarking).

## Collision check (2026-10-26)

- Open PRs: #429, #430, #431, #432 — none touches
  `lib/src/model/account/account_repository.dart` or
  `test/model/account/account_repository_test.dart`.
- Ledger: the target is `NEVER` audited; no REJECTED/WONTFIX disposition.

## Oracle

```
fvm flutter test test/model/account/account_repository_test.dart --concurrency=1
```

Baseline (fresh worktree at `97cc2eccc`, 2026-10-26): 1 test green, ~8 s
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
| Killed (engine, original suite) | 0 |
| Survived → killed by new tests | 2 |
| Survived → EQUIVALENT (no pin) | 0 |
| Uncompilable (excluded) | 0 |
| Timed out | 0 |

2 candidates — the dart rule pack finds the null check in `accountProvider` and
the boolean default in `kidModeProvider`; 0/2 killable before the round, 2/2
after.

Survivor triage:

- **Line 13** (`authUser == null` → `!= null` in `accountProvider`): real gap,
  pinned. Flipping the guard would make the profile fetch unreachable for a
  signed-in user. Killed by `accountProvider fetches the profile when signed in`.
- **Line 20** (`account?.kid ?? false` → `?? true` in `kidModeProvider`): real
  gap, pinned. A signed-out session would report kid mode on. Killed by
  `kidModeProvider defaults to false when signed out`.

4 tests in the oracle (was 1). No production defect found. `lib/` byte-identical
to origin/main.

Verification note (2026-10-26): `gates.sh t1` expected to pass; no source file
is touched.
