# Autonomous Improvement Catalogue

> **Status:** Appendix to `AGENTS.md §10` and `TEST_STRATEGY.md`. Subordinate to
> `IMPLEMENTATION_PLAN.md` — the plan owns the work queue, this catalogue
> owns *how* autonomous agents work that queue without creating fake work.
> Every rule here inherits `AGENTS.md §3.1` (machine budget), `§10` (gate
> discipline), and `GATES_PLAN.md` phasing. If this file conflicts with any of
> those, those win. Protected path — gate-change PR required to edit
> (see `.gates/protected-paths.txt`).

---

## 1. Quick Start: When Asked to "Improve the Repo"

If a user prompt says:

- *"Improve the repo"*
- *"Run an autonomous improvement cycle"*
- *"Audit and improve tests"*
- *"Find and fix bugs or performance issues"*

**DO NOT** do cosmetic refactoring, variable renames, or write unchecked
placeholder code.
**DO NOT** run full-suite local tests (`flutter test` without a path filter or
`./verify` — see `AGENTS.md` Hard Rule and `§3.1` test budget).
**DO NOT** invent work that `IMPLEMENTATION_PLAN.md` has not scheduled. The
default answer to a new feature is still **no** (`AGENTS.md §6`).

**Follow this 5-step protocol:**

1. **Pick from the plan, deduplicate via the ledger:** Select the next ready
   task from `IMPLEMENTATION_PLAN.md`. For autonomous quality work (streams
   below), query `docs/AUTONOMOUS_WORK_LEDGER.md` or run:

   ```bash
   python3 scripts/autonomous/ledger.py next --stream <stream_number>
   ```

   If the file's content hash has not changed since its last `COMPLETED`/`SOUND`
   ledger entry, **skip it**. Run `gh pr list` to ensure no open PR is already
   modifying your chosen target — and re-check immediately before pushing.

2. **Prove failure first:** Produce an automated test or mutation that
   **fails on `origin/main`** before any fix. A test that passes on unmodified
   code has zero signal.

3. **Execute in isolation:** Create a dedicated worktree
   (`../chesssrs-<slug>`) branched from `origin/main`. Never run
   destructive git commands outside it; stage files **by name**, never
   `git add -A`.

4. **Deliver via gated PR:** Verify the targeted test passes, run
   `./scripts/gates.sh t1` **after committing** (diff-based gates read
   `origin/main...HEAD` and see nothing while uncommitted), and open a PR
   with fail-to-pass evidence in the body.

5. **Update the ledger:** Append the completed task row to
   `docs/AUTONOMOUS_WORK_LEDGER.md` in your PR. If `git pull --rebase`
   is needed to land the row (another agent appended first), rebase and retry
   — do not overwrite their entry.

---

## 2. Foundational Law: The Fail-to-Pass Invariant

> **No PR, test, or bugfix is accepted unless it is backed by an automated
> test that is mechanically proven to FAIL on `origin/main` before the fix
> is applied.**

- If a test passes on current code, it has **zero signal** as a bugfix or
  new test.
- Every bugfix PR must prove:
  - **Repro on baseline:** Add failing test → **Red** on `origin/main`.
  - **Minimal fix:** Smallest implementation change → **Green**.
  - **Gates clean:** `./scripts/gates.sh t1` with zero G08 findings
    (`python3 scripts/gates/test_weakening_check.py --base origin/main` is
    the direct check).
- Classification and evidence per `GATES.md` Class → evidence and the PR
  template; `G09` is the fail-to-pass gate (reviewer-enforced until CI-wired).

---

## 3. Improvement Streams

Two streams are **active now**. Four streams are **planned** — they are
tracked in `GATES_PLAN.md` rows 9–11 and `IMPLEMENTATION_PLAN.md` Future
Horizon, not executed until their promotion criteria are met. Do not start
a planned stream to "use tokens".

### Stream 1 — Active: Mutation Testing & Test-Gap Elimination (Breaker → Builder)

*Goal: Mechanically find blindspots where logic could break without tests noticing.*

- **Target files (priority order, R0/R1 first per `GATES_PLAN.md §2`):**

  1. `lib/src/domain/graph_aware_review_coordinator.dart` (contagion, exposure credit, sibling coupling)
  2. `lib/src/domain/chess_fsrs_scheduler.dart` (DSR power-law formulas, interval solvers)
  3. `lib/src/domain/review/review_engine.dart` (move validation, auto-traversal, line transitions)
  4. `lib/src/domain/review/review_session.dart` (prefetch buffers, queue partitioning, daily limits)
  5. `lib/src/import/pgn_exporter.dart` (serialization, move comments, orientation tags)
  6. `lib/src/persistence/sqlite_study_repository.dart` (batching, mmap, transactions)

