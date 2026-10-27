# MUTATION-09 — pgn_importer first re-audit (Stream 1)

## Premise (re-runnable)

Selected via the queue tool:

```
python3 scripts/autonomous/ledger.py next --stream A
#   NEXT TARGET FOUND: lib/src/import/pgn_importer.dart
#   Current source hash: ebc82a7e0 | Mapped test: test/import/pgn_importer_test.dart
#   Composite hash:      ebc82a7e0:0b8efc3ee
#   Last audited hash:   888ab4e28
```

Re-audit (source moved since 888ab4e28). The file parses a multi-game PGN into an
`ImportResult` (chapters, decisions, errors), resolves chapter orientation and
titles, and fingerprints the PGN for duplicate detection.

## Collision check (2026-10-26)

- Open PRs: none touching `lib/src/import/pgn_importer.dart` or
  `test/import/pgn_importer_test.dart` (#429/#430 cover other files).
- Ledger: target last audited at `888ab4e28`; source hash now `ebc82a7e0`.

## Oracle

```
fvm flutter test test/import/pgn_importer_test.dart --concurrency=1
```

Baseline (fresh worktree at `97cc2eccc`, 2026-10-26): 85 tests green, ~6 s
test time (startup-dominated).

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
| Killed (engine, original suite) | 43 |
| Survived → killed by the new tests | 6 |
| Survived → EQUIVALENT (no pin) | 5 |
| Uncompilable (excluded) | 24 |
| Timed out | 0 |

78 candidates — the dart rule pack finds 78 mutants across the file; 43/54
compilable killed before the round, 6/11 survivors after.

Survivor triage:

- **Line 163** (`hasErrors => errors.isNotEmpty` → `errors.isEmpty`): no pin.
  `hasErrors` has no caller in `lib/` or `test/` (dead getter); a mutation
  there cannot affect any observable behaviour. Classified EQUIVALENT (dead
  code).
- **Line 164** (`isEmpty => chapters.isEmpty` → `chapters.isNotEmpty`): no pin.
  Same as above — `ImportResult.isEmpty` is never read outside its definition.
- **Line 242** (null check `parsedGames != null` → `== null`): no pin.
  `parsedGames` is never supplied by any caller, so both branches reduce to
  `computePgnHash(pgnText)`; the mutation is behaviourally identical on the
  reachable path.
- **Line 261** (`moveIndex: -1` → `-2` in the catastrophic-parse catch): no
  pin. That catch wraps a parser that never throws (malformed text parses as
  moveless games), so the branch is unreachable; the `-1` sentinel is already
  pinned for the three reachable fatal paths.
- **Line 404** (`if (errors.isNotEmpty)` → `errors.isEmpty`): no pin.
  Controls only a `_logger.warning` call; no test asserts on log output, and
  logging is not part of the import contract.
- **Line 485** (`caseSensitive: false` → `true` on the white-keyword regex):
  real gap, pinned. The white-keyword path had no case-variation test, so a
  flip to case-sensitive matching would pass silently. Killed by
  `a mixed-case white keyword still resolves to white`.
- **Line 503** (`||` → `&&` in `whiteIsPlaceholder`): real gap, pinned.
  `'*'` would stop counting as a sentinel. Killed by
  `a "*" white tag resolves orientation to black`.
- **Line 503** (`white.isEmpty` → `white.isNotEmpty`): real gap, pinned.
  A real name would be treated as a placeholder. Killed by
  `two real player names do not make white a placeholder`.
- **Line 504** (`||` → `&&` in `blackIsPlaceholder`): real gap, pinned.
  Killed by `a "*" black tag resolves orientation to white`.
- **Line 504** (`black.isEmpty` → `black.isNotEmpty`): real gap, pinned.
  Killed by `two real player names with a black-to-move start stay black`.
- **Line 542** (`v.trim().isNotEmpty` → `isEmpty` in the Chapter/ChapterName
  loop): real gap, pinned. A real chapter name would be skipped. Killed by
  `a dedicated Chapter tag wins the chapter title`.

6 real gaps pinned; 5 survivors classified EQUIVALENT (dead code, unreachable
path, or log-only). No production defect found. 91 tests in the oracle
(was 85). `lib/` byte-identical to origin/main.

Verification note (2026-10-26): `gates.sh t1` passed (G03, G07, G08, G05,
G10, G13 clean); ratchet improved `test_declarations` 2722 → 2747.
