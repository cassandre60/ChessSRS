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
| Q9 | The fail-to-pass gate script detaches the caller's worktree | — | **answered 2026-10-22: fix it — both legs now run in throwaway worktrees** |
| Q10 | Should the shared test scope FAIL on a layout overflow? | — | **answered 2026-10-22: fix the scaffolding first, then fail — done in this PR** |
| Q11 | The queue tool reported an empty queue, and the dedup law could not see the ledger | — | **answered 2026-10-22: guard it — the tool now refuses to say "nothing to do" when it is not configured** |


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

---

## Q9 — The fail-to-pass gate script runs `git checkout --detach` in the caller's directory

**Known.** `scripts/gates/fail_to_pass_check.sh` checks out the head ref with

    git checkout -q --detach "$HEAD_REF"

**in the caller's current directory**, not inside the temporary worktree the
script creates for itself. On 2026-10-22 the mutation round that fixed the
move-path id encoding ran the gate, and the script detached *that agent's*
worktree HEAD and left two of its commits off the branch. The agent repaired it
with a soft reset and a merge — no force-push, nothing lost — but the trap is
still there for the next caller.

The same hazard has bitten twice more in this repo's session: a
`git checkout --detach` in a shared tree, and a `git reset --hard` in a tree
another agent was working in (which destroyed 17 files of uncommitted work
once). This script is the third instance of the same shape, and it is the one
that is *shipped*, so it will fire again.

**Why the fleet did not fix it.** `scripts/gates/*` is a protected path
(`.gates/protected-paths.txt`): a change to it edits the referee — what
"passing" means — so it needs a human approval and a gate-change PR. The fleet
may not touch it on its own initiative.

**Not known.** Whether the intended contract is "the script never touches the
caller's tree" (the checkout moves inside the temp worktree, and the script
restores the caller's original state on exit) or "the caller must be a clean,
disposable checkout" (the script refuses to run when the caller's HEAD is not
on its branch, and says so).

**Needed.** One word, and then the fleet can cut the gate-change PR:
~~*isolate* (the checkout runs inside the script's own temp worktree, and the
caller's HEAD is never touched) or *refuse* (the script detects that the
caller's HEAD is detached or off-branch and exits with an explanation instead
of running).~~ **Answered 2026-10-22: *isolate*.** The script now creates TWO
throwaway worktrees — one at the base with the PR's test files dropped in, one
at the head — and runs both legs inside them, so the caller's checkout is
never touched and the "must pass on the change" leg really tests the head
commit. A self-test (`scripts/gates/fail_to_pass_check_test.sh`) proves it, and
fails against the previous version of the script.

