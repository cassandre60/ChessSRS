# Recursive Autonomous Repository Improvement Strategy
*Leveraging High Token Capacity for Verified, Non-Degenerative Codebase Evolution*

---

## 0. Original User Prompt (Reference)

> "I have (near) infinite tokens, I need a plan to recursvly imporve this repo via PRs and issues (no automatic merge): my pb is that if i ask an gent for a task (even complcaited one like audit and debug this repo) it finishes within 1 hour max and i have all my tokens unspent.
> How do i leaverage my tokens so that the app and the code and the repo imporve but wihtout falling in the trap of the agents createing fake tests and fake goals that do nothing beside waste tokens?
> Think"

---

## 1. Diagnosis: The 1-Hour Stall & The "Fake Work" Trap

### Why Agents Stop in Under 1 Hour
1. **Local Convergence Bias:** LLMs are fine-tuned to seek completion. When given an open-ended goal ("audit and improve"), an agent runs static analysis, runs a test file, notes that everything passes, writes a markdown summary, and declares victory.
2. **Lack of Objective Counter-Evidence:** Without a mechanical signal saying *"this is still broken"*, the model's reasoning loop terminates.
3. **Execution Horizon Ceiling:** A single agent session lacks the structural feedback loops needed to spin up continuous work.

### The "Fake Work" Degeneration
When prompted blindly with *"keep improving"* without strict gates, agents predictably degenerate into:
- **Tautological / Checkbox Tests:** Writing tests that assert trivialities (`expect(state.isActive, isTrue)`) or mock the subject under test until the test passes vacuously regardless of real implementation bugs (e.g. Findings F2, F3, F4 in `docs/spec-conformance-audit-2026-10-16.md`).
- **Cosmetic Churn:** Renaming variables, rearranging imports, or splitting functions into tiny unhelpful wrappers that create merge friction without improving reliability.
- **Scope Creep / Spec Hallucination:** Inventing unrequested features (gamification, cloud sync) that violate foundational product specs (`MVP.md`, `PRODUCT.md`, `QUALITY.md`).
- **Machine Overheating:** Running wide local test suites (`flutter test` across the repo) in violation of `AGENTS.md` rules, pinning CPU cores and stalling the developer's workstation.

---

## 2. Foundational Law: The "Fail-to-Pass" Invariant

To ensure every token spent produces durable, high-integrity code:

> **No PR, test, or bugfix is accepted unless it is backed by an automated test that is mechanically proven to FAIL on `origin/main` before the fix is applied.**

- If a test passes on current code, it has **zero signal** as a bugfix or new test.
- Every Issue must include a reproducible failing command.
- Every PR must demonstrate:
  1. Commit A: Add failing test $\rightarrow$ **Red** (fails on baseline).
  2. Commit B: Minimal implementation fix $\rightarrow$ **Green** (passes).
  3. Tripwire gate verification: `./scripts/gates.sh t1` clean, zero test weakening (G08).

---

## 3. High-Token, Zero-Bullshit Verification Engines

Instead of asking agents for subjective code reviews, channel large token budgets into computationally and logically exhaustive verification engines:

### A. Autonomous Mutation Testing (Killing the Mutants)
- **Concept:** Take core domain and engine files (`ChessFsrsScheduler`, `GraphAwareReviewCoordinator`, `ReviewEngine`, `PgnParser`, `ReviewSession`, `StudyRepository`).
- **Mechanics:** An agent systematically introduces subtle mutations into AST/code:
  - Invert relational operators (`>` $\leftrightarrow$ `>=`, `<` $\leftrightarrow$ `<=`)
  - Remove database transaction wrappers or rollback logic
  - Invert boolean flags or default parameters
  - Drop cache invalidation / prefetch triggers
  - Truncate loop boundaries
- **The Token Sink:** For each mutation, the agent runs the targeted test file.
  - **Mutant Killed:** A test fails $\rightarrow$ The existing test suite is guarding this behavior.
  - **Mutant Survived:** All tests pass $\rightarrow$ **A proven, objective gap in test coverage exists.**
- **The Output:** The agent logs a surviving mutant, drafts an issue with the mutant patch, and constructs a test that fails on the mutant and passes on correct code.

### B. Property-Based Fuzzing & Model Checking
- **Concept:** Chess repertoires, move trees, transpositions, and SRS algorithms are formal state machines.
- **Mechanics:** Write property generators running 10,000+ randomized iterations:
  - **FSRS Monotonicity:** Test that higher stability never yields shorter intervals, difficulty is clamped $[1, 10]$, and retrievability satisfies $R(t) \in [0, 1]$.
  - **Tree & Transposition Round-tripping:** Generate random valid PGNs with deep variations, commentary shapes (`[%cal ...]`, `[%csl ...]`), transpositions, and castling formats. Prove parsing and re-export are 100% idempotent and lossless.
  - **Session Quota & Continuity:** Fuzz state sequences (mixes of correct, lapse, skip, and transpositions under `ReviewContinuity.fullLine` and daily limits). Prove absence of infinite loops, deadlocks, and unhandled exceptions.
