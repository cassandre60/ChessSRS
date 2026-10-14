# Open questions — things only the owner can settle

Not bugs, not work in progress. These are decisions and confirmations that
engineering cannot make on its own, collected here so they don't live in a
scrolling chat log and get lost.

Each one states what is known, what is not, and what I would need from you.

| # | Question | Needs | Status |
|---|---|---|---|
| Q1 | Does the ~37 ms review-open pause matter to you? | a product judgement | open |
| Q2 | Does the capture sound differ enough from the plain move sound in practice? | your ears | open |
| Q3 | Does a check produce a noticeable heavier haptic? | your hands | open |
| Q4 | May I delete `getDueReviewStates` and its only test? | an `Ack-G08` signature | open |
| Q5 | Swap G07's click-approval for a signed commit trailer? | a gate decision | investigated — not fixable as framed |
| Q6 | Should docs-only PRs be able to merge on their own? | a gate decision | open |

---

## Q1 — Does the ~37 ms review-open pause matter?

**Known.** Against your real library (519 decisions, 480 due), a whole-library
`startSession()` takes **37–39 ms**; ~28 ms of that is `getDueSummary`'s SQLite
queries. Measured over three runs; see `docs/tasks/PERF-FIX-24-real-library-measurement.md`.

**Not a QUALITY.md §4.1 breach.** §4.1's 16 ms is *Move Response Time* — legality
and repertoire lookup on a move. Session start is off that path.

**Not optimised.** PERF-FIX-21 already landed a targeted query there (#84), so
the remaining cost may already be near the floor for this schema. I did not
optimise further because I cannot tell whether it is worth doing.

**Not optimised, and now with the reason.** A second pass (2026-10-14) attributed
the cost: `getAllReviewStates()` is 76% of it, at 16.7 ms of a 20.8 ms total. The
SQL involved is ~1.4 ms, so **an index would buy nothing**, and the mapper's
`DateTime.parse` calls are 1.92 ms, so **that is not it either**. ~13 ms sits in
Dart, constructing and merging 772 objects, and is not yet attributed further —
two hypotheses were tested and refuted, and a third guess would be no more
reliable than the two that were wrong.

**What I need from you.** Whether a ~37 ms pause when opening review is
noticeable in normal use. If yes, the next step is a profiler run on that ~13 ms,
not an index and not date parsing. If no, this should stay recorded and closed
rather than optimised speculatively.

---

## Q2 / Q3 — Capture sound and check haptic

**Known.** #93 added sound and haptics to review moves, and both are asserted by
tests at the `MoveFeedbackService` boundary: a capture calls `captureFeedback`,
a check passes `check: true` for the heavier impact.

**Not known.** Whether the capture sound is actually distinguishable from the
plain move sound by ear, and whether the check haptic is noticeable without
looking at the phone. `FakeSoundService` returns `Future.value()`, so the tests
pass identically with the volume at zero.

**What I need from you.** One minute in review mode: play a capture, then play a
check, and tell me if you can tell them apart. Then close the item in
`docs/manual-test-log.md`.

---

## Q4 — `getDueReviewStates`

**Known.** Declaration-only: zero callers in `lib/`, and its single caller is its
own test in `test/persistence/sqlite_study_repository_test.dart`. Removing the
method means removing that test too.

**Why I stopped.** G08 flags a deleted test declaration as a weakening finding and
requires a human `Ack-G08: <reason>` commit-message trailer. Writing that trailer
on my own PR is precisely the abuse the gate exists to catch, so I removed the
other eight dead symbols in #105 and left this one.

**What I need from you.** Either the `Ack-G08` signature on a branch deleting it,
or a decision to leave it. `getDueCount` is a related case I also left: dead in
production but used as the assertion helper by ~10 call sites across three test
files, so retiring it is a test refactor rather than a deletion.

---

## Q5 — G07 cannot tell who approved (investigated: not fixable as framed)

**Asked.** Whether G07 should verify *who* added `gate-approved`.

**Answer: not implementable in this repository, and the premise of the question
was wrong.** Investigated 2026-10-14; recording it here so nobody builds it.

`scripts/gates/protected_paths_check.py` passes when a label named
`gate-approved` *exists*. It does not check who added it. The obvious fix —
require the approver to differ from the PR author — **can never be satisfied
here**:

```
$ gh api repos/cassandre60/ChessSRS/collaborators --jq '.[].login'
cassandre60
```

Every PR is authored by `cassandre60`, and that is the only account with write
access, because agents push using the owner's credentials. A
`labeller != author` rule would block every protected-path PR permanently —
including the legitimate ones. Identity is not a usable signal in a
single-account setup.

**How little the gate currently protects.** Every protected-path PR this session
was approved by its own author:

| PR | Author | Labelled by |
|---|---|---|
| #95 | cassandre60 | cassandre60 |
| #99 | cassandre60 | cassandre60 |
| #117 | cassandre60 | cassandre60 |

Three for three. G07 stopped nobody, including me — I labelled my own PRs and
recorded in each one that the gate "is working as intended", which was a
statement about the mechanism rather than about what had happened.

**What is achievable, and what it is not.** Replace the click with a signed
commit trailer, the way G08 already does: `Ack-G07: <reason>` in the branch
history. That makes approval a deliberate, permanent, publicly-visible act
instead of a label an agent can add reflexively, and G08's own output already
shows the pattern working — findings stay listed on every run even when
acknowledged.

**It would still not be a security boundary.** An agent can write a trailer just
as easily as a label. Nothing in GitHub distinguishes "the owner typed this" from
"the agent typed this" when both share one account. The improvement is
**accountability, not enforcement** — it makes approval a quotable act in history
instead of a silent state change.

**What I need from you.** Whether to make that swap. It is a gate change needing
its own PR, and it is a real improvement, but it is weaker than the question
originally implied and I would rather you know that before agreeing to it.

---

## Q6 — Docs-only PRs cannot merge alone

**Known.** `gates.yml` deliberately has no Markdown trigger, but branch protection
requires `T1 fast gates` to be *reported*. A PR touching only `.md` never
triggers it, so the check stays "expected" and the merge is blocked — including
for admins. This is not new; it is the trap recorded in the 2026-10-01 lesson.

**Why it still bites.** The workaround is to touch something `gates.yml` reads.
`IMPLEMENTATION_PLAN.md` is the usual choice, which is why several of this
project's docs PRs carry a one-line plan update they would not otherwise need.
`test.yml` gained `IMPLEMENTATION_PLAN.md` in #106 as a second patch; `AGENTS.md`
and `CODEOWNERS` are still gated this way.

**What I need from you.** Whether to fix the cause. Options I can see: add a
Markdown trigger to `gates.yml` (costs ~30 s of gates on docs PRs), or give the
Docs Check workflow a real job that emits `T1 fast gates` as well as its own
check. Both are gate changes needing their own PR. The status quo is stable, just
annoying — so this is a "worth doing or leave alone" call, not a fire.