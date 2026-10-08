# Correctness Review Series — Index & Disposition

Four sequential reviews of the ChessSRS scheduling stack, each scoped to one subsystem and each
including the boundary into the next. This document is the single place to see what was found, what
was done about it, and what to fix first.

| # | Document | Subsystem |
|---|---|---|
| 1 | [`review-1-chessfsrs-scheduler.md`](review-1-chessfsrs-scheduler.md) | FSRS scheduler kernel |
| 2 | [`review-2-graph-aware-coordinator.md`](review-2-graph-aware-coordinator.md) | Graph propagation (contagion, exposure, coupling) |
| 3 | [`review-3-review-session.md`](review-3-review-session.md) | Session state machine |
| 4 | [`review-4-orchestration-persistence.md`](review-4-orchestration-persistence.md) | Orchestration & the storage round-trip |

**Totals:** 18 confirmed defects. 3 fixed, 1 documented and pinned, 1 deferred pending a product
decision, 1 dropped, 12 open. One design concern (review 1 · D3) was retracted outright after checking
reachability, and one review-2 design concern (D5) was corrected before it was published.

---

## CI gate status: G10 is blocked on a stale baseline, not on this branch

`T1 fast gates` fails at **G10 ratchets** on this branch, and it is not caused by anything in the
review series. `domain_loc` is ratcheted at `3020` with a `150`-line tolerance, so the ceiling is
**3170**. Measured with the gate's own `collect_metrics.py` on the PR merged into `main`, which is
what CI judges:

| tree | `domain_loc` | vs 3170 |
|---|---|---|
| branch point `fd12d85` | 3052 | 118 under |
| `main` at `23a3c5a` (today) | 3134 | **36 under** |
| `ff6f637e5` — this branch *before* the C1 fix, CI-green when pushed | **3200** | **30 over** |
| `f866be47f` — this branch now | **3194** | **24 over** |

`ff6f637e5` passed every workflow when it was pushed, and it contains none of the C1 work. It fails
now purely because `main` grew the domain by **88 insertions across 21 files** while this PR was
open, consuming the entire tolerance. `main` on its own sits 36 lines from the ceiling, so the
ratchet currently blocks any PR that touches `lib/src/domain` at all.

What was done about it here: the doc comments this series added were compressed from 74 lines to 33,
which cut this branch's footprint by 41 lines and took the merged total from 3200 to 3194. Every
fact is retained. Compressing further would mean deleting the rationale the reviews exist to record,
in order to satisfy a number that `main` itself has already overtaken — so it stops here.

**The remaining fix is a one-line re-baseline of `.gates/ratchet-baseline.json`** (`domain_loc` 3020
to, say, 3150), which is the same maintenance as `#170` (2876 to 3020). That file is a protected path
under G07, and a PR that edits its own referee and self-approves the `gate-approved` label is exactly
what G07 exists to stop, so it is deliberately **not** done here. It needs an owner.

Everything else on this branch is green: `dart format`, `flutter analyze` and `flutter test` all pass
(`f866be47f`), and G03, G05, G07 and G08 pass in the same run that fails G10.

---

## Fix these first

Ordered by what a user would actually notice, not by the order they were found.

The finding that originally ranked first — **review 2 · C1**, unbounded auto-traversal exposure
credit — is now fixed (`af0988ca2`); see review 2 §6. The remaining items are renumbered below.

| Rank | Finding | Why it ranks here |
|---|---|---|
| 1 | **Review 4 · C2** — timestamps are local time with no offset | The only finding that corrupts scheduling for real users with no unusual behaviour required. Changing timezone shifts every stored due date; one direction can flip future items to overdue and manufacture a backlog. Needs its own migration. |
| 2 | **Review 4 · C1 + D1** — latency erased on every write, conversion triplicated | Silent data loss on a reserved field. Fix the duplication first (`PositionKnowledgeState.fromReviewState`), then make the write non-destructive. |
| 3 | **Review 2 · C2** — contagion runs at 51.3% of documented strength | A whole subsystem is at half the strength the spec says. Two of three sources agree on the intended value. Changes scheduling, so it needs a deliberate decision. |
| 4 | **Review 3 · C3** — auto-traversal follows only the first user continuation | Alternative lines are never traversed and never credited. Was ranked against review 2 · C1 because the two errors pull in opposite directions. C1 is now fixed, so this one now stands alone: alternative lines are simply never traversed. |
| 5 | **Review 3 · C1 + C2** — the two progress counters disagree; the quota silently drops re-tests | C1 is invisible today (no production consumer) but is public API and checkpointed. C2 is a code comment promising the opposite of what the code does. |
| 6 | **Review 1 · C4** — switching scheduler reinterprets `stability` | Real and demonstrable, but every remedy mutates stored memory. Blocked on a product decision, documented in review-1 §6. |
| 7 | **Review 3 · C4, C5 · Review 4 · C3** | Free fixes; remove latent crashes and divergences. |

---

## Every confirmed finding

### Review 1 — FSRS scheduler