- **Execution command:**

  ```bash
  python3 scripts/autonomous/mutation_engine.py \
    --source lib/src/domain/<target_file>.dart \
    --test-cmd "fvm flutter test test/domain/<matching_test>.dart" \
    --max-mutants 20 \
    --output-issue docs/tasks/mutant_issue.md
  ```

  > **Limitation (read before trusting output):** The engine is regex-based,
  > not AST-based. It can mutate string literals, comments, and the wrong
  > `&&`, and it treats uncompilable mutants as killed only if they fail the
  > test command. Every surviving mutant must be triaged by a human — many
  > are equivalent mutants or noise. See `scripts/autonomous/mutation_engine.py`
  > header. Promotion to blocking CI is gated on `GATES_PLAN.md` row 9
  > (two green runs without false positives).

- **Action:** A triaged surviving mutant is an objective test gap. Write a
  test that fails on the mutant and passes on clean code, citing the
  relevant `SPEC.md` invariant (`// SPEC INV-xxx.`).

---

### Stream 2 — Active: Adversarial Test Suite Audit (Hardening Existing Tests)

*Goal: Eliminate vacuous, circular, or flaky tests. Complements G05/G08.*

When reviewing or auditing existing test files (`test/review/`,
`test/domain/`, `test/persistence/`, `test/view/`), answer the
**3 adversarial questions**:

1. **Can it actually fail? (Vacuity check):**
   Does this test assert real state changes, or trivialities?
   *Example defect:* Finding F2 in `docs/spec-conformance-audit-2026-10-16.md`
   (`review_service_test.dart` claimed trees are not rewritten but never
   inspected the tree table) — fix by snapshotting the table or counting
   writes.

2. **Is it asserting behavior or implementation? (Over-mocking check):**
   Does the test exercise real domain outputs, or only that a mock returned
   what the test told it to?
   *Fix:* Replace mocks with in-memory domain entities
   (`makeTestProviderScope`, fake clocks, in-memory SQLite).

3. **Is it a timing bomb? (Flakiness check):**
   Does the test use fixed wall-clock sleeps
   (`Future.delayed(Duration(milliseconds: 80))`)? Under CPU contention this
   flakes in wide runs (`AGENTS.md` lesson 2026-09-28).
   *Fix:* Poll on a condition or use `pumpAndSettle`; never add a fixed sleep
   to "stabilize" a test.

Mechanical help: `scripts/audit_2026-10/smell_tests.py` screens for these
patterns (298 flagged of 1855 on 2026-10-17), but every flag needs human
judgment — a flagged assertion is not automatically vacuous.

---

### Stream 3 — Planned: Property-Based Fuzzing & Model Checking

*Goal: Verify invariant stability across thousands of randomized transitions.*
*Promotion criteria: `GATES_PLAN.md` row 10 (nightly harness proven, not
blocking PRs).*

- **Target areas:**
  - **PGN round-tripping:** Generate randomized PGN trees with RAVs, comments,
    shapes (`[%cal ...]`, `[%csl ...]`), and transpositions. The oracle is
    structural equivalence after `import → export → import`, not string
    identity — whitespace and annotation normalization make
    `export(import(text)) == text` false in the literal sense.
  - **FSRS monotonicity:** Random ratings and intervals; prove higher stability
    does not shorten intervals, difficulty stays in `[1, 10]`, and
    retrievability in `[0, 1]`.
  - **Queue state machine fuzzing:** Random user actions under both
    `ReviewContinuity` modes; prove zero deadlocks, zero negative due counts,
    zero uncaught exceptions.

No harness is wired yet. Do not claim this stream is "proven" until the
harness exists and is run nightly.

---

### Stream 4 — Planned: SQLite Migration & Data Preservation Archeology

*Goal: Prove data durability across all 18 schema upgrades.*
*Promotion criteria: `GATES_PLAN.md` row 10 (crash-consistency harness).*

- **Historical migration fixtures:** Audit finding F3 — migrations for schemas
  v6–v11 and v14–v15 lack on-disk upgrade tests. Create fixture databases
  populated with pre-migration data and assert forward migration to v18 with
  zero lost studies, chapters, or reviews.
- **Orphan row elimination:** Finding F5 — 117 orphaned `srs_review_state`
  rows with no matching `srs_decision`. Add cascade/repair logic and a
  regression test pinning the count at zero.

---

### Stream 5 — Planned: Targeted Performance & Startup Optimization

*Goal: Eliminate latency bottlenecks on the critical review path.*
*Promotion criteria: `GATES_PLAN.md` row 11 (pinned runner + budgets).*
*Authoritative guides:* `docs/performance-handoff.md` and
`docs/tasks/PERF-FIX-24-real-library-measurement.md`.