- **The Output:** Any failure produces a minimal shrunk counterexample PGN or action sequence filed as an Issue.

### C. Migration Archeology & Invariant Proving
- **Concept:** Schema changes across 18 SQLite migrations must never drop or corrupt user data.
- **Mechanics:** Build automated fixture databases for schemas v1 through v18, populate them with real-world synthetic repertoires, and run forward migrations to v18.
- **The Output:** Verify that zero orphan rows (such as the 117 orphaned review states from the Oct 16 audit) are produced, and that foreign-key cascades remain strictly sound.

---

## 4. The 3-Agent Adversarial Architecture

Coordinate autonomous agents using Git and GitHub Issues/PRs as the decoupled message bus:

```text
 ┌────────────────────────────────────────────────────────┐
 │                   AGENT 1: The Breaker                 │
 │            (Fuzzer / Mutation Tester / Red Team)       │
 └───────────────────────────┬────────────────────────────┘
                             │
                             │ Finds a surviving mutant or property failure
                             ▼
                 [ GitHub Issue Created ]
                 - Minimal failing test repro
                 - Cited SPEC.md invariant
                             │
                             ▼
 ┌────────────────────────────────────────────────────────┐
 │                   AGENT 2: The Builder                 │
 │                 (Worktree-Isolated Solver)             │
 └───────────────────────────┬────────────────────────────┘
                             │
                             │ 1. Proves test fails on origin/main
                             │ 2. Writes minimal fix
                             │ 3. Runs gates.sh t1
                             ▼
                  [ GitHub PR Opened ]
                  - Clean single-purpose commit
                  - No test-weakening patterns
                             │
                             ▼
 ┌────────────────────────────────────────────────────────┐
 │                   AGENT 3: The Sentinel                │
 │                 (Diff Auditor / Gatekeeper)            │
 └───────────────────────────┬────────────────────────────┘
                             │
                             │ Audits PR diff against SPEC & AGENTS.md
                             ▼
                 [ Ready for Human Merge ]
```

### Agent Roles & Boundaries:

1. **The Breaker (Red Team):**
   - **Constraint:** Never modifies `lib/`. Never fixes bugs.
   - **Job:** Generates counterexamples, surviving mutants, or stress failures.
   - **Output:** GitHub Issue with a copy-pasteable failing test file (`test/repro/issue_xxx_test.dart`).

2. **The Builder (Blue Team):**
   - **Constraint:** Works strictly in an isolated worktree (`../chesssrs-<task>`), stages only by name, never touches unrelated files.
   - **Job:** Takes an open Issue, proves the test fails, writes the minimal fix, verifies locally on a test budget, and opens a PR.

3. **The Sentinel (Auditor):**
   - **Constraint:** Read-only inspection of the PR diff and CI run.
   - **Job:** Ensures no protected files (`GATES.md`, `SPEC.md`, `analysis_options.yaml`) were tampered with, no tests were loosened or skipped, and no fake abstractions were added.

---

## 5. Repository-Specific Guardrails (ChessSRS Invariants)

1. **Never Melt The User's Machine (`AGENTS.md` §3.1 & Hard Rule):**
   - Never run full-workspace tests locally (`flutter test` without path or `./verify`).
   - Run targeted tests with `--plain-name` filters.
   - Run `flutter analyze` only on touched files after the final edit.
   - Offload heavy regression validation to GitHub Actions CI.
2. **Worktree Isolation:**
   - Every Builder agent must work in its own worktree branched from `origin/main`.
   - Never run destructive git commands (`git reset --hard`, `git clean`) outside the assigned worktree.
3. **Repository Identity:**
   - Active repository is `cassandre60/ChessSRS`. Never target the archived `chess-repertoire-srs`.
4. **No Automatic Merge:**
   - All PRs queue cleanly on GitHub for human review and click-to-merge.

---

## 6. Execution Plan & Next Steps

1. **Phase 1: Harness & Tooling Setup**
   - Deploy `scripts/autonomous/mutation_engine.py`: A lightweight, AST/token-based Dart mutation test runner that iterates over target domain files, mutates them, runs the targeted test, and logs surviving mutants.
   - Deploy `scripts/autonomous/orchestrator.py`: CLI harness to spawn breaker/builder sessions in git worktrees.
2. **Phase 2: Seed Queue from Known Specification Holes**
   - Tackle confirmed findings from `docs/spec-conformance-audit-2026-10-16.md`:
     - **F2:** Rewrite `INV-002` test to verify tree JSON is genuinely untouched on answer save.
     - **F3:** Fill missing migration coverage for schemas v6–v11 and v14–v15.
     - **F4:** Fix `INV-051` chunking test so it tests SQLite parameter limits with >400 chunk boundaries.
     - **F5:** Trace and eliminate the origin of orphaned `srs_review_state` rows.
3. **Phase 3: Continuous Mutation & Fuzzing Pipeline**
   - Run the Breaker against `lib/src/domain/` to surface genuine logic blindspots.
