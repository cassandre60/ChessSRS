# TASK-08 — Capstone: TEST_STRATEGY pyramid + budgets + "good test" canon

> **Pick this up last, in a fresh worktree.** `git worktree add ../chesssrs-strategy -b docs/test-strategy-pyramid origin/main` then `fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs`.

## Goal

Make `TEST_STRATEGY.md` the **contract** a weak future agent can follow without guessing: the new **test pyramid with explicit per-layer budgets**, **Fakes-over-mocks**, and **2–3 short "good test" examples lifted from this repo**. This is the capstone — it documents whatever 01–07 actually shipped, not what was proposed.

## Why this is last

`TEST_STRATEGY.md` is a **protected path** (`.gates/protected-paths.txt` → needs `gate-approved`). It should land as one `docs`-only + protected-path PR that closes the brief's Deliverables §3, after 01–07 have decided what exists to document.

## Read before editing

- `TEST_STRATEGY.md` (current structure: matrix, suite organization, verification levels).
- `QUALITY.md` + `SPEC.md` (the invariants the matrix must still transcribe).
- `docs/test-audit/baseline.md`, `audit-report.md`, `redesign.md`, `final.md` — the measured facts this doc must not contradict.
- `GATES.md` + `GATES_PLAN.md` (gate IDs, tiers, and the "no blocking mutation CI without two green runs" rule).
- Whatever 01–07 shipped: check if `dart_test.yaml` exists, if `scripts/gates/banned_patterns_check.py` / `test_budgets.py` are wired, if `fsrs_vectors.json` / `crash_consistency_test.dart` / table-merged importer are present, and whether `test.yml` is tiered.

## What to do

1. **Rewrite or extend §2 "Test Suite Organization (target)"** to state the **actual** pyramid as shipped (not just proposed):
   - **Base — pure unit** (`dart test`, no binding): ~70% of decls, **budget <30s** in CI (parallel). Covers schedulers, coordinator, entities, PGN parse/normalize, schema, adapters, utils. Banned: `pumpAndSettle`, `sleep`, network, `File` real I/O except `sqflite_common_ffi` in persistence.
   - **Middle — flutter unit + widget (critical flows only)**: ~25% of decls, **budget <120s**. Board helpers, feedback states (INV-060/061/062/063), auth, network. Must use explicit `pump`/`pumpAndSettle` with timeout; `sleep` banned.
   - **Top — integration / vertical slice / perf**: ~5% of decls, **budget <60s**. `vertical_slice_gate_test`, `pgn_offload`, `move_latency`, crash-consistency (task 06).
   Total **<180s** test execution (vs today's ~291s). If CI timing differs from the projection, use the measured number and say "measured on CI run <id>".
2. **Add a new §2.1 "What a good test is here"** with **2–3 short examples sourced from this repo** (copy ~10 lines each, citing the file). Suggested picks:
   - A deterministic FSRS or scheduler property (`test/domain/scheduler_properties_test.dart` or `chess_fsrs_scheduler_test.dart` interval preview clamp, INV-026).
   - A `FixedClock` + `review_state` due-filter partition (`test/domain/scheduler_properties_test.dart: dueItems partition` or `scheduler_test.dart: dueItems`).
   - A widget smoke with `findsOneWidget` + SEMAT channel (`test/view/review/review_screen_test.dart` verdict announcement, INV-060) — and why widget tests stop there.
   For each, state what invariant it protects and why a different split (example-only vs property vs widget) would be wrong.
3. **Add a new §2.2 "How the new gates work"** describing:
   - `banned_patterns_check.py` as T1 (or T2 if unwired) — what it bans, its allowlist, its `rg` command.
   - `test_budgets.py` as T2-then-T1 (two green runs before promotion) — how it reads `--reporter json` timing and budgets per tier/per-test.
   - The ratchet on `test_declarations` and `mutant_score` (post-TASK-02), and flaky quarantine `--exclude-tags=quarantine` with expiry.
   Keep this in sync with `GATES.md` — do not invent gate IDs; re-use G03/G05/G06/G08/G10/G12.
4. **Refresh §1 Enforcement Matrix** only where a new test target exists (e.g. FSRS vectors, crash-consistency). Do not remove rows whose tests moved — just update the `Test Target` column to the table-merged file if TASK-04 moved it.
5. **Deliverables hygiene.** When done, refresh `docs/test-audit/final.md` (same metrics as `baseline.md`: test count, CI wall, mutation score on domain, flakiness triage, coverage split if CI `lcov` now exists) and confirm `docs/test-audit/inventory.csv` still matches `find test -name '*_test.dart' | wc -l` + `rg -c`.
6. **Format + local checks:**
   ```bash
   fvm dart format TEST_STRATEGY.md   # or just dart format . — note that Markdown tables are hand-wrapped at page width 100 per CLAUDE.md
   fvm flutter analyze                # docs-only so no-op, but run it if you touched scripts/gates helpers for the doc
   python3 scripts/gates/spec_trace_check.py --spec SPEC.md --tests test --base-spec /tmp/base-spec.md
   ./scripts/gates.sh t1              # after committing (diff-based gates read origin/main...HEAD)
   ```

## Done when

- [ ] `TEST_STRATEGY.md` states the **shipped** pyramid, budgets, and gate wiring (not the pre-ship proposal), with 2–3 repo-sourced "good test" snippets and their INV citations.
- [ ] §2 tree reflects today's `test/` layout (`test/domain` now 9 files after task 01's property file, `test/fixtures/` if task 05 landed, `test/persistence/crash_*` if task 06 landed).
- [ ] `docs/test-audit/final.md` refreshed to post-tasks before/after (test count, CI wall, mutant score, flakiness, coverage) and explicitly says what got worse, what could not be measured, and what remains.
- [ ] PR body contains the **honest final message** required by the original brief (§5): what was measured, what got worse, what remains and why — not a victory lap.
- [ ] `git status` clean, commit message follows Conventional Commits (`docs(test-strategy): ...`), and the commit is on the branch `docs/test-strategy-pyramid`.

## Not to do

- Do not add new gates or `lib/` behavior here — this is a docs capstone.
- Do not bulk-edit `test/**/*_test.dart`.
- Do not claim CI savings that were not measured on a CI run (use `gh run view <id> --json jobs` before/after, or say "projected").

## Evidence

- `./scripts/gates.sh t1` run **after committing** (diff-based gates read the committed range).
- `python3 scripts/gates/spec_trace_check.py --spec SPEC.md --tests test --base-spec <(git show origin/main:SPEC.md)` on this branch if you moved any `INV-0xx`.
- `fvm flutter analyze` on touched docs-adjacent files (if any).

---
Source: the original brief Deliverables §3–5, `docs/test-audit/PLAN.md`, and whatever 01–07 shipped. Measure, then document.
