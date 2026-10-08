# Escape to gate: turning a slipped-through bug into permanent proof

Protected path. This is the procedure any agent follows when fixing a bug the
gates did not catch. Each escape must come back as a regression test, a SPEC
invariant, and a red-team case — otherwise the flywheel is decoration.

## When this applies

A user, the owner, or another agent found wrong behavior and no gate is red
because of it. (If a gate IS red, just fix the code — this document is not
needed.) The output is always a `bugfix`-class PR.

## Prerequisites

A task worktree on its own branch cut from `origin/main` (AGENTS.md §3.1).
All commands below run from the repo root of that worktree.

## The loop

### 1. Reproduce first, on the current code

Write the failing test BEFORE touching `lib/`. Name it after the behavior,
not the function. Run exactly that test and watch it fail:

```bash
fvm flutter test test/<area>/<file>_test.dart --plain-name '<test name>'
```

If no existing SPEC invariant covers it, note that — you will add one in
step 4. If one does cover it and the test still passed on buggy code, say so
in the PR: the invariant needs a sharper test, not a new invariant.

### 2. Fix the code, nothing else

Minimal diff. No drive-by refactors. Re-run the single test from step 1 —
it must pass now. That pair (fail run + pass run) is your two budgeted local
runs for the file; everything else is CI's job.

### 3. Prove fail-to-pass

```bash
EXPECT_PATTERN='<output line that proves the right failure>' \
  bash scripts/gates/fail_to_pass_check.sh origin/main \
  "fvm flutter test test/<area>/<file>_test.dart --plain-name '<test name>'"
```

Paste the output into the PR body. If the bug cannot be tested (rare), the PR
says why and the owner decides — never skip this step silently.

### 4. Add the SPEC invariant

Find the next free ID:

```bash
grep -oh 'INV-[0-9]*' SPEC.md | sort -u | tail -3
```

Append to the matching section (A persistence, B import, C review/SRS,
D architecture, E performance, F UX contract) in this shape:

```markdown
### INV-0xx One falsifiable sentence, no 'and' hiding two claims
<One sentence of context: where, when, what is affected.>
- Oracle: <the test from step 1, by name>.
- Gates: <the suite plus any gate ID, e.g. review engine suite>.
- Tier: <T0 loss/corruption/security, T1 wrong behavior, T2 UX/perf>.
- History: <date, what escaped, e.g. PR number>.
- Covering: `<test/file_test.dart>`.
```

Add a row to the Change log table at the bottom of SPEC.md. Never renumber or
reuse an ID; retire with `RETIRED (reason, date)`, never delete.

### 5. Cite the invariant from the test

Directly under the license header of the covering test file, add or extend:

```dart
// SPEC coverage: INV-012, INV-0xx.
```

Keep the line under 100 columns (wrap continuation lines as `//   ...`).
Re-run the trace check:

```bash
python3 scripts/gates/spec_trace_check.py --spec SPEC.md --tests test
```

It must report every invariant referenced and no unknown IDs.

### 6. Add the red-team case

Scaffold it (fills in the template and records the current HEAD):

```bash
bash scripts/gates/scaffold_redteam_case.sh rt-<nn>-<short-name>
```

Then, in a THROWAWAY worktree of the pre-fix commit (never your worktree),
re-introduce the bug (or the gaming variant: hardcode, weakened assert,
swallowed error), capture it, and verify it applies:

```bash
git worktree add /tmp/opencode/rt-<nn> <pre-fix-sha>
cd /tmp/opencode/rt-<nn>
# ... make the wrong change ...
git diff -- <touched files> > <repo>/redteam/cases/rt-<nn>-<short-name>/patch.diff
git apply --check --whitespace=nowarn <repo>/redteam/cases/rt-<nn>-<short-name>/patch.diff
```

Fill in `case.md`: what the patch does, why it is wrong (cite the INV),
which gate must catch it. Then prove the catcher individually — apply the
patch in the scratch worktree, commit it there, run ONLY the expected gate
script against it, confirm non-zero exit, then destroy the scratch worktree:

```bash
git worktree remove --force /tmp/opencode/rt-<nn>
```

Finish with the full recall run (judges patch deltas only):

```bash
BASE_REF=$(git rev-parse HEAD) python3 scripts/gates/redteam_runner.py \
  --gate-cmd "./scripts/gates.sh t1" --ref HEAD
```

Recall must not drop. See `redteam/cases/rt-01-removed-assertion/case.md`
for a complete example of a finished case.

### 7. Log the escape in GATES.md

One row in the escapes table: date, what escaped, root cause, and the new
invariant + red-team case IDs. An escape with no row will happen again.

### 8. Ship it as a bugfix PR

```bash
./scripts/gates.sh t1   # BASE_REF defaults to origin/main
git push -u origin <branch>
gh pr create -R cassandre60/ChessSRS
```

PR body: `Class: bugfix`, the fail-to-pass output pasted, the new INV ID,
the red-team case ID. The `gate-approved` label is NOT needed (no referee
files touched — SPEC.md and redteam ARE referee files, so if step 4 or 6
touched them, the PR is a combined bugfix+spec-change and DOES need the
label; say so plainly in the body).

## Do not

- Edit SPEC.md to match weak code, or loosen an invariant to make a test pass.
- Add a red-team case whose patch does not apply, or that no gate catches
  (that is an escape from the harness itself — strengthen a gate first).
- Weaken the tripwire, ratchets, or protected paths to get green; fix the code.
- Bundle product refactors into the bugfix; one concern per PR.
- Run the full suite or `./verify` locally to "be safe" — CI does that on push.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `spec_trace_check` reports unknown ID | test cites an INV not in SPEC.md | add the invariant first (step 4), never delete the citation |
| `spec_trace_check` reports uncovered INV | new invariant, no citing test yet | step 5 |
| tripwire fires on `redteam/` or `scripts/gates/` | should not happen — those trees are excluded | report as a gate bug, do not work around it |
| ratchet fails right after `main` advanced | baseline measured on an older tree | merge `origin/main`, re-run `collect_metrics.py`, update the baseline in the same PR with the reason |
| recall shows STALE | code moved under a patch | regenerate the patch from its `case.md`, never delete the case |
| recall shows ESCAPED | a gate is weak | stop, strengthen the gate, confirm the case is rejected, then proceed |
