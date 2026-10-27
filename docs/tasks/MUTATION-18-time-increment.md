# MUTATION-18 — mutation audit of `time_increment.dart` (Stream 1)

## Premise (re-runnable)

Selected via the queue tool as the next never-audited Stream A target:

```
python3 scripts/autonomous/ledger.py next --stream A
#   NEXT TARGET FOUND: lib/src/model/common/time_increment.dart
#   Mapped test: test/model/common/time_increment_test.dart
```

`TimeIncrement` is the game-clock value type (`time`/`increment` seconds pair,
duration constructor, `isInfinite`, `estimatedDuration`, equality chain) shared
by every clock preset and persistence path. This wake resumed an interrupted
same-day run that had already produced the engine reports and the new tests in
this worktree; every verdict below was re-verified by hand this wake (per-mutant
red runs, byte-identical restores) rather than trusted from the cached reports.

## Collision check (2026-10-27)

- Open PRs: none touching `lib/src/model/common/time_increment.dart` or its
  mapped test (#444 is a skill sync, #436 a server-analysis fix).
- Ledger: target never audited; the 13 commits main gained while the audit was
  in flight (MUTATION-07…17 landings) do not touch either file, so the cached
  engine verdicts stayed valid for the unchanged source hash.

## Oracle

```
fvm flutter test test/model/common/time_increment_test.dart --concurrency=1
```

## Plan

1. Full-window engine run (`--max-mutants 500`, `--timeout 150`, JSON report to
   `.autonomous/` — never committed).
2. Triage survivors; pin real gaps with new tests (each red under the mutant,
   green on clean source).
3. Round summary table here; ledger row in a SEPARATE protected-path PR.

Class: test-only. `lib/` ends byte-identical to origin/main.

## Results (2026-10-27)

| Outcome | First run | Final |
|---|---|---|
| Killed | 10 | 11 |
| Survived | 1 | 0 |
| Uncompilable (excluded) | 5 | 5 |
| Timed out | 0 | 0 |
| Kill rate (killable = 11) | 90.9% | 100% |

16 candidates total. The mapped test file grew 6 → 15 tests. Source hash
`143c23f95` before and after (`lib/` byte-identical; re-verified after every
mutant run and at the end).

### The closed gap

- **L43 `identical(this, other) ||` → `&&` in `operator ==`**: with distinct
  but field-equal instances the conjunctive form makes equality always false.
  The pre-existing equality test could not see it — its operands are `const`,
  and const instances with equal fields are canonicalized to a single object,
  so `identical` short-circuits and no field comparison runs (the same
  canonicalization trap as #203/#271, cf. SPEC INV-026). Pinned by
  `Equality holds for runtime-equal, distinct instances`, which builds both
  sides at runtime, asserts `identical(a, b)` is false, and still requires
  `a == b` with matching hash codes.

### New pins (defense in depth, hand-verified red)

| Mutant | Killing test (red under the mutant, green on clean source) |
|---|---|
| L6 `&&` → `||` (constructor assert) | `Rejects a negative initial time` and `Rejects a negative increment` |
| L11 `>=` → `>` on `time` (duration assert) | `fromDurations accepts zero durations (the infinite clock)` |
| L45 `runtimeType ==` → `!=` | `Equality requires the same runtime type` (equal-field subclass) and `Equality holds for runtime-equal, distinct instances` |
| L46 / L47 `==` → `!=` (field comparisons) | `Equality distinguishes the initial time alone` / `... the increment alone` |

The remaining new tests pin the duration-constructor negative rejects and the
zero-duration infinite clock values.

### Uncompilable (5, excluded as compile noise, not gaps)

- L6 `>=` → `>` (both operands): `presets` and `TimeIncrement.infinite()`
  contain zero-valued const instances, so the tightened assert fails **const
  evaluation** and the library no longer compiles.
- L44/L45/L46 `&&` → `||` in the equality chain: the disjunction drops the
  `other is TimeIncrement` type promotion for the right-hand operand, so
  `other.time`/`other.increment` become `undefined_getter` compile errors.

No survivors remain; no equivalents to document; no production defect found.
