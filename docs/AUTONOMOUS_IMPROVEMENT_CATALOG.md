# Autonomous Improvement Catalogue & Agent Operating Manual
*The Master Guide for Autonomous, Non-Degenerative Repository Evolution*

---

## 1. Quick Start: When Asked to "Improve the Repo"

If a user prompt says:
- *"Improve the repo"*
- *"Run an autonomous improvement cycle"*
- *"Audit and improve tests"*
- *"Find and fix bugs or performance issues"*

**DO NOT** do cosmetic refactoring, variable renames, or write unchecked placeholder code.
**DO NOT** run full-suite local tests (`flutter test` across the repo or `./verify` — see `AGENTS.md` Hard Rule).

**Follow this 5-step protocol:**
1. **Query the Work Ledger (Deduplication):** Inspect `docs/AUTONOMOUS_WORK_LEDGER.md` or run:
   ```bash
   python3 scripts/autonomous/ledger.py next --stream <stream_number>
   ```
   If a file has already been audited at its current Git SHA, **skip it**.
   Check `gh pr list` to ensure no open PR is already modifying your chosen target.
2. **Prove Failure First:** Produce an automated test or mutation that fails on `origin/main`.
3. **Execute in Isolation:** Create a dedicated worktree (`../chesssrs-<task>`) branched from `origin/main`.
4. **Deliver via Gated PR:** Verify targeted test passes, run `./scripts/gates.sh t1` after commit, and open a PR with evidence.
5. **Update the Ledger:** Append the completed task row to `docs/AUTONOMOUS_WORK_LEDGER.md` in your PR.

---

## 2. Foundational Law: The "Fail-to-Pass" Invariant

> **No PR, test, or bugfix is accepted unless it is backed by an automated test that is mechanically proven to FAIL on `origin/main` before the fix is applied.**

- If a test passes on current code, it has **zero signal** as a bugfix or new test.
- Every Issue/PR must prove:
  - **Commit A (or Repro):** Add failing test $\rightarrow$ **Red** on baseline.
  - **Commit B:** Minimal implementation fix $\rightarrow$ **Green**.
  - **Gates Check:** `./scripts/gates.sh t1` clean (zero G08 test-weakening findings).

---

## 3. The 6 Perpetual Improvement Streams

### Stream 1: Mutation Testing & Test-Gap Elimination (Breaker $\rightarrow$ Builder)
*Goal: Mechanically find and kill blindspots in the test suite where logic could break without tests noticing.*

- **Target Files (Priority Order):**
  1. `lib/src/domain/graph_aware_review_coordinator.dart` (contagion, exposure credit, sibling coupling)
  2. `lib/src/domain/chess_fsrs_scheduler.dart` (DSR power-law formulas, interval solvers)
  3. `lib/src/domain/review/review_engine.dart` (move validation, auto-traversal, line transitions)
  4. `lib/src/domain/review/review_session.dart` (prefetch buffers, queue partitioning, daily limits)
  5. `lib/src/import/pgn_exporter.dart` (serialization, move comments, orientation tags)
  6. `lib/src/persistence/sqlite_study_repository.dart` (batching, mmap, transactions)
- **Execution Command:**
  ```bash
  python3 scripts/autonomous/mutation_engine.py \
    --source lib/src/domain/<target_file>.dart \
    --test-cmd "fvm flutter test test/domain/<matching_test>.dart" \
    --max-mutants 20 \
    --output-issue docs/tasks/mutant_issue.md
  ```
- **Action:** Any surviving mutant is an objective test gap. Write a test that fails on the mutant and passes on clean code.

---

### Stream 2: Adversarial Test Suite Audit (Hardening Existing Tests)
*Goal: Eliminate vacuous, circular, or flaky tests across the existing suite.*

When reviewing or auditing existing test files (`test/review/`, `test/domain/`, `test/persistence/`, `test/view/`), answer the **3 Adversarial Questions**:
1. **Can it actually fail? (The Vacuity Check):**
   - Does this test assert real state changes, or does it assert trivialities?
   - *Example defect:* Finding F2 in `docs/spec-conformance-audit-2026-10-16.md` (`review_service_test.dart` claimed to test that trees are not rewritten, but never inspected the tree table).
   - *Fix:* Add assertions that verify database write counts or snapshot unchanged tables.
