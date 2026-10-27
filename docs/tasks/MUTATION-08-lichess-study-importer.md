# MUTATION-08 — lichess_study_importer first audit (Stream 1)

## Premise (re-runnable)

Selected via the queue tool:

```
python3 scripts/autonomous/ledger.py next --stream A
#   NEXT TARGET FOUND: lib/src/import/lichess_study_importer.dart
#   Current source hash: b1a5cbee8 | Mapped test: test/import/lichess_study_importer_test.dart
#   Composite hash:      b1a5cbee8:1a423d1b3
#   Last audited hash:   NEVER
```

First audit. The file parses Lichess study URLs/raw IDs into an id + host and
extracts a study-level title from PGN headers (`StudyName`, then `Event`).

## Collision check (2026-10-26)

- Open PRs: none touching `lib/src/import/lichess_study_importer.dart` or
  `test/import/lichess_study_importer_test.dart`.
- Ledger: the target is `NEVER` audited; no REJECTED/WONTFIX disposition.

## Oracle

```
fvm flutter test test/import/lichess_study_importer_test.dart --concurrency=1
```

Baseline (fresh worktree at `97cc2eccc`, 2026-10-26): 14 tests green, ~19 s
test time.

## Plan

1. Full-window engine run (`--max-mutants 500`, `--timeout 120`, JSON report to
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
| Killed (engine, original suite) | 3 |
| Survived → killed by the new tests | 1 |
| Survived → EQUIVALENT (no pin) | 0 |
| Uncompilable (excluded) | 7 |
| Timed out | 0 |

11 candidates — the dart rule pack finds 11 mutants across the file; 3/4
compilable survivors killed before the round, 1/1 after.

Survivor triage:

- **Line 45** (`studyName.isNotEmpty` → `studyName.isEmpty`): real gap, pinned.
  A non-empty `StudyName` header must win over an `Event` header without a
  colon. Killed by `prefers a non-empty StudyName header over an Event
  without a colon` — red under the mutant, green on clean source.

No production defect found. 15 tests in the oracle (was 14). `lib/`
byte-identical to origin/main.

Verification note (2026-10-26): `gates.sh t1` is expected to pass; the
touched file is format-clean.
