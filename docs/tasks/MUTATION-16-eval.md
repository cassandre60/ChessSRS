# MUTATION-16 — mutation audit of `eval.dart`

**Date:** 2026-10-27
**Stream:** 1 (Mutation Testing & Test-Gap Elimination)
**Class:** test-only (no production code)
**Target:** `lib/src/model/common/eval.dart`
**Mapped test:** `test/model/common/eval_test.dart`
**Content hash under test:** `git hash-object` = `17a7fff8e` (never audited before;
selected via `ledger.py next --stream A`).

## Engine settings used

```bash
python3 scripts/autonomous/mutation_engine.py \
  --source lib/src/model/common/eval.dart \
  --test-cmd "fvm flutter test test/model/common/eval_test.dart --concurrency=1" \
  --max-mutants 500 \
  --timeout 210 \
  --output-json /tmp/mut_eval.json \
  --output-issue docs/tasks/mutant_issue.md
```

## Totals

| Outcome | Count (round 1) | Count (round 2) |
|---|---|---|
| Killed by the old suite | 1 | 20 |
| Survived | 21 | 2 |
| Closed in round 2 | — | 19 |
| Uncompilable (excluded) | 7 | 7 |
| Timed out | 0 | 0 |
| Kill rate (killable) | 4.5% | 90.9% (20/22) |

## Triage (round 2)

19 survivors closed by tests added to `test/model/common/eval_test.dart`
(9 → 42 tests in the mapped file). Each closed mutant has a per-mutant red
run (mutant applied → the named test fails) and the tree was restored and
verified byte-identical after each, with the full file green (42/42) on clean
code. Format + analyze clean on the touched file; `lib/` byte-identical
throughout (source hash still `17a7fff8e`).

| Mutant (line) | Gap closed | Killing test |
|---|---|---|
| L68 `isNotEmpty → isEmpty` | `bestMoves` drops PVs with empty move lists | `filters out pvs with empty moves` |
| L126 `depth > → >=` / `|| → &&` / `== → !=` / `&& → ||` / `nodes > → >=` | `LocalEval.isBetter` ordering (5 variants) | 5 `isBetter` tests |
| L145 `!= null → == null` | `ExternalEval.fromPgnEval` null pawns | `yields null cp when pawns is null` |
| L164 `!= null → == null` | `winningSide` mate branch | `mate takes precedence over cp` |
| L165 `> → >=` (mate) | mate-zero boundary | `mate zero -> black (boundary)` |
| L166 `!= null → == null` | `winningSide` cp branch | `mate null but cp present -> uses cp` |
| L167 `> → >=` (cp) | cp-zero boundary | `cp zero -> black (boundary)` |
| L200 `isNotEmpty → isEmpty` / `first → last` | `_firstMoveWithWinningChances` uses first move | `uses the first move of a multi-move pv` |
| L259 `> → >=` (0.3) | arrow scale threshold boundary | `scale drops to minScale only when diff exceeds 0.3` |
| L275 `== → !=` (i == 0) | best-move arrow colour | `first move uses bestMoveColor` |
| L297 `> → >=` (mate > 0) | mate-zero winning chances sign | `mate zero yields negative chances for white (boundary)` |
| L301 `== → !=` (side == white) | POV inversion | `black side inverts the perspective` |
| L306 `- 1 → - 2` | `_rawWinningChances` formula | `cp zero yields zero chances` |
| L321 `|| → &&` | `_evalString` zero-rounding normalisation | `rounds a tiny positive/negative cp ...` |

## Open survivors

- **L297** (`-1 → -2` in `_mateWinningChances`): equivalent mutant — both
  the original (`-1`) and the mutant (`-2`) produce a signed centipawn
  magnitude of at least 1100, which `_cpWinningChances` clamps to ±1000, so
  the resulting winning chances are identical for every mate score.
- **L324** (`> → >=` in `_evalString`): equivalent mutant — this branch is
  only reached when the formatted string is neither `'0.0'` nor `'-0.0'`, i.e.
  when the pawn value is not zero, so `e > 0` and `e >= 0` are
  indistinguishable.

## Mechanics worth recording

- `Move` (sealed) does not expose `from`/`to`; cast to `NormalMove` in tests
  when inspecting arrow origins.
- `PgnEvaluation` uses named constructors (`.pawns` / `.mate`); the unnamed
  constructor does not exist.
- Floating-point: a diff of exactly `0.3` is not representable from `0.8 - 0.5`;
  use `0.3 - 0.0` to hit the `> 0.3` boundary precisely.
- `lib/` byte-identical throughout (source hash `17a7fff8e`).
