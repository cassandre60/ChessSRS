# Universal Autonomous Engineering Framework & Agent Prompt
*A Reusable, Stack-Agnostic Blueprint for Recursive Repository Improvement Without Fake Work*

---

## Part 1: Philosophy & The Anti-Degeneration Model

### The Problem This Solves
When modern coding agents are given open-ended instructions (*"improve this codebase"*, *"audit and fix bugs"*, *"increase test coverage"*), they suffer from two failure modes:
1. **The 1-Hour Early Termination Stall:** Agents run static linters, run existing tests, see green output, write a summary report, and exit within 45 minutes—leaving large token budgets completely unspent.
2. **The "Fake Work" Degeneration Trap:** When instructed to keep iterating, agents manufacture artificial tasks:
   - Cosmetic churn (variable renames, formatting re-writes, splitting 5-line functions).
   - Vacuous / Checkbox tests (tautological tests asserting literals, tests asserting mock responses, or tests that pass even when the production code is broken).
   - Scope creep (hallucinating unrequested features or rewriting stable libraries).
   - Resource exhaustion (running wide, multi-worker test suites locally that melt developer workstations).

### The Solution: Mechanically Falsifiable Adversarial Loops
Real improvement occurs only when work is subjected to **mechanical falsifiability**. Tokens are channeled into continuous mutation discovery, property fuzzing, and defect proof rather than prose generation.

---

## Part 2: The 4 Non-Negotiable Invariant Laws

Any agent operating under this framework must strictly observe these four laws:

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. THE FAIL-TO-PASS INVARIANT                                               │
│    No bugfix or test is accepted unless backed by an automated test that    │
│    mechanically FAILS on unmodified `main` before the fix is applied.       │
├─────────────────────────────────────────────────────────────────────────────┤
│ 2. GIT SHA-BASED IDEMPOTENCY (DEDUPLICATION)                                │
│    Audits, mutations, and verifications are anchored to the target file's   │
│    Git commit SHA. If a file has not changed in git since its last audit,   │
│    re-auditing it is strictly FORBIDDEN.                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│ 3. WORKTREE ISOLATION                                                       │
│    Every task runs in an isolated git worktree branched from `origin/main`. │
│    Never run destructive commands (`git reset --hard`) in shared trees.     │
│    Stage files strictly BY NAME. Never `git add -A`.                        │
├─────────────────────────────────────────────────────────────────────────────┤
│ 4. LOCAL RESOURCE PROTECTION                                                │
│    Never run wide workspace test suites locally (e.g. `pytest`, `npm test`, │
│    `cargo test` over the entire repository). Run single targeted test files │
│    with path filters. Delegate full regressions to CI runners.             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 3: The 4 Universal Improvement Streams (Any Tech Stack)

### Stream A: Autonomous Mutation Testing (Killing Mutants)
- **Concept:** Take a production file and systematically invert its semantic operators:
  - Relational: `>` $\leftrightarrow$ `>=`, `<` $\leftrightarrow$ `<=`, `==` $\leftrightarrow$ `!=`
  - Logical: `&&` $\leftrightarrow$ `||`, `true` $\leftrightarrow$ `false`
  - Nullability / Conditionals: Invert null-checks, delete early return guards
  - Arithmetic: `+ 1` $\leftrightarrow$ `- 1`, boundary offset shifts
- **Verification:** Run the matching test file for each mutation.
  - *Killed:* Test fails $\rightarrow$ existing suite verified.
  - *Survived:* All tests pass $\rightarrow$ **A proven blindspot exists in the test suite.**
- **Output:** File a bug/gap report with the exact mutant diff and write a test that kills it.

### Stream B: Adversarial Test Suite Audit (The 3 Sins)
Inspect existing test files and eliminate the three deadly test smells:
1. **Vacuous Assertions:** Tests with missing `assert` / `expect`, or assertions on trivial literals (`expect(true).toBe(true)`).
2. **Circular Mocking:** Tests where the mock returns data $X$, and the test only asserts that the subject returned $X$, never exercising real business logic.
3. **Wall-Clock Timing Bombs:** Tests that use hard sleeps (`time.sleep(1)`, `setTimeout(100ms)`) rather than polling condition triggers or deterministic virtual clocks.