| ID | Finding | Disposition |
|---|---|---|
| C1 | Difficulty mutated during rapid re-review, contradicting §C.7 | **Fixed** `18dde77` |
| C2 | A corrected false-start graded twice — same action, two outcomes depending on which button ended the turn | **Fixed** `604d5a1` |
| C3 | Interval preview ignored the scheduler's clamps (advertised 1697 d where the scheduler emits 1095 d) | **Fixed** `5ccb7ba` |
| C4 | Switching scheduler reinterprets the `stability` column | **Deferred** — needs a product decision; see review-1 §6 |
| C5 | Lapse formula is not monotone in stability; failing can push an item further out | **Documented + pinned** `cbf3194` — matches canonical FSRS and §C.6, so a clamp would be a spec change |
| C6 | `isColdStart` never re-arms | **Open** |
| C7 | Three disagreeing difficulty defaults | **Dropped** — both columns are `NOT NULL`, so the fallbacks are unreachable |
| D1 | `steps` unvalidated in the preview | **Fixed** with C3 |
| D2 | `stability` documented as "days" when every scheduler writes milliseconds | **Fixed** `5ccb7ba` |
| D3 | O(k) sequential writes "on the review hot path" | **Retracted** — no production callers; the live path is already batched |
| D4 | Offset-less local timestamps | Traced end-to-end and re-raised as **review 4 · C2** |
| D5–D7 | Counter semantics, "FSRS-5" naming vs 4.5 math, unlinked stability/interval caps | **Open**, recorded |

### Review 2 — graph-aware coordinator

| ID | Finding | Disposition |
|---|---|---|
| C1 | Exposure credit unbounded; the throttle is in-memory so the "once per day" guarantee is per-session | **Fixed** `af0988ca2` (schema top-up in `onOpen`, see review 2 §6) |
| C2 | Contagion delivers 51.3% of the documented `λ0` (9.24% at depth 1, not 18%) | **Open, MEDIUM** |
| C3 | `recordAutoTraversalExposure` returns a state it never stored | **Open, LOW** |
| D1–D5 | Throttle/rollback conflated; depth cap vs prose; unused `parentId`; test double in `lib/`; implicit sibling-coupling contract | **Open**, recorded |

### Review 3 — review session

| ID | Finding | Disposition |
|---|---|---|
| C1 | `completedCount` and the quota counter count different things; a re-tested lapse double-counts | **Open, MEDIUM** (no production consumer today) |
| C2 | The daily quota silently discards re-queued lapses, contradicting the comment that promises them | **Open, MEDIUM** |
| C3 | Auto-traversal follows `children.first` and ignores every other user continuation | **Open, MEDIUM** |
| C4 | Unguarded `.first` on `expectedMoves` where every neighbouring consumer is safe | **Open, LOW** |
| C5 | `submitMove` and `retryMove` disagree on identity in the same fallback | **Open, LOW** |
| D1–D5 | Duplicated grading block; triple-constructed move; no re-test marker; misleading forwarder; checkpoint fidelity | **Open**, recorded |

### Review 4 — orchestration & persistence

| ID | Finding | Disposition |
|---|---|---|
| C1 | Latency telemetry erased on every persisted answer (lossy conversion + `INSERT OR REPLACE`) | **Open, MEDIUM** |
| C2 | Local timestamps with no offset; a timezone change shifts every due date | **Open, MEDIUM** |
| C3 | Sub-millisecond precision truncated on the round-trip | **Open, LOW** — immaterial at day scale |
| D1–D4 | Conversion hand-written three times; undocumented double write; dead `deleteDecisionsByStudy`; misleading method name | **Open**, recorded |

---

## What the series got wrong, and what changed because of it

Recorded because it changed how the later reviews were run, and because the pattern is worth knowing
about this codebase.

**Four findings were wrong about impact, all from the same cause: reading the code accurately without
asking whether the path runs in production.**

| Finding | What was claimed | What checking callers showed |
|---|---|---|
| Review 1 · D3 | Sequential writes on the review hot path | No production callers at all; the live path was already batched |
| Review 1 · C7 | Difficulty defaults cause a 5.0 vs 0.0 mismatch | Both columns `NOT NULL`, so the fallbacks are unreachable |
| Review 2 · D5 | Sibling coupling never fires in production | The incorrect branch passes both arguments; it fires |
| Review 3 · C1 | Progress counter visibly wrong | Rated MEDIUM, not HIGH, because nothing reads it |

From review 2 onward, **reachability was checked before severity was assigned**, and each review's
closing section records what was checked and found sound — including its own corrections. Reviews 3
and 4 also verified every line citation against the source by script rather than by eye, which caught
thirteen wrong line numbers (twelve in review 3, one in review 4) before they were committed.

**Three process failures, all caught:**

- A test asserted `lapseCount == 1` when the real value was `2` — the cold-start lapse was already the
  first. Caught by running the numbers before committing.
- An initial claim that split-form `test(` declarations broke CI formatting was wrong; the cause was a
  collection-`for` mixed with plain entries in a map literal. Isolated by a CI bisect.
- A gate failure (`G07`, `no merge base`) was a shallow-clone artifact, not a violation. Fixed properly
  with `git fetch --unshallow` rather than worked around, then re-verified.

---

## How to re-verify

No Dart toolchain is available in the environment these reviews were written in, so nothing was
executed locally. Everything was verified by reading, by arithmetic on quoted constants, and by pushing
to CI, which runs real `dart format`, `flutter analyze` and `flutter test`.

- Local gates: `./scripts/gates.sh t1`
- CI status: `gh pr checks 12`
- The C1 fix from review 1 has a fail-to-pass check against base:
  `EXPECT_PATTERN='difficulty|Expected' scripts/gates/fail_to_pass_check.sh origin/main "flutter test test/domain/chess_fsrs_scheduler_test.dart"`
