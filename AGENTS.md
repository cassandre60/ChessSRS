# Agent Operating Guidelines

## 0. Start here

ChessSRS is a GPL-3.0 Lichess Mobile fork, a local-first repertoire/SRS trainer.
The beta is in refinement; `legacy/pre-reset` is behavioral reference only.
Use the authority map in §1, then read the homes relevant to the task:
PRODUCT/MVP for scope, ARCHITECTURE for boundaries, SPEC for exact behavior,
QUALITY for additional constraints, CLAUDE for Dart/Riverpod conventions.
Read GATES before editing. For scheduling math read
`ChessSRS Scheduling Architecture.md`; for cuts read CUT_PROPOSALS; for reference
integration read `docs/INTEGRATION_MAP.md`; for visual work read `design/README.md`.

## 1. Authority and conflicts

This protected section owns the authority map; docs/documentation-map.md is
only its navigation pointer. Each subject has one normative home. Summaries,
dated audits, proposals and completed tasks do not create competing rules.

| Subject | Authoritative home |
|---|---|
| Product intent, journeys and non-goals | PRODUCT.md |
| Current included/deferred beta scope | MVP.md |
| Module boundaries, storage arrangement, licensing | ARCHITECTURE.md |
| Exact behavioral invariants, stable IDs, oracles/test links | SPEC.md |
| Engineering constraints not captured by an INV | QUALITY.md |
| Scheduling math and graph mechanisms | ChessSRS Scheduling Architecture.md |
| Local/remote verification and runtime acceptance | TEST_STRATEGY.md |
| Gate registry, change-class evidence, protected-file approval | GATES.md |
| Planned gates and promotion criteria | GATES_PLAN.md |
| Delivery status, dated evidence and work queue | IMPLEMENTATION_PLAN.md |
| Agent task selection, isolation and safe delivery | AGENTS.md |
| Dart/Riverpod/codegen/test-helper conventions | CLAUDE.md |
| Visual/copy specification | design/docs via design/README.md |
| Inherited subsystem cut decisions/status | CUT_PROPOSALS.md |
| Reference-source provenance and extraction boundaries | docs/INTEGRATION_MAP.md |
| Decision rationale and explicit supersession | docs/decisions.md |
| Owner decisions needing resolution | docs/open-questions.md |
| Unconfirmed physical/device checks | docs/manual-test-log.md |
| Publishing, stamping, artifacts and proof mechanics | docs/releases.md |

Code implements specifications; it proves current behavior, not intent. Prefer
the home above for its subject; SPEC is the exact contract for numbered rules.
When normative homes disagree, stop the affected behavioral change and record
it in open-questions. Do not silently change tests, lower budgets, remove
features or treat code as owner approval. Update the home, then repair pointers;
protected edits follow GATES's dedicated approval lane.

Config/scripts own pins, schema versions, workflow triggers, protected paths
and ratchet values. Cite paths instead of caching counts/line numbers. README
summarizes the delivery ledger. Historical entries retain dates/evidence with
explicit newer dispositions; they are not standing instructions.
Historical instructions/incident evidence live in `docs/agent-history.md`;
consult them for an incident, not as another operating manual.

## 2. Select work

Use the explicit user request or a ready task in IMPLEMENTATION_PLAN; inspect
the live premise before editing. `docs/tasks/README.md` indexes briefs;
`docs/AUTONOMOUS_IMPROVEMENT_CATALOG.md` applies to autonomous improvement work.
Feature expansion requires PRODUCT/MVP justification, not an agent's preference.
Reference-project behavior does not override the accepted local contract.

## 3. Development loop

1. Check git status, remotes, recent CI and the requested task's live state.
2. Isolate work; read the applicable contract and define one testable change.
3. Write a regression/contract test, implement minimally, follow CLAUDE.
4. Verify under TEST_STRATEGY; review the diff for scope and unrelated work.
5. Record delivery/evidence in IMPLEMENTATION_PLAN. Contract/referee changes
   use the separate approval lane in GATES, not an ordinary product commit.
6. Stage by name; make an atomic Conventional Commit identifying OpenCode and
   the actual model. Report exactly what was and was not verified.

### 3.1 Verification pointer

**TEST_STRATEGY §2 is the single local-machine budget:** narrow single-worker
tests, one final affected-file run, one analysis after the last edit; full
suites and release builds belong to CI. No local wide-suite/watch/offline
exception. Markdown-only work needs no Flutter setup/codegen.
GATES specifies the post-commit fast check and required evidence.

### Isolation: one worktree per task

