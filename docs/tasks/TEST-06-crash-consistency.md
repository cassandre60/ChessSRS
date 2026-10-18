# TASK-06 — Crash-consistency fault injection (T0)

> **Pick this up in a fresh worktree.** `git worktree add ../chesssrs-crash -b test/crash-consistency origin/main` then `fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs`.

## Goal

Prove **no orphan `srs_decision` / `position_knowledge_state` row** is left if the app dies mid-write (audit T0 blind spot #1). This is the only item that can silently destroy months of the owner's memorization work.

## Why

INV-001/002 assert durability and incremental scope, but **no test injects a fault** in `sqlite_study_repository.dart`'s `saveImportResult` / `submitMove` batch boundaries. Today WAL + `Batch` atomicity is assumed — a missing `transaction` is a silent survivor.

## Read before editing

- `docs/test-audit/audit-report.md` §Top 10 blind spots #1 + INV-001/002/004 in `SPEC.md`.
- `docs/test-audit/redesign.md` §6 (design: `FaultyDatabase` wrapper that throws at `Batch.commit`).
- `lib/src/persistence/sqlite_study_repository.dart` (where `saveImportResult` batches `srs_study` → `srs_chapter` → `srs_decision` → `position_knowledge_state`).
- `test/persistence/**` (existing `sqlite_study_repository_test.dart`, `srs_upgrade_test.dart` — both use `sqflite_common_ffi`) and `AGENTS.md` §3.1 (one-file targeted runs; no full-suite sweep locally).

## What to do

1. **Add a fault harness** `test/persistence/faulty_database.dart` (or extend the existing sqflite helper) that wraps `sqflite_common_ffi`'s `Database`/`Batch` and throws `DatabaseException` at a configured boundary:
   - after N rows of the current `Batch`,
   - or at `Batch.commit` call #K,
   - or after N `insert`s into `srs_decision`.
   The harness must support "fault at chapter-2 batch" so a 3-chapter PGN import can be torn mid-write.
2. **Add `test/persistence/crash_consistency_test.dart`** with at least two scenarios, each as a **fail-to-pass** loop (G09): stash the before-tree, run the failing write, assert the invariant, then re-run and watch it heal.
   - **Scenario A — torn import:** import a 3-chapter PGN via the faulty DB with a fault at chapter 2's batch. Assert the DB is left with **0 or 1 complete studies** (never a half-written chapter with orphan `srs_decision` rows pointing at a missing `srs_chapter`), and that a retry with a faultless DB succeeds.
   - **Scenario B — torn answer write:** graded `submitMove` that batches `position_knowledge_state` + `srs_review_state`. Inject a fault between the two writes and assert no orphan `position_knowledge_state` row without its `srs_review_state` counterpart (and vice versa), and that the next session recovers.
3. **Make the tests deterministic.** Inject a fixed `Clock`, use `sqflite_common_ffi` in-memory DB, and assert counts, not wall-clock. No `DateTime.now` here.
4. **Format + targeted run:**
   ```bash
   fvm dart format test/persistence/crash_consistency_test.dart test/persistence/faulty_database.dart
   fvm flutter analyze test/persistence/crash_consistency_test.dart
   fvm flutter test test/persistence/crash_consistency_test.dart --plain-name 'torn import'  # one test first
   fvm flutter test test/persistence/crash_consistency_test.dart                              # full file
   ```

## Done when

- [ ] `faulty_database.dart` (or equivalent) + `crash_consistency_test.dart` exist and pass.
- [ ] Both scenarios cite INV-001/002/004, and the torn-import scenario asserts "0 or 1 complete studies, never orphan `srs_decision`".
- [ ] `fvm flutter analyze` on touched files clean.
- [ ] Commit message records the before-state (no crash test) and the harness choice.

## Not to do

- Do not change the WAL / `Batch` / `transaction` strategy in `lib/` to make the test pass — **add the test first with a failing expectation**, then fix the `lib` site in a second `fix(persistence): wrap ... in transaction` commit if needed (one logical change per commit).
- Do not add `test --coverage` or a full-suite run locally.
- Do not widen tolerances or add `skip:`.

## Evidence

- Per-scenario `fvm flutter test ... --plain-name '<name>'` then full-file run.
- The G09 fail-to-pass pair if you add the fix: `bash scripts/gates/fail_to_pass_check.sh origin/main "fvm flutter test test/persistence/crash_consistency_test.dart"` output pasted in the PR body.
- `fvm flutter analyze` on the two new files.

---
Source: `docs/test-audit/audit-report.md` T0 #1, `redesign.md` §6, `GATES_PLAN.md` #10 nightly crash-consistency.