- **Known context:** Against a real 31k-decision library,
  `getAllReviewStates()` was measured at ~13 ms of Dart object construction
  and merging — but the benchmark was unreliable (same call measured 16 ms,
  29 ms, and 36 ms across harnesses on unchanged code; `AGENTS.md` lesson
  2026-10-13).
- **Rule:** Never optimize against a noisy benchmark. Fix the instrument
  first (`PERF-FIX-24`), measure before and after across at least 3 runs on
  a real database, report spread not just median, and pin improvements with
  benchmark regression tests. No PR in this stream without before/after
  numbers on the pinned harness (`GATES.md` perf class).

---

### Stream 6 — Planned: Accessibility (A11y) & Interaction Verification

*Goal: Ensure review and settings surfaces meet WCAG and design specs.*
*Promotion criteria: Next design pass; complements `design/docs/`.*

- **Target areas:**
  - **Screen reader announcements:** Verify `_VerdictLiveRegion` announces
    moves post-guess without lag or double-announcement.
  - **Hit targets:** Verify all interactive controls satisfy the 44 px minimum
    across narrow viewports (down to 320 px).
  - **Keyboard navigation:** Verify desktop shortcuts (Enter, NumpadEnter,
    ArrowRight) dispatch accurately across focus states.

Stream 2 already covers hit-target regressions (INV-062); this stream is the
systematic pass, not a duplicate.

---

## 4. Execution Workflow for Agents

All steps inherit `AGENTS.md §3` (Development Loop) and `§3.1` (test budget).
This section adds autonomous-specific detail — it does not replace those rules.

```bash
# 1. Create task-isolated worktree (branch from origin/main, not local main)
git remote set-url origin https://github.com/cassandre60/ChessSRS.git
git fetch origin main
git worktree add ../chesssrs-<slug> -b <type>/<slug> origin/main
cd ../chesssrs-<slug>

# 2. Codegen baseline (required per-worktree; generated files are gitignored)
fvm flutter pub get
# Note: with unresolved includes the formatter silently falls back to width 80
# and rewrites hundreds of lines — pub get must succeed first (AGENTS.md §3).
fvm dart run build_runner build --delete-conflicting-outputs
fvm dart format lib/l10n/  # discard l10n churn if present; do not commit it

# 3. Prove failure on origin/main (Commit A) — targeted, not wide
# Write failing test -> confirm it fails on baseline (one test, not the file):
fvm flutter test test/<path>/<test_file>.dart --plain-name '<test_name>'

# 4. Implement minimal fix (Commit B)
# Run targeted test -> confirm it passes:
fvm flutter test test/<path>/<test_file>.dart --plain-name '<test_name>'

# 5. Gate & format checks — after committing (diff-based gates read HEAD)
fvm dart format lib test
# Analyze only touched files, after the last edit (AGENTS.md §3.1):
fvm flutter analyze <touched_files>
# Full T1 gate (same as CI's fast lane):
./scripts/gates.sh t1
# Or the direct tripwire check:
python3 scripts/gates/test_weakening_check.py --base origin/main

# 6. Push & create PR (stage by name, never git add -A)
git status  # confirm only intended files are staged
git push -u origin <branch>
gh pr create -R cassandre60/ChessSRS --title "<type>(<area>): <summary>" --body "<evidence>"
```

Workflow notes:

- Iterate with `--plain-name '<test name>'` (one test), one full-file run at
  the end. The fail-on-old-code check (stash + rerun) counts as the second
  run — then stop. Neighbouring files and `./verify` are CI's job.
- One `flutter analyze` per task, on the files touched, after the last edit.
- `fvm flutter run -d linux` for runtime validation is bounded: launch,
  exercise, quit. Never run a release build locally (`AGENTS.md §4`).

---

## 5. Supporting Roles (Optional: Breaker → Builder → Sentinel)

For teams running multiple agents concurrently, the ledger and worktrees act
as the message bus. Roles are optional — a single agent may do all three —
but the separation helps avoid fake work:

- **Breaker (Red Team):** Never modifies `lib/`. Generates surviving mutants,
  fuzz failures, or smell flags. Output: GitHub Issue with a copy-pasteable
  failing test and a cited `SPEC.md` invariant.
- **Builder (Blue Team):** Works in an isolated worktree, proves red on
  `origin/main`, writes the minimal fix, verifies `gates.sh t1`, opens the PR.
- **Sentinel (Auditor):** Read-only diff + CI inspection. Ensures no
  protected paths were touched, no tests were weakened (G08), no fake
  abstractions were added.

All three respect worktree isolation, stage-by-name, and the machine budget.
