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
| Q5 | Should G07 verify *who* added `gate-approved`? | a gate decision | open |
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

**What I need from you.** Whether a ~37 ms pause when opening review is
noticeable in normal use. If yes, this is worth a look; if no, it should stay
recorded and closed rather than optimised speculatively.

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

## Q5 — G07 cannot tell who approved

**Known.** `scripts/gates/protected_paths_check.py` passes when a label named
`gate-approved` *exists*. It does not check who added it, or when. An agent can
therefore label its own PR and pass the gate meant to stop agents editing
referee files. I hit this in practice: the label made G07 pass on #95 and #99,
and I applied it myself under your instruction.

**Why it matters.** G07 is one of the few gates standing between an agent and
`SPEC.md`, `GATES.md`, `.gates/`, `analysis_options.yaml`, and `pubspec.yaml`.
Its value depends on approval being a separate act by a separate person.

**What I need from you.** Whether to tighten it — most plausibly by requiring the
label to come from someone other than the PR author. That is a gate change and
needs its own PR with evidence, not a drive-by.

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