# TASK-02 — Expanded mutation corpus (FSRS, coordinator, import, persistence)

> **Pick this up in a fresh worktree.** `git worktree add ../chesssrs-mutants -b feat/test-mutants origin/main` then `fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs`.

## Goal

Expand `.gates/mutants.json` from **6 mutants on `scheduler.dart`** to a corpus that covers the **Top-10 blind spots** where today no mutant exists: FSRS kernel, graph coordinator, PGN import, canonical re-key, transposition grader, due/fresh partition, scope aggregation, socket sri regression, and wall-clock guards. Keep 100% killed on the new corpus.

## Why

Mutation is per GATES.md the only quality gate (G06, T2). Today it only covers `SimpleScheduler`/`EaseScalingScheduler` caps, off-by-one, and `dueItems` negation. The audit tags 8 more modules with surviving mutants — a missing guard there is silent today. Expanding the corpus is high-signal, low-cost, and unblocks tasks 04/05/06/08 which need an oracle to say "nothing lost" on their merges.

## Read before editing

- `docs/test-audit/audit-report.md` §Top 10 blind spots (ranked T0/T1 risk).
- `docs/test-audit/redesign.md` §5/6 (differential/crash proposals that depend on this).
- `.gates/mutants.json` (current 6, format: `{file, find, replace, occurrence, note}`) and `scripts/gates/manual_mutation_runner.py` (usage: `--test-cmd` + `--force` on dirty tree).
- `GATES.md` (G06 hand-picked mutants, G08 tripwire) + `.gates/protected-paths.txt` (`.gates/*` is protected — this PR needs `gate-approved`).

## What to do (small, targeted — one file per commit if large)

1. **Pick 2–3 mutants per blind-spot module.** Keep them **hand-picked** (GATES_PLAN.md: "hand-picked mutants, local T2") — no auto mutator. Prefer: flipped `<`/`<=`/`>` boundaries, dropped `clamp`/`where`, removed `if (stability > threshold)` guard, negated `if (!scope.matches)`, stripped `?sri=` query param, bare `DateTime.now()` in `domain/*`. Each mutant must be a small bug: flip, constant change, line drop, condition negation.
2. **Name each mutant's oracle.** In `note`, cite the invariant (`SPEC INV-0xx`) and the test that kills it (`'killed by ...'`). If no existing test kills it, **add the test in the same PR** (that's the point) and keep the mutant.
3. **Prefer `.gates/mutants.json` shape compatible with `manual_mutation_runner.py`.** If you add equivalent mutants (cannot change behavior, e.g. `x<0` → `x<=0` inside `abs`), mark them `{"equivalent": true, "note": "why"}` — they are expected to survive and do not fail the run (listed for review). Keep equivalents rare.
4. **Run the runner locally — targeted.** Use `fvm flutter test <file>` matching each module (`scheduler*`, `chess_fsrs_scheduler*`, `graph_aware_*`, `pgn_importer*`, `position_knowledge_state*`, `review_session*` / `review_transposition*`, `socket*`). Never run the whole suite locally (AGENTS.md §3.1). Example:
   ```bash
   python3 scripts/gates/manual_mutation_runner.py \
     --mutants .gates/mutants.json \
     --test-cmd "fvm flutter test test/domain/chess_fsrs_scheduler_test.dart --no-pub" --force
   python3 scripts/gates/manual_mutation_runner.py \
     --mutants .gates/mutants.json \
     --test-cmd "fvm flutter test test/import/pgn_importer_test.dart --no-pub" --force
   ```
   State the command + killed/survived counts in the commit/PR. If a mutant survives, add the killing test and re-run — do not weaken the mutant.
5. **Keep G06's test command aligned.** `scripts/gates.sh t2` currently runs `fvm flutter test test/domain/scheduler_test.dart`. If TASK-01 lands a `dart test` lane, update the `G06` command to `dart test test/domain/...` or `fvm flutter test test/domain/... test/import/...` so the new corpus is covered. If you change `gates.sh`, that is a protected path — say so in the PR body.
6. **Format + analyze touched files only:**
   ```bash
   fvm dart format test/domain/chess_fsrs_scheduler_test.dart .gates/mutants.json
   fvm flutter analyze test/domain/chess_fsrs_scheduler_test.dart
   ```

