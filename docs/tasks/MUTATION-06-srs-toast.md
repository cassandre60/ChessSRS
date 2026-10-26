# MUTATION-06 — srs_toast first audit (Stream 1)

## Premise (re-runnable)

Selected via the queue tool, not the catalogue:

```
python3 scripts/autonomous/ledger.py next --stream 1 --limit 6
#   NEXT TARGET FOUND: lib/src/design/srs_toast.dart
#   Current source hash: dfbdd83a8 | Mapped test: test/design/srs_toast_test.dart
#   Last audited hash:   NEVER
```

First audit. The file is the Diagram toast (`design/docs/03-components.md` §12):
a timer, an overlay entry and a replace-don't-stack singleton, with the spec's
numbers (160 ms entry, 2.4 s dwell, bottom 24, radius 999, one line) as the
observable contract.

## Collision check (2026-10-26)

- Open PRs: #426 only (ledger row for `graph_aware_review_coordinator.dart` at
  the hash its audit measured) — different file, no overlap.
- Every branch with a live worktree was diffed against its merge-base with
  origin/main for `lib/src/design/srs_toast.dart` and
  `test/design/srs_toast_test.dart`: no hits. The seven branches that touched
  the toast test around #409 time (MUTATION-05's collision note) are gone from
  the live set.
- Ledger: the target is `NEVER` audited; no REJECTED/WONTFIX disposition.

## Oracle

```
fvm flutter test test/design/srs_toast_test.dart --concurrency=1
```

Baseline (fresh worktree at `ae6380dbd`, 2026-10-26): 6 tests green, ~25 s
test time (startup-dominated; `--timeout 300` ≈ 12×).

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

## Results (2026-10-26)

| State | Count |
|---|---|
| Killed (engine, original suite) | 0 |
| Survived → killed by the new tests | 2 |
| Survived → EQUIVALENT (no pin) | 0 |
| Uncompilable (excluded) | 1 |
| Timed out | 0 |

3 candidates — the dart rule pack finds only three boolean/null operators in the
file; 0/2 killable before the round, 2/2 after. The uncompilable is the
`== null` inversion on the early return (type-promotion noise, same class as
prior rounds').

Survivor triage (dispositions in `docs/AUTOMOUS_MUTANTS.md` at source hash
`dfbdd83a8`):

- **Line 42** (`Overlay.maybeOf(context, rootOverlay: true)` → `false`): real
  gap, pinned. The toast is app chrome — §12 puts it at z-index 40, above the
  scrim and the sheet, neither of which lives inside a nested subtree — so a
  context below a *nested* navigator's overlay must resolve to the rootmost
  overlay. Clean source does; the mutant filed the toast into the nested
  subtree. New test `renders in the root overlay even from inside a nested
  navigator` builds a shell with its own `Navigator`, asserts the toast renders
  outside the shell subtree; red under the mutant, green on clean source.
- **Line 43** (`Navigator.maybeOf(context, rootNavigator: true)` → `false`):
  first called EQUIVALENT ("the fallback only runs where no overlay exists
  above, i.e. at the rootmost navigator, where both flags agree") — the round's
  refutation pass **refuted that**, empirically, against the framework source:
  an app-placed `LookupBoundary` clips `Overlay.maybeOf`'s marker walk
  (`lookup_boundary.dart`, `boundary.depth > candidate.depth`), so a nested
  navigator's own key context can reach the fallback with overlays above it,
  and `Navigator.maybeOf`'s `??` asymmetry (`rootNavigator: false` takes the
  context-owned navigator, `true` takes the rootmost ancestor) then picks
  different navigators. Killed by `a navigator-key context past a LookupBoundary
  still resolves to the root` — red under the mutant, green on clean source.
  The refuted EQUIVALENT row stays in `docs/AUTONOMOUS_MUTANTS.md` history,
  superseded by the topmost KILLED-BY row.

Both kills pin the same documented contract from the file's own header comment:
the toast is app-level chrome — both lookups in the pair are load-bearing, and
now both are enforced. 8 tests in the oracle (was 6). No production defect
found. `lib/` byte-identical to origin/main. Re-audit trigger: any modification
to `srs_toast.dart` or `test/design/srs_toast_test.dart`.
