# Open questions — things only the owner can settle

Not bugs, not work in progress. These are decisions and confirmations that
engineering cannot make on its own, collected here so they don't live in a
scrolling chat log and get lost.

Each one states what is known, what is not, and what I would need from you.

| # | Question | Needs | Status |
|---|---|---|---|
| Q1 | Speed | — | **answered 2026-10-14: as fast as possible, everything.** Handoff written |
| Q2 | Capture-sound distinctness | — | closed 2026-10-14 — detail not wanted |
| Q3 | Check haptic | — | closed 2026-10-14 — detail not wanted |
| Q4 | `getDueReviewStates` | — | **answered 2026-10-14: delete.** Done |
| Q5 | G07 approval attribution | — | **answered 2026-10-14: one account for both, accepted.** No action |
| Q6 | Docs-only PRs merging alone | — | **fixed 2026-10-14** |
| Q7 | Lapse-announcement wording ("repertoire" vs "study") | — | open 2026-10-16 |
| Q8 | A corrupt timestamp in a row: roll over silently, or refuse? | — | open 2026-10-21 |

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

**Answered 2026-10-14:** *"it needs to be instant ie everything in the app need
to be as fast as possible."* So: yes, and the scope is the whole app, not just
this path.

The work is handed off in `docs/performance-handoff.md`, which carries the
measurements above, the two refuted hypotheses and their numbers, the ~13 ms that
remains unattributed, and the discipline required to close it without breaking
the app. The first instruction there is to profile, not to guess — the next move
is finding those 13 ms, not an index and not date parsing.

---

## Q2 / Q3 — Capture sound and check haptic

**Known.** #93 added sound and haptics to review moves, and both are asserted by
tests at the `MoveFeedbackService` boundary: a capture calls `captureFeedback`,
a check passes `check: true` for the heavier impact.

**Not known.** Whether the capture sound is actually distinguishable from the
plain move sound by ear, and whether the check haptic is noticeable without
looking at the phone. `FakeSoundService` returns `Future.value()`, so the tests
pass identically with the volume at zero.

**Closed 2026-10-14** — the owner's answer was to leave this detail alone. The
unit tests still assert the correct sound is selected per move type at the
service boundary, which is the most that can be checked without a human ear.
`docs/manual-test-log.md` keeps the entry marked unconfirmed rather than
restating it as verified.

---

## Q4 — `getDueReviewStates`

**Known.** Declaration-only: zero callers in `lib/`, and its single caller is its
own test in `test/persistence/sqlite_study_repository_test.dart`. Removing the
method means removing that test too.

**Why I stopped.** G08 flags a deleted test declaration as a weakening finding and
requires a human `Ack-G08: <reason>` commit-message trailer. Writing that trailer
on my own PR is precisely the abuse the gate exists to catch, so I removed the
other eight dead symbols in #105 and left this one.

**Answered 2026-10-14: delete.** Removed, with the `Ack-G08` trailer in the
committing branch recording that the owner authorised it — which is the thing
that was missing before. The gate exists to stop an agent deciding this alone;
the owner deciding it is what makes the signature legitimate rather than
self-serving.

`getDueCount` remains, and is a different case: dead in production but the
assertion helper for ~10 call sites across three test files, so retiring it is a
test refactor rather than a deletion. Not asked about, not touched.

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

**Answered 2026-10-14:** *"for now im using only 1 account for both."* Accepted,
and it is the reason this is not fixable rather than merely unfixed. No action
taken. The finding stays recorded so a future multi-account setup does not
rediscover it, and so nobody reads G07 as deterring self-approval — it does
not.

---

## Q6 — Docs-only PRs cannot merge alone (FIXED 2026-10-14)

**The problem.** `gates.yml` had no Markdown trigger, but branch protection
requires both `T1 fast gates` and `Tests` to *report*. A PR touching only `.md`
triggered neither, so both checks stayed permanently "expected" and the merge was
blocked — not failed, blocked, waiting on something that could never arrive.
GitHub refuses that override for admins too.

