# MUTATION-07 — theme_bridge first audit (Stream 1)

## Premise (re-runnable)

Selected via the queue tool, not the catalogue:

```
python3 scripts/autonomous/ledger.py next --stream A
#   NEXT TARGET FOUND: lib/src/design/theme_bridge.dart
#   Current source hash: 98ad8b774 | Mapped test: test/design/theme_bridge_test.dart
#   Composite hash:      98ad8b774:7afd8b42e
#   Last audited hash:   NEVER
```

First audit. The file is the bridge between `SrsColors` and Material `ThemeData`:
it builds a `ColorScheme` and a `ThemeData` whose interactive controls (filled
button, segmented selection, switch track) are ink rather than the Material
accent, plus an input-decoration fill and a post-2023 slider appearance.

## Collision check (2026-10-26)

- Open PRs: none touching `lib/src/design/theme_bridge.dart` or
  `test/design/theme_bridge_test.dart`.
- Ledger: the target is `NEVER` audited; no REJECTED/WONTFIX disposition.

## Oracle

```
fvm flutter test test/design/theme_bridge_test.dart --concurrency=1
```

Baseline (fresh worktree at `97cc2eccc`, 2026-10-26): 6 tests green, ~8 s
test time (startup-dominated; `--timeout 300` ≈ 37×).

## Plan

1. Full-window engine run (`--max-mutants 500`, `--timeout 300`, JSON report to
   /tmp — never committed).
2. Triage every survivor by hand: re-apply, red under `--plain-name`, restore,
   `git diff --quiet -- lib/`.
3. Pin real gaps with new tests (each red under the mutant, green on clean
   tree).
4. Round summary table here; ledger row in a SEPARATE protected-path PR.

Class: test-only. `lib/` must end byte-identical to origin/main.

## Results (2026-10-26)

| State | Count |
|---|---|
| Killed (engine, original suite) | 0 |
| Survived → killed by the new tests | 2 |
| Survived → EQUIVALENT (no pin) | 0 |
| Uncompilable (excluded) | 0 |
| Timed out | 0 |

2 candidates — the dart rule pack finds only the two boolean literals in the
file; 0/2 killable before the round, 2/2 after.

Survivor triage:

- **Line 119** (`filled: true` → `false`): real gap, pinned. The input
  decoration is deliberately filled with the surface colour, so an un-migrated
  field reads as part of the system rather than a transparent Material field.
  Killed by `input decoration is filled` — red under the mutant, green on clean
  source.
- **Line 225** (`year2023: false` → `true`): real gap, pinned. The slider
  opts out of the deprecated 2023 appearance. Killed by `slider uses the
  post-2023 style` — red under the mutant, green on clean source.

Both kills pin constants that were previously unguarded. 10 tests in the oracle
(was 6). No production defect found. `lib/` byte-identical to origin/main.

Verification note (2026-10-26): the referee's `gates.sh t1` is expected to
pass; the touched file is format-clean.
