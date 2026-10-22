# SPEC audit continuation: answer-driven fresh-cap bypass

Recorded 2026-10-22. Class: bugfix. Contract: SPEC INV-068.

## Implemented locally, not delivered

Branch `fix/audit-fresh-cap-bypass`, based on
`5c26b4f3e5eed5c68f21c9a3af9bab1a6d959d81`. The five repairs listed in
`docs/spec-audit-handoff:docs/spec-audit-handoff.md` (plus the INV-032 repair
recorded in `docs/spec-audit-answer-fence-status.md`) remain on their separate
branches; this change integrates and publishes none of them.

The audit lead was F12: *"queue construction caps fresh items, but answering a
due ancestor can follow an opponent reply to a fresh descendant even when
`remainingNewQuota` is zero"*.

## Root cause

`ReviewSession`'s queue construction caps the fresh bucket by
`remainingNewQuota` and drops the remainder — but that cap only ever applied
to the **queue**. The answer-driven walk in `_continueWithCorrectMove` had no
equivalent gate: it asked whatever decision it reached below the answered
position, and `_isDecisionDue` treated an absent review state as eligible.
So the cap was bypassed by answering the position *above* a fresh one, and the
fresh descendant could also overtake due work that was still queued elsewhere.

## Change

`lib/src/domain/review/review_session.dart`:

- The session records the canonical ids the new-position allowance admitted
  (`_admittedFreshIds`), taken from the same `introduced` list the queue is
  built from.
- The walk's prompt site now classifies the decision it reached with
  `dueStatusOf` rather than assuming eligibility, and stops the line when the
  position is fresh and either (a) the allowance did not admit it, or (b) due
  work is still queued. Two modes are exempt from (b), each because the user
  asked for the material explicitly: dynamic repertoire mode (an unlocked line
  is the user's own request) and full-line continuity (every line is played
  whole). The allowance cap applies to both.
- `_hasQueuedDueWork` is scanned once per walk and reused, so the move path
  stays O(queue) rather than O(steps x queue) (INV-050).
- `_isDecisionDue` is **unchanged**. An earlier attempt changed it, which
  broke the INV-022 walk-steering contract (a never-learned position is
  walkable material) and four existing tests; the cap belongs at the prompt
  site, not in the due predicate.

## Observed evidence

- Failing regression on the base code. With the production file stashed, the
  new tests fail:
  ```
  00:00 +0 -1: ...answering a due ancestor does not introduce a fresh descendant when new allowance is zero (INV-068)
    Expected: 'dec-other'
      Actual: 'dec-2'
  00:00 +0 -2: ...answering ancestor with zero new allowance and no other due work completes session without introducing fresh descendant (INV-068)
    Expected: null
      Actual: ReviewPrompt:<ReviewPrompt(decision: dec-2, ...)>
  00:00 +0 -3: ...due work stays ahead of admitted fresh introductions down an answered line (INV-068)
    Expected: 'dec-other'
      Actual: 'dec-2'
  ```
  The fourth new test (practice-mode exemption) passes on the base code by
  design: it guards against the fix going too far. The same is true of the
  fifth (full-line exemption).
- After the fix:
  `fvm flutter test test/review/review_session_test.dart --no-pub --concurrency=1 --reporter=expanded`
  reported **49 passed**, including the 5 new INV-068 tests.
- The four tests that failed under the rejected `_isDecisionDue` approach pass
  again:
  `fvm flutter test test/review/review_engine_test.dart --no-pub --concurrency=1 --reporter=expanded`
  reported **47 passed**.
- The other consumers of the shared session:
  `fvm flutter test test/review/review_continuity_test.dart test/domain/due_status_test.dart test/review/review_controller_test.dart --no-pub --concurrency=1`
  reported **116 passed** together with the engine suite. These are the suites
  that assert which position is prompted after an answer, so they are the ones
  a change here could break.
- **Measured cost of the due-work scan** (temporary harness, since deleted):
  with 30,000 queued decisions the graded move measured a **median 129–136 us**
  across runs, against the 16 ms budget of INV-050. The first sample was
  4.8–7.9 ms, which is JIT warm-up on the first call, not the scan: the
  steady-state samples after it were flat. The scan is O(queue) and is reached
  only when a walk actually meets a fresh position, and it is cached per walk.
  The measurement used a synthetic fixture, so it bounds the code path rather
  than proving the owner's 61-study database behaves the same.
- `fvm dart format lib/src/domain/review/review_session.dart test/review/review_session_test.dart`
  reported no changes on the final files.
- `fvm flutter analyze lib/src/domain/review/review_session.dart test/review/review_session_test.dart --no-pub`
  reported **No issues found** (run after the last edit).

No full-suite run, no `./verify`: per `AGENTS.md` §3.1 those belong to CI.

## Scope limits that matter

- The fix changes **which position is asked after a correct answer**. It does
  not change what is persisted, the scheduler, the queue order, or the due
  figures. An answer still writes its state and event exactly as before.
- The walk now **stops** at a fresh position it may not introduce rather than
  auto-playing the user's own move there. That is the behaviour the audit
  asked for; it is a visible change to line traversal, so it is the part most
  worth a human look at runtime.
- `_hasQueuedDueWork` counts only what the queue still holds. A due position
  the daily quota already set aside does not hold a fresh introduction back,
  and a pending re-test (INV-021) does not either.
- Practice mode is exempt throughout (SPEC INV-068 says so explicitly), and
  the new test pins it.
- Dynamic repertoire mode and full-line continuity are exempt from the
  due-before-fresh ordering, not from the allowance. An unlocked line is the
  user's own request, and "every line whole" is the point of full-line
  continuity; the existing test `the walk continues onto a position unlocked by
  canonical id alone` depends on the first, and a new test pins the second.
- INV-066's off-queue **due** traversal is untouched: a due position reached
  mid-line is still prompted, exactly as before.
- The null-date exception (a stored row with `nextDueAt == null` is due) and
  INV-068's other open contract disagreements are unchanged. No SPEC text was
  edited.
- Not covered: the `maxNewPerDay` setting crossing days, a fresh position
  reached in *practice* mode (exempt), the controller's optimistic tally after
  a walk now stops early, and FSRS-specific fresh scheduling.

## Still unverified / separate follow-ups

- **Independent oracle/red-team review remains pending.** Three reviewer
  sessions failed with harness decryption errors before returning any review.
  Attempting delegation is not receiving approval.
- **No runtime validation.** No app was launched for this change; the Linux
  SDK download timed out on the previous task's bounded attempt. The
  user-visible consequence is the traversal stopping early, and that is
  exactly what a human should confirm: answer a position whose line continues
  into fresh material and check that the fresh position is not asked.
- No push, PR, CI, merge, or release. Publishing requires explicit owner
  authorization.
- No protected referee files changed. INV-068 already covers this clause;
  red-team corpus and escape-log maintenance need a separate protected-file
  change and owner approval.
- Next recommended independent repair: the remaining INV-031 / INV-028
  findings from the audit, or the INV-005 / INV-007 identity and auth items.
