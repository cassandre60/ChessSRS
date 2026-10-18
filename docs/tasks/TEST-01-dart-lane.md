# TASK-01 — Pure `dart test` lane

> **Pick this up in a fresh worktree.** `git worktree add ../chesssrs-dart-lane -b feat/test-dart-lane origin/main` then `fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs`.

## Goal

Make the pure-Dart SRS core run as **plain `dart test`** (no `flutter_tester`, no widget binding) so CI can split into `dart test` (cheap) + `flutter test` (expensive). Projected **~100s saved** off `Tests` (~291s → ~190s) per `redesign.md` §1.

## Why this is #1

`lib/src/domain/**` (25 files, 3.76k lines) is pure Dart — zero `package:flutter` imports (verified: `rg "package:flutter" lib/src/domain`). `Clock`/`Random` seams already exist. Today 100% of tests import `flutter_test` for matchers, so 100% pay the flutter binding cost. Separating them is the highest ROI lever and unblocks CI tiering (task 07).

## Seam inventory (already measured — do not re-audit)

| Lib seam | Finding | Action |
|---|---|---|
| `lib/src/domain/**` | pure | none |
| `lib/src/import/pgn_offload.dart` | 2 flutter lines: `kIsWeb` + `FLUTTER_TEST` env check | task may leave this file on the flutter lane; not worth a `refactor(testability)` here |
| `lib/src/persistence/sqlite_study_repository.dart` | 1 `flutter_riverpod` line (provider wrapper) | class itself takes `Database`; provider is the seam — nothing to change |

## What to do

1. **Read before editing:** `docs/test-audit/baseline.md` §1, `redesign.md` §1, `AGENTS.md` §3.1 (local test budget), `GATES.md` + `.gates/protected-paths.txt` (this is a **protected-path PR**).
2. **Decide `dart_test.yaml` placement.** Put it at the repo root. Typical shape:
   ```yaml
   # dart_test.yaml — keeps flutter_test for widget tests, allows dart test for pure tests
   tags:
     dart: { }   # or define "unit"/"widget" tags for tiering; TASK-07 will formalize them
   ```
   An alternative with no file is to just convert headers and invoke `dart test test/domain/...` directly. Either works — choose the one that stays green on CI's `flutter test` (the suite must still pass). Document the choice in the PR body.
3. **Convert test headers** for `test/domain/**` (8 files today + `scheduler_properties_test.dart`) and optionally `test/import/**` (minus `pgn_offload_test.dart`) and `test/persistence/srs_schema*` — any file whose `lib` target is pure on the inventory above. The header change is `import 'package:flutter_test/flutter_test.dart'` → `import 'package:test/test.dart'` (or `package:checks/checks.dart` if you add `checks`; TASK-02 may decide). Keep `flutter_test` where the test actually pumps a widget or reads `WidgetTester`.
4. **Add a dev dependency if needed.** If the conversion needs `package:test` or `package:checks`, add it to `pubspec.yaml`. This is a **protected path** — the PR must be labelled `gate-approved` by the owner (G07) and CI will enforce `Tests` + `T1 fast gates`. State the size cost in the PR body.
5. **Add or update the CI lane** *or* leave that to TASK-07 — but **do not break CI**. The existing `flutter test` must still pass after your header edits (pure `test` imports do not satisfy `flutter test` on those files, so you must either keep a `flutter test` lane that skips them or make `dart_test.yaml` route them correctly). The simplest green path is: keep `flutter test` as the suite authority and verify locally that `dart test test/domain/...` passes with no widget binding.
6. **Format + analyze + targeted test:**
   ```bash
   fvm dart format .
   fvm flutter analyze              # or dart analyze for pure files — just say which you ran
   fvm flutter test test/domain/scheduler_properties_test.dart --plain-name '<one>'
   fvm flutter test test/domain/scheduler_properties_test.dart   # one full-file run at the end
   dart test test/domain/scheduler_properties_test.dart           # prove the pure lane works
   ```
   Do not run `./verify` or the full 183-file suite locally (AGENTS.md §3.1). State in the commit/PR what was run.

## Done when

- [ ] `dart test test/domain/...` (or at least `test/domain/scheduler_properties_test.dart`) passes with **no `flutter_tester`** — prove it by pasting the `dart test` output (it says `dart test`, not `flutter test`).
- [ ] `fvm flutter test test/domain/scheduler_properties_test.dart` still passes if you kept a flutter lane, or `fvm flutter test` is explicitly scoped to skip pure files and you document it.
- [ ] `fvm flutter analyze` (or `dart analyze`) on touched files is clean.
- [ ] `pubspec.lock` hash change (if any) is committed; PR body lists why.
- [ ] PR body lists per-tier timing: targeted file wall-clock and a note that full-suite timing is CI's job.

## Not to do

- Do not edit `TEST_STRATEGY.md` (that's TASK-08, capstone).
- Do not wire `scripts/gates/banned_patterns_check.py` / `test_budgets.py` (TASK-03).
- Do not expand `.gates/mutants.json` (TASK-02).
- Do not delete or table-merge tests (TASK-04).
- Do not touch `lib/` unless a one-line seam is required and you label the commit `refactor(testability)` with behavior unchanged.

## Evidence the PR must contain

- The targeted `dart test` + `flutter test` (or scoped) outputs.
- The `analyze` output.
- The mutant re-check if you touched scheduler lanes: `python3 scripts/gates/manual_mutation_runner.py --mutants .gates/mutants.json --test-cmd "fvm flutter test test/domain/scheduler_test.dart test/domain/scheduler_properties_test.dart --no-pub" --force` — or `dart test` variant if you switched.

## If unsure

- Leave `pubspec.yaml` untouched and do header edits only if that keeps CI green — list that choice as a gate change needing approval in the PR body.
- Ask the owner before adding `package:checks` vs plain `package:test`.

---
Source: `docs/test-audit/redesign.md` §1, `baseline.md` §5, audit blind-spots table. Measure before you judge.