### Stream C: Property-Based Fuzzing & Model Checking
- Write generative tests running 10,000+ randomized iterations to verify mathematical state machine properties:
  - **Round-Trip Idempotence:** `deserialize(serialize(x)) == x` for all random valid domain structures.
  - **Monotonicity:** Invariants where input increases must strictly yield non-decreasing outputs (e.g., scoring, rate-limiting, scheduling).
  - **Boundary Invariants:** Quota limits, balances, and retries never produce negative values, deadlocks, or uncaught exceptions.

### Stream D: Data Durability & Migration Archaeology
- Ensure database schema migrations (SQL, ORM, document stores) preserve all historical user data.
- Construct fixture databases from schema version $v_1$ through $v_{N-1}$ and verify migrations upgrade cleanly to $v_N$ with zero data loss and zero orphaned rows.

---

## Part 4: The Universal Work Ledger Pattern

Every repository operating under this framework maintains `docs/AUTONOMOUS_WORK_LEDGER.md`:

```markdown
# Autonomous Work Ledger

| Date | Stream | Target File / Module | Target SHA | Status | PR / Issue | Summary / Outcome | Re-Audit Trigger |
|---|---|---|---|---|---|---|---|
| YYYY-MM-DD | Stream A (Mutation) | `src/auth/token_service.ts` | `a1b2c3d` | COMPLETED | PR #42 | Evaluated 25 mutants: 23 killed, 2 test gaps fixed | Any modification to `token_service.ts` |
```

### The Invalidation Rule:
When an agent is looking for work:
1. It queries candidate target files in priority order.
2. It compares the file's current Git commit SHA (`git log -n 1 --pretty=format:%h -- <file>`) against the ledger.
3. If the SHA matches and status is `COMPLETED`, **the file is skipped**.
4. If the file is modified (SHA changed) or absent from the ledger, **it is selected**.
5. When the agent opens a PR, it appends its completed row to the ledger.

---

## Part 5: The Master Copy-Paste Agent Prompt

*Copy and paste the markdown block below into any AI agent session in ANY repository to launch a recursive, high-signal improvement loop:*

```markdown
# MISSION: Autonomous Codebase Verification & Recursive Improvement

You are operating as an autonomous software engineer. Your objective is to mechanically improve this codebase through verifiable, high-signal pull requests without human hand-holding and without creating fake work.

## Core Directives & Laws:
1. THE FAIL-TO-PASS INVARIANT: Never write a bugfix or test unless you first prove the test FAILS on `origin/main` before applying your fix. If a test passes on current code, it has zero signal value.
2. STRICT DEDUPLICATION: Inspect `docs/AUTONOMOUS_WORK_LEDGER.md`. If a file/module is marked COMPLETED at its current Git commit SHA (`git log -n 1 --pretty=format:%h -- <file>`), do NOT re-audit it. Check `gh pr list` to ensure no active PR is already modifying your target.
3. WORKTREE ISOLATION: Always create and work inside a dedicated git worktree (`git worktree add ../<repo>-<task> -b <type>/<task> origin/main`). Never run destructive git commands (`git reset --hard`) in shared trees. Stage files strictly BY NAME.
4. RESOURCE BUDGET: Never run full workspace test suites locally. Run targeted test files with explicit filters. Let CI handle full regressions.
5. NO FAKE WORK: Do not perform cosmetic refactors, variable renames, import reorganizations, or write tests that assert trivialities or circular mocks.

## Execution Cycle:
Step 1: Consult `docs/AUTONOMOUS_WORK_LEDGER.md` (or run your ledger CLI). Pick the highest-priority target file that has never been audited or whose Git SHA has changed.
Step 2: Execute an adversarial verification pass:
  - Option A (Mutation Testing): Invert semantic operators (relational, boolean, null checks, boundaries) in the target file. Run targeted tests. If any mutant survives, you have found a real test gap.
  - Option B (Adversarial Test Audit): Inspect tests covering the target. Check for vacuous assertions, circular mocks, or wall-clock timing sleeps.
Step 3: In your isolated worktree, write a minimal reproduction test proving the gap/bug fails on unmodified code.
Step 4: Implement the minimal production fix or test hardening. Verify the targeted test now passes cleanly.
Step 5: Verify formatters and linters pass on touched files. Ensure zero test weakening.
Step 6: Append your completed entry (Date, Stream, File, SHA, Outcome) to `docs/AUTONOMOUS_WORK_LEDGER.md`.
Step 7: Push your branch and open a GitHub PR with the reproduction evidence attached.
```