## Coverage target (order by blind-spot rank)

| Rank | Module / SPEC | Suggested mutants (examples) |
|---|---|---|
| T0 #1 | `persistence` / INV-001/002/004 | fault-injection wrapper needs TASK-06; for this task, add non-crash mutants: drop `canonicalStateId` write, swap `where` clause, remove `ON DELETE CASCADE` guard |
| T1 #2 | `lib/src/domain/chess_fsrs_scheduler.dart` / INV-025/026 | `Retention`→`/api` miss, `MaximumInterval` hand-off, `schedule ==` equality (cf. INV-026), remove `stability > threshold` guard |
| T1 #3 | `graph_aware_review_coordinator.dart` / INV-027/028/029 | drop `oncePerDay` check, `confusableSiblingsOnly` negated, `stability > minStabilityDays` removed |
| T0 #4 | `lib/src/import/pgn_importer.dart` / INV-010 — variation + NAG | flatten third-level variation (`...addAll(children)`), drop `comment` on re-import (`reExport` stripped), `RavVariants` → single child |
| T0 #5 | `canonical_rekey_migration.dart` / INV-015/017 | recompute with old first-move key (regression), `opening_name_repair` erases genuine opening |
| T1 #6 | `lib/src/domain/review/review_session.dart` / INV-065 — transposition grader | accept when `Transposed moves: Off`, reject even when in scope |
| T1 #7 | fresh-vs-due / INV-068 — `startSession` builder | `maxNewPerSession == null ? all : all.sublist(0,N)` removed → all fresh included |
| T1 #8 | `ReviewScope` / INV-030 + INV-067 | `ReviewScope.opening(name)` normalization dropped, `white()`/`black()` orientation aggregation removed, `isActive` filter dropped |
| T1 #9 | `lib/src/network/socket.dart` / INV-064 | strip `?sri=` query param (fake must assert URL) |
| T2 #10 | wall-clock guards / INV-024/041 + G03 | `DateTime.now()` in `domain/*` outside allowlist, bare `Future.delayed` in `test/domain/` |

You do not need all 10 in one PR — **6 to 10 new mutants that all kill green is a successful PR.** Any survivors must come with their killing test; if you cannot write one that fails on base and passes here (G09), mark it `equivalent` with why.

## Done when

- [ ] `.gates/mutants.json` has 12–20 non-equivalent mutants (6 old + 6–14 new) plus at most 1–2 declared equivalents, all green via `manual_mutation_runner.py` for their module's targeted test command.
- [ ] Each new mutant's `note` cites its `INV-0xx` and the killing test name.
- [ ] `GATES.md` G06 blind-spot line updated if the corpus grew beyond "six scheduler boundaries only".
- [ ] `TEST_STRATEGY.md` not touched here (TASK-08 capstone) unless the audit's G06 table row is the only change — otherwise leave it.
- [ ] Commit message lists the runner command(s) and the before/after killed counts.

## Not to do

- Do not add a blocking mutation job in `.github/workflows/` (TASK-07 owns CI). This stays local-opt-in (`gates.sh t2`), per GATES_PLAN.md #9.
- Do not bulk-reformat `test/**/*_test.dart`.
- Do not change `lib/` behavior — mutants live in `.gates/mutants.json` and tests live in `test/`.

## Evidence

- `python3 scripts/gates/manual_mutation_runner.py --mutants .gates/mutants.json --test-cmd "<targeted cmd>" --force` output (killed/survived/invalid) before and after.
- `fvm flutter analyze` on touched files.

---
Source: `docs/test-audit/audit-report.md` §§1–10, `redesign.md` §§2/5/6, `GATES.md` G06. Measure before you judge.