2. **Is it asserting implementation or behavior? (The Over-Mocking Check):**
   - Does the test assert real domain outputs, or only that a mocked method returned what the test told it to return?
   - *Fix:* Replace mocks with pure in-memory domain entities (`makeTestProviderScope`, fake clocks, pure SQLite in-memory).
3. **Is it a timing bomb? (The Flakiness Check):**
   - Does the test use fixed wall-clock sleeps (`Future.delayed(Duration(milliseconds: 80))`)? Under CPU contention, this causes CI flakes.
   - *Fix:* Replace fixed sleeps with condition-polling loops (`pumpAndSettle`, polling futures until state changes).

---

### Stream 3: Property-Based Fuzzing & Model Checking
*Goal: Mathematically verify invariant stability across 10,000+ randomized state transitions.*

- **Target Areas:**
  - **PGN Parsing & Export Round-tripping:** Generate randomized, deeply nested PGN trees with diverse RAVs, comments, board shapes (`[%cal ...]`, `[%csl ...]`), and transpositions. Prove that `exportStudyPgn(importPgn(text)) == text` (idempotence).
  - **FSRS Monotonicity:** Generate random ratings ($R \in \{\text{good}, \text{again}\}$) and intervals ($t \in [1, 365]$). Prove that higher stability $S$ strictly increases intervals, difficulty $D$ remains bounded $[1, 10]$, and retrievability $R(t) \in [0, 1]$.
  - **Queue State Machine Fuzzing:** Simulate random user actions (answers, lapses, skips, restarts) under both `ReviewContinuity.dueOnly` and `ReviewContinuity.fullLine`. Prove zero deadlocks, zero negative due counts, and zero uncaught exceptions.

---

### Stream 4: SQLite Migration & Data Preservation Archeology
*Goal: Prove 100% data durability across all 18 SQLite schema upgrades.*

- **Target Areas:**
  - **Historical Migration Fixtures:** As noted in audit Finding F3, migrations for schemas v6–v11 and v14–v15 lack on-disk upgrade tests. Create fixture databases populated with pre-migration data and assert that forward migration to v18 succeeds with zero lost studies, chapters, or reviews.
  - **Orphan Row Elimination:** Finding F5 found 117 orphaned `srs_review_state` rows with no matching `srs_decision`. Build cascade cleanup triggers or repair logic so deletions and imports never leave ghost records.

---

### Stream 5: Targeted Performance & Startup Optimization
*Goal: Eliminate latency bottlenecks on the critical review and session path.*

- **Authoritative Guide:** `docs/performance-handoff.md` and `docs/tasks/PERF-FIX-24-real-library-measurement.md`.
- **Known Bottleneck:** Against a real 31k-decision library, `getAllReviewStates()` consumes ~13 ms in Dart object construction and merging.
- **Rule:** Never optimize against a noisy benchmark. Measure before and after across at least 3 runs on a real database. Pin improvements with benchmark regression tests.

---

### Stream 6: Accessibility (A11y) & Interaction Verification
*Goal: Ensure the review and settings surfaces meet WCAG accessibility and design specs.*

- **Target Areas:**
  - **Screen Reader Announcements:** Verify `_VerdictLiveRegion` correctly announces moves post-guess for screen-reader users without lagging or double-announcing.
  - **Hit Targets:** Verify all interactive buttons, pills, and drawer tiles satisfy the 44px minimum touch target requirement across narrow viewports (down to 320px).
  - **Keyboard Navigation:** Verify desktop shortcuts (Enter, NumpadEnter, ArrowRight) dispatch accurately across focus states.

---

## 4. Execution Workflow for Agents

```bash
# 1. Create task-isolated worktree
git worktree add ../chesssrs-<slug> -b <type>/<slug> origin/main
cd ../chesssrs-<slug>

# 2. Codegen baseline (required per-worktree)
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs

# 3. Prove failure on origin/main (Commit A)
# Write failing test -> confirm it fails:
fvm flutter test test/<path>/<test_file>.dart --plain-name '<test_name>'

# 4. Implement minimal fix (Commit B)
# Run targeted test -> confirm it passes:
fvm flutter test test/<path>/<test_file>.dart --plain-name '<test_name>'

# 5. Gate & Format Check (Zero weakening allowed)
fvm dart format lib test
fvm flutter analyze <touched_files>
python3 scripts/gates/test_weakening_check.py --base origin/main

# 6. Push & Create PR
git push -u origin <branch>
gh pr create -R cassandre60/ChessSRS --title "<type>(<area>): <summary>" --body "<details>"
```
