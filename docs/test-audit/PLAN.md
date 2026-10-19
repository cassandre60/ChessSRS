# Orchestrator plan — ChessSRS test-audit follow-on work

> **Status: Retired.** This document's 8 task briefs (`docs/tasks/TEST-0*`) have been removed. They duplicated `docs/AUTONOMOUS_IMPROVEMENT_CATALOG.md` and `docs/AUTONOMOUS_WORK_LEDGER.md`. For dispatch, use `python3 scripts/autonomous/ledger.py next --stream <N>` and `docs/AUTONOMOUS_IMPROVEMENT_CATALOG.md` §4. Evidence files `docs/test-audit/baseline.md` / `audit-report.md` / `redesign.md` / `final.md` / `inventory.csv` remain as read-only input for Stream 1. See Cleanup section at end.

Branch `test-audit` (base `a9fbfe0fb`). The audit itself is finished; what remains is **wiring** the redesign. I am the orchestrator: I do not implement the tasks below myself. Each task is a self-contained brief an agent picks up in its own worktree, lands in one small PR, and verifies with targeted tests + `flutter analyze` (+ `gates.sh t1` where it touches gates). CI (`Tests`) is the full-suite authority — no agent runs `./verify` or the whole suite locally (AGENTS.md §3.1).

## What is already landed on this branch

| Artifact | File | State |
|---|---|---|
| Baseline scoreboard | `docs/test-audit/baseline.md` | landed 7526242a6 |
| Inventory (182 rows) | `docs/test-audit/inventory.csv` | landed 7526242a6 |
| Audit (method, buckets, Top-10 blind spots) | `docs/test-audit/audit-report.md` | landed 94b2a0efb |
| Redesign lever ranking + seam map | `docs/test-audit/redesign.md` | landed 8f8e2bcc1 |
| Before/after | `docs/test-audit/final.md` | landed 8f8e2bcc1 |
| Property tests INV-024/025/026/030 | `test/domain/scheduler_properties_test.dart` | landed f60eb4619 |

Tracked so far: 4 commits, +1085 lines, 6 files on `test-audit`. Mutation on `scheduler.dart` is 6/6 killed; property batch is co-run-verified.

## What is NOT done (and why it was deferred)

The redesign lists 9 levers. #1 (`dart test` lane) and #8 (the two new gates) need `pubspec.yaml` / `TEST_STRATEGY.md` / `.gates/*` / `scripts/gates/*` / `.github/**` — all **protected paths** (`.gates/protected-paths.txt`). Landing them requires a separate `gate-approved` PR. The other levers need fixtures or a fault harness and would have bloated this PR. So they were recorded with method + seam map and left for agents.

## Dispatch map

| # | Brief | Cost | ROI | Order | Protected? |
|---|---|---|---|---|---|
| 01 | Pure `dart test` lane | S | #1 CI saved ≈100s | first | **yes** (`pubspec.yaml`, optionally `dart_test.yaml`) |
| 02 | Expanded mutation corpus (FSRS, coordinator, import, persistence) | S | #2 signal | first (parallel with 01) | **yes** (`.gates/mutants.json`) |
| 03 | Banned-patterns + budgets gates | S | flake prevention + budget enforcement | after 01 | **yes** (`scripts/gates/*`, `GATES.md`, `GATES_PLAN.md`) |
| 04 | Table-driven merges (PGN importer, design tokens) | M | readability | after 02 | no |
| 05 | Differential FSRS vectors | M | high signal (FSRS oracle) | after 02 | no (fixture in `test/fixtures/`) |
| 06 | Crash-consistency fault injection | M | **T0 critical** | after 02 | no |
| 07 | CI tiering / tags / caching / conditional build_runner | S | 30–60s | after 01+03 | **yes** (`.github/workflows/test.yml`, `.gates/*`) |
| 08 | TEST_STRATEGY pyramid + budgets + "good test" examples | S | contracts for future agents | after 01–07 (capstone) | **yes** (`TEST_STRATEGY.md`) |

Dependency: 04/05/06 need 02's expanded mutants as their oracle before they can claim "nothing lost" on a merge. 07 needs 01's `dart_test.yaml` tags. 08 is the capstone that documents whatever actually shipped.

Rules every agent follows (from the original brief):