**A correction worth keeping.** This was first written up as "only `T1 fast
gates` goes missing". That was wrong. Verifying it showed `test.yml` excludes
`docs/**` as well, so **both** required checks are absent on a docs-only PR. Any
fix addressing only `gates.yml` would have looked correct, half-fixed the problem,
and left docs PRs just as stuck.

**The fix.** Added `**.md` and `docs/**` to the trigger lists of both `gates.yml`
and `test.yml`.

**Why the expensive option was the right one.** The original omission was
defensible — no CI step reads a Markdown file, so a full run confirms what cannot
fail. It stopped being the right trade once the two required checks diverged, since
a required check that never fires blocks regardless of whether it would have found
anything. The honest alternative was paying for the run. The dishonest ones were
worse: editing a file with no reason to edit it so a workflow would fire, or
having the no-op Docs Check job impersonate the suite's check name. The second is
precisely the collision closed in #95 and #107, and reintroducing it would let a
**code** PR merge on a check that ran nothing.

**Cost, stated plainly.** A docs-only PR now runs the full suite, about 6
minutes. Real, and accepted. It is cheaper than the bug it removes, where the
failure mode was misleading rather than merely annoying: it looks like a failing
test, so the instinct is to fix tests that never ran.

**Verified.** `gates.yml`'s `pull_request` filter now carries `**.md` and
`docs/**`; `test.yml`'s `push` and `pull_request` filters are identical and both
carry them — the divergence between those two filters is a documented trap in
`gates.yml`, so it was checked explicitly rather than assumed.

---

## Q7 — the lapse announcement says "study move"; the spec says "repertoire move"

**Known.** INV-060 (`SPEC.md`) quotes the announcement a screen-reader user hears
after a wrong move as `Not this move. The repertoire move is {san}.` The app ships
`Not this move. The study move is {param}.` (`lib/l10n/app_en.arb:313`). The
design docs disagree with each other as well: `design/docs/01-identity.md:96`
says "study move", while `design/docs/04-screens-and-flows.md:99` says "repertoire
move". The covering test hardcodes the shipped wording, so the suite passes
either way and cannot surface the mismatch.

**Not known.** Which word you want a screen-reader user to hear.

**Needed.** A one-word decision. Then either the `app_en.arb` string changes to
"repertoire move" (matching SPEC and `04`), or SPEC INV-060 and `04` change to
"study move" (matching `01` and the shipped app). Either is a small, self-contained
change; the point is that four places currently say two different things about one
sentence.

**Found.** 2026-10-16 spec-conformance audit
(`docs/spec-conformance-audit-2026-10-16.md`, F1).

---

## Q8 — A corrupt timestamp in a row: roll over silently, or refuse?

**Known.** `parseUtcIso` (`lib/src/persistence/fast_date_parser.dart`) reads a
stored timestamp two ways: a fast path for the two layouts it documents
(`YYYY-MM-DDTHH:MM:SSZ` and `YYYY-MM-DDTHH:MM:SS.mmmZ`), and `DateTime.parse`
for everything else. The fast path trusts the digits it reads, so a field
outside the calendar — a 13th month, a 32nd day — is not rejected: Dart's
`DateTime.utc(2026, 13, 14)` rolls over to 2027-01-14, and the row reads back
as a date nobody wrote. `DateTime.parse` refuses the same string.

**Why it is a question and not a bug I fixed.** Both outcomes are defensible and
the product has never said which it wants. Today the row reads as a rolled-over
date (a `nextDueAt` a month out reads a month out, and the card is due or not
due accordingly). The alternative is to refuse the value, which turns a corrupt
row into a read that throws. The mutation audit could not settle it either: a
mutant that disables the fast path is killed only by a test that pins the
roll-over, and a test that pins the refusal requires the behaviour change. I
would not bless either without your word.

**Not known.** Which of the two a corrupt row should produce. Nothing in the
codebase writes such a value — every writer stores a UTC ISO string produced by
`toUtc().toIso8601String()` — so this is about a row that is already broken, not
about a path the app takes.

**Needed.** One word: *roll over* (today's behaviour, left alone) or *refuse*
(the fast path validates each field and hands the string to `DateTime.parse`,
which raises `FormatException` on the read).

**Found.** 2026-10-21 mutation audit of `lib/src/persistence/fast_date_parser.dart`
#337).