The only repository is **cassandre60/ChessSRS**. The archived
`cassandre60/chess-repertoire-srs` is not a destination for branches or PRs.
Confirm origin resolves to the former before any remote write. Each task gets
its own worktree/branch from origin/main; main changes only through merged PRs.

```bash
git fetch origin main
git worktree add ../chesssrs-<slug> -b <type>/<area>-<slug> origin/main
```

Operate/edit only inside that worktree. Before compiling a fresh tree,
follow CLAUDE's dependency/codegen setup; skip it for docs-only work.

- Stage explicit files, never `git add -A`.
- Check status before/after tree changes. Preserve unfamiliar/unrelated work.
- Never reset, stash, clean or restore another worktree, or remove one you did
  not create. Read `git worktree list` first.
- Updating the owner's checkout belongs to its owner/operator. Report a stale
  checkout rather than writing into it.
- Before acting on a shared remote branch/PR, fetch/re-read its live tip,
  state and head SHA; integrate moved tips, never force them away.
- Disclose overlapping subsystem work before starting. Worktrees expose
  conflicts; they do not resolve design disagreements.
- Push only when explicitly authorized by the user/session instructions.
  Use `-R cassandre60/ChessSRS` on every gh PR/run command; fork defaults may
  resolve to upstream. Merging belongs to the merge agent.

## 4. Runtime validation

TEST_STRATEGY §4 owns real-app/visual acceptance and uncovered-device evidence.
Automated green is not a runtime pass. Follow that protocol for user-visible
work before claiming a milestone complete. Release/proof workflow distinctions
live in `docs/releases.md`; inspect their actual definitions before dispatching.

## 5. Quality and tests

SPEC owns numbered invariants/oracles; QUALITY owns remaining constraints.
New behavioral tests cite applicable stable IDs. A test earns its place by
failing when code is wrong, not merely different. Use GATES's change-class
evidence and `docs/ESCAPE_TO_GATE.md` for escaped bugs.

## 6. Feature-creep policy

PRODUCT §6 and MVP §3 own exclusions. Retained optional Lichess sign-in and
analysis tools are not authorization for a new cloud/account/social product.

## 7. Licensing

Follow ARCHITECTURE §6; preserve LICENSE/COPYING/notices. Reference adaptation
rules and source pointers live in `docs/INTEGRATION_MAP.md`.

## 8. Reference work

For PGN trees, repertoire training or SRS changes inspect relevant source
pointers in INTEGRATION_MAP plus inherited `model/study/` and
`model/common/node.dart`. Mine behavior, not old architecture. Accepted local
contracts take precedence over upstream examples/recommendation reports.

## 9. Cuts

Follow CUT_PROPOSALS's owner decisions, trace shared dependencies before
deleting, keep one subsystem per commit and use TEST_STRATEGY for verification.

## 10. Gates and consent

GATES owns evidence classes, protected-file policy and gate operation;
`.gates/protected-paths.txt` is the executable protected set. No bundled product
code in a referee/spec change. Do not weaken assertions/checks to obtain green.
After three failed attempts on the same gate, stop and report evidence.

Approval is **per item and explicit**. Explain in plain terms what changes,
what it costs and what declining means. Do not treat silence, "continue", the
initial task request or another PR's approval as approval of this diff. If the
owner agrees, perform the label/action and record whose consent it was.
One shared account cannot distinguish human from agent approval; that accepted
limitation is documented in open-questions Q5. Merging belongs to the merge agent.

## 11. Releases

After a merged green batch, state one decision: release user-visible changes;
do not release docs/tests/gates/bookkeeping or behavior-preserving refactors.
Never tag a red/unreviewed tree or move/delete a published tag. Publishing
commands, artifacts, stamping and nightly behavior live in `docs/releases.md`;
remote writes still require authorization.
Patch versions for fixes/copy, minor for features/settings. The existing tag
series has major 1; do not reset it to the obsolete "major stays 0" rule.

## Open threads and durable evidence

- Owner decisions: `docs/open-questions.md` (read status, not cached counts).
- Physical/device gaps: `docs/manual-test-log.md`.
- Performance: `docs/performance-handoff.md` and the linked measurement brief.
- Work/claims: `docs/tasks/README.md` and IMPLEMENTATION_PLAN.
- Older incidents: `docs/agent-history.md`, historical only.

Add durable, verified lessons to their subject's home; agent-workflow lessons
here need protected-file approval. Reuse entries instead of appending duplicates.
Keep task narrative in the delivery ledger, not always-loaded instructions.