- **Measure before you judge.** State the measurement command and its output. Never invent numbers. If a tool cannot run, say so and fall back to a labelled manual method.
- **Never reduce real bug-catching power.** Deletions only if (a) redundant — removing it changes no mutation outcome and no unique coverage, (b) dead/cut code, or (c) asserts nothing meaningful. Record the evidence in the commit message. No merge that drops signal.
- **Don't weaken any gate** without listing it under "Gate changes needing my approval" in the PR body.
- **Production seams only** (`Clock`/`Random`/`Database` injection, pure-function extraction) in separate `refactor(testability)` commits, behavior unchanged, suite green after each.
- One logical change per commit; Conventional Commits; suite green after each; stage by name; branch `<type>/<area>-<slug>` off `origin/main` in a fresh worktree (AGENTS.md isolation). Run `dart format` and `fvm flutter analyze` on touched files; the full suite is CI's job.

## How to pick up a task

```bash
git remote set-url origin https://github.com/cassandre60/ChessSRS.git
git worktree add ../chesssrs-<slug> -b <type>/<area>-<slug> origin/main
cd ../chesssrs-<slug>
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
# read the brief top-to-bottom, then execute it exactly
```

Each brief states its **entry command** (the targeted test), its **done criteria**, and its **not-to-do** list. If you are unsure about a deletion, stop and list it under "Decisions needing my approval" rather than landing it.

## Deliverables still required (from the original task)

1. `baseline.md` + `final.md` — done; `final.md` will be refreshed by the last agent to reflect whatever actually shipped.
2. `audit-report.md` + `inventory.csv` — done.
3. **Updated `TEST_STRATEGY.md`** — task 08 (protected, capstone).
4. **"Decisions needing my approval"** — aggregated in this file §Decisions and per-PR. Nothing above weakens a gate without owner approval.
5. **Final honest summary** — task 08 refreshes `final.md` and the PR body with what was measured, what got worse, and what remains.

## Current stack facts an agent must know

- Flutter 3.47.3 / Dart 3.13.5 via `fvm`. `build_runner` is ~64s of fixed overhead (CI run 39118936674). Do not attempt a local `flutter test` over 183 files — use `fvm flutter test <file> --plain-name '<name>'` per AGENTS.md §3.1.
- `lib/src/domain/**` is pure Dart (zero `package:flutter` imports — verified with `rg`). `Clock` + seeded `Random` seams already exist. `pgn_offload.dart` (2 flutter lines) and `sqlite_study_repository.dart` (1 flutter_riverpod line) are the only impure seams — see `redesign.md` §1.
- `test/` is 183 files / 57.5k lines / 1888 decls after this branch. `pubspec.yaml` currently has `fake_async` but no `checks`/`test` extra dep. `GATES.md` lists G01–G12; `GATES_PLAN.md` §4 is the gap table.
- Protected paths: `SPEC.md`, `GATES.md`, `GATES_PLAN.md`, `QUALITY.md`, `TEST_STRATEGY.md`, `.gates/*`, `redteam/*`, `scripts/gates/*`, `.github/*`, `AGENTS.md`, `CLAUDE.md`, `analysis_options.yaml`, `pubspec.yaml`, `test/fixtures/*`. Any PR touching one needs `gate-approved` label from the owner and must be a separate gate-change/spec-change PR.

## Decisions needing my approval (aggregated)

- Any gate addition or loosening (G07: protected-path label).
- Any test deletion whose mutation/coverage delta is inconclusive.
- Any `refactor(testability)` touching `lib/` beyond the two documented seams.
- Tightening the `test_declarations` ratchet (1886→1888) — trivial but protected.
- Whether to cache `.dart_tool/build/` vs. always run `build_runner` in CI (task 07 must choose and justify).

## After all tasks

The last agent to land (expected: task 08) does three things:

1. Refresh `docs/test-audit/final.md` — same metrics as `baseline.md` (test count, CI wall, mutation score on domain, flakiness triage, coverage split if CI `lcov` exists).
2. Confirm `docs/test-audit/inventory.csv` still matches `find test -name '*_test.dart' | wc -l` and `rg -c`.
3. Post the honest final message required by the brief: what was measured, what got worse, what remains and why.

---

## Cleanup (2026-10-19): duplicate queue retired

On 2026-10-19 `docs/tasks/TEST-01-dart-lane.md` … `TEST-08-strategy-capstone.md` were removed. Reason: they re-invented a queue that already exists in `docs/AUTONOMOUS_IMPROVEMENT_CATALOG.md` (catalog, Streams 1–2 active, 3–6 planned) + `docs/AUTONOMOUS_WORK_LEDGER.md` (content-hash dedup, `ledger.py`). The audit data stays; the dispatch layer does not.

For any blind spot listed in `docs/test-audit/audit-report.md` Top-10, file it as a Stream 1 issue against `LEDGER.md` instead of a `TEST-0*` task. Streams 3–6 are **planned** (`GATES_PLAN.md` rows 9–11) — do not start them to use tokens (see catalog §1).

Orchestrator: Claude Opus 5.5 (OpenCode). Measure, then judge.