**Found.** 2026-10-22, by the mutation round on `lib/src/model/common/uci.dart`
(#364) while running the gate after committing.

---

## Q10 — Should the shared test scope FAIL on a layout overflow?

**Known.** The shared widget-test scope (`test/test_provider_scope.dart`)
swallowed every RenderFlex overflow error for months, so the 270 "overflow
sites" it reported were mostly the harness's own mis-measurement. Two fixes
have now landed: the scope **reports** the overflows instead of swallowing them
(#339), and it **measures like the app** — the app's own `srsThemeData`, a
`Material` ancestor, and the app's font families registered from the app's own
`FontManifest.json` (#357).

Measured after both, one file at a time over all 59 files that use the scope:
**268 → 78 overflow occurrences, and ZERO of them in production code.** The 78
are 76 in `game_layout_test.dart`'s own bare-`Text` scaffold (a fixture that
builds its own `MaterialApp` with no `Scaffold`, so the board's top table gets
Material's 48 px monospace error style) and 2 deliberate ones in the scope's
own test. The two candidate production defects the earlier triage had named
(`offline_computer_game_screen.dart:503`, `primitives.dart:216`) turned out to
be test-font artefacts and are **gone** on the corrected base.

**What a 0 px threshold would cost.** It would redden **8 tests in 2 files**,
both of them test scaffolds, and no production site. In other words: the
harness can now be made honest without reddening the world.

**Why it is your call.** This changes what "green" means for the whole suite.
Today a layout defect can still pass CI as long as the widget does not throw.
Making the scope fail at 0 px turns every future overflow into a red build —
which is the point, but it is a change in policy for the whole project, not a
fix to one screen.

**Not known.** Whether you want the 8 remaining scaffold failures fixed first
(the `game_layout_test.dart` fixture could be given the app's theme and a
`Scaffold`, like the shared scope now has) so the threshold can be set to 0
immediately, or the threshold set to 0 now with those 8 known-red tests
excluded by name until the fixture is fixed. The first is cleaner; the second
is one PR instead of two.

**Needed.** ~~One word~~ — **answered 2026-10-22: *fix then fail*.** The scaffolding was repaired first and the scope now fails: the one test file whose own fixture overflowed (76 occurrences) was given the app's theme and a `Material` ancestor instead of being exempted, and the shared scope now forwards a `RenderFlex` overflow to the test framework instead of swallowing it, while still printing the greppable marker. A layout overflow in a widget test is now a red test.

**Found.** 2026-10-22, by the harness-measurement work (#355/#357) and the
triage of the overflow blind spot (issues #334, #336).

---

## Q11 — The queue tool reported an empty queue, and the dedup law could not see the ledger

**Known.** Two of the fleet's own instruments have been reporting "nothing to do" while there was plenty to do. Both were measured with the tools' own parsers, not by eye.

**First: the queue tool proposed nothing.** `scripts/autonomous/ledger.py next --stream 1` answered *"No eligible targets remain for this stream at their current hashes."* The reason is in `candidate_paths()`: when the config's `candidates.<stream>.include` list is empty it returns `[]`. The repo's `scripts/autonomous/config.json` is **gitignored on purpose** (`.gitignore`: *"The fleet config is project-local: it names this repo's test/analyze/gate commands"*), so it only exists where somebody created it — and in the primary checkout nobody had. The tooling then ran on its built-in defaults, where the include list is empty and the queue is empty by construction. The fleet's work list has been coming from a hand-written script, not from the tool that is supposed to produce it.

**Second: the mapping guessed the wrong path.** With no config, the Dart mapping guesses `test/<path-with-lib/-stripped>_test.dart`, so `lib/src/view/analysis/analysis_screen.dart` maps to `test/src/view/analysis/analysis_screen_test.dart` — and this repo's test tree has no `src/` segment. The tool therefore found an existing companion test for **0 of 329** lib files, while the real convention (`lib/src/<rest>.dart` ↔ `test/<rest>_test.dart`) has one for 119.

**Third: the ledger itself was invisible to the dedup law.** 54 of its 85 rows carried a decorated status cell (`COMPLETED (second round: …)`) where the tool accepts only exactly `COMPLETED` or `SOUND`, so they were skipped; and for six files the bugfix row sat below its round row, recording a pre-change blob. The tool saw **27 rows** and would have re-audited **34 of the 48** lib files the ledger names — including files audited and fixed hours earlier. That part is fixed (PR #376).

**What I did about it.** The local config now exists in the primary checkout (it is gitignored, so it never appears in `git status` — that is the repo's convention, and I did not change it). With it, the queue tool proposes **79 eligible targets** — the same 79 the hand-written script had been producing — each with its correct mapped test and composite `source:companion` hash.

**Not known.** Whether the tooling should **fail loudly** when the project-local config is missing, instead of silently reporting an empty queue. Today the failure mode is the worst kind: a green answer that means "I was not configured". A one-line guard in `candidate_paths()` — no config, or an empty `include`, is an error with a message that says which file to create — would have caught this the first time it ran. That file is under `scripts/autonomous/`, which is a protected path, so the fleet may not change it on its own initiative.

**Needed.** ~~One word~~ — **answered 2026-10-22: *guard*.** The tooling now refuses to report an empty queue without a config: it exits with a message naming the key and the file to create, and a candidate list that matches no file is reported separately from an exhausted queue. The committed example config also describes THIS repo (Dart globs, the `lib/src/<rest>.dart` ↔ `test/<rest>_test.dart` mapping, the real commands) instead of a generic Python template, so a fresh clone starts from something that works.

**Found.** 2026-10-22, by the fleet's own consistency check after a ledger correction: measuring the ledger's visibility with the tool's parser surfaced the queue tool reporting an empty queue.
