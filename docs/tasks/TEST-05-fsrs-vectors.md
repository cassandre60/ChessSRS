# TASK-05 — Differential FSRS vectors

> **Pick this up in a fresh worktree.** `git worktree add ../chesssrs-fsrs-vectors -b test/fsrs-vectors origin/main` then `fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs`.

## Goal

Add a **differential oracle** for the FSRS kernel so parameter drift (blind spot #2) is caught mechanically, not by eyeballing w-values.

## Why

`lib/src/domain/chess_fsrs_scheduler.dart` (343 lines, D015 binary FSRS) has zero mutants and no reference vectors. The current `chess_fsrs_scheduler_test.dart` (21k lines) covers example trails. A Python FSRS repo (`py-fsrs` / `open-spaced-repetition/py-fsrs`) publishes `test_vectors.py` rows `(state, rating, elapsedDays → newState)` per weight set. Replaying those vectors through `ChessFsrsScheduler` with `|dart - python| < eps` is the highest-signal oracle for this module.

## What to do

1. **Fetch the vector source once and pin it.** Clone or vendor `open-spaced-repetition/py-fsrs` (or whichever Python implementation the current Dart weights derive from — `lib/src/domain/chess_fsrs_scheduler.dart:30-50` declares `w0..w14`). Run its `test_vectors.py` (or `tests/test_fsrs.py`) to dump **~200–500 rows** as JSON with the Dart `w0..w14` mapping applied. Check the JSON in as `test/fixtures/fsrs_vectors.json` (or `test_fixtures/` if the repo prefers it). Include the commit SHA of the Python repo as a header comment in the fixture. If the Python repo is unreachable, say so in the PR and fall back to the existing Dart vectors as a labelled manual method.
2. **Add `test/domain/chess_fsrs_vectors_test.dart`** that:
   - reads `test/fixtures/fsrs_vectors.json`,
   - for each row, calls `fsrsRetrievability`, `fsrsIntervalForTarget`, and `ChessFsrsScheduler.schedule(...)` (with `Clock` fixed at the row's `elapsedDays`),
   - asserts `|dart - python| < 1e-9` per scalar (or per `nextDueAt` in days, `difficulty`, `stability`). Choose `eps` honestly and **never widen it** to go green — if it fails, fix the Dart float path, not the tolerance. Document why `1e-9` is the smallest that keeps the test deterministic on dart 3.x's `double`.
   - is **deterministic** (fixed `Clock`, seeded `Random`, no wall-clock).
3. **Keep the test cheap.** 500 vectors at ~10µs each is ~5ms — well under the per-test budget. Do not add a per-vector `test()` decl (that would be 500 decls); one `test('FSRS vectors')` looping the fixture is correct.
4. **Format + analyze + targeted run:**
   ```bash
   fvm dart format test/domain/chess_fsrs_vectors_test.dart test/fixtures/fsrs_vectors.json
   fvm flutter analyze test/domain/chess_fsrs_vectors_test.dart
   fvm flutter test test/domain/chess_fsrs_vectors_test.dart --plain-name 'FSRS vectors'   # one test first
   fvm flutter test test/domain/chess_fsrs_vectors_test.dart                                # full file
   ```
   If TASK-01 landed, run `dart test test/domain/chess_fsrs_vectors_test.dart` instead.

## Fixture notes

- The Dart mapping is `ChessFsrsParams(w0:0.35, w2:2.20, ... , maxStabilityDays:365*5)` per `chess_fsrs_scheduler.dart`. Align the Python weights to this set before dumping — do not dump under Python's defaults and compare against Dart's.
- The fixture may also vendor `dartchess` perft counts later (audit §Blind 4); keep this PR to FSRS only. One oracle per PR.
- `test/fixtures/**` is a **protected path** (`.gates/protected-paths.txt`). Landing the fixture needs `gate-approved` label from the owner (G07). Mention this in the PR body.

## Done when

- [ ] `test/fixtures/fsrs_vectors.json` exists (rows + Python SHA header).
- [ ] `test/domain/chess_fsrs_vectors_test.dart` passes, `analyze` clean.
- [ ] Existing `chess_fsrs_scheduler_test.dart` still passes (no weakened mutant there — diff the two files' `spec_trace_check` coverage if you moved any `INV-0xx`).
- [ ] PR body lists the fixture size, the Python repo + SHA, the `eps`, and the targeted `flutter test` output.

## Not to do

- Do not add `test_dependencies` beyond `fake_async` unless needed (this needs none).
- Do not change `lib/src/domain/chess_fsrs_scheduler.dart` weights to match Python defaults — Dart's weights are the spec; the fixture must map to them.
- Do not widen `eps` or add `skip:` to go green.

## Evidence

- `fvm flutter test test/domain/chess_fsrs_vectors_test.dart` (or `dart test ...`) output.
- `fvm flutter analyze test/domain/chess_fsrs_vectors_test.dart`.
- `python3 scripts/gates/manual_mutation_runner.py --mutants .gates/mutants.json --test-cmd "fvm flutter test test/domain/chess_fsrs_scheduler_test.dart --no-pub" --force` if TASK-02 expanded FSRS mutants.

---
Source: `docs/test-audit/audit-report.md` §Top 10 blind spots #2 + #4, `redesign.md` §5, `GATES_PLAN.md` #10 (nightly).
