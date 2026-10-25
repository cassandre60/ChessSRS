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

Baseline (fresh worktree at `ae6380dbd`, 2026-10-26): see Results.

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

(filled at the end of the round)
