# SPEC audit continuation: pending answer publication

Recorded 2026-10-22. Class: bugfix. Contract: SPEC INV-032.

## Implemented locally, not delivered

Branch `fix/audit-answer-publication`, based on
`5c26b4f3e5eed5c68f21c9a3af9bab1a6d959d81`. The four repairs listed in
`docs/spec-audit-handoff:docs/spec-audit-handoff.md` remain on their separate
branches; this change does not integrate or publish them.

`ReviewController.onUserMove` captures its generation before grading. After
either initial-answer or retry persistence, a superseded operation returns its
result without publishing its old verdict, commentary, board, or advancement.
Error recovery restores the old screen only when that generation still owns it.
Service persistence and checkpoint rollback are unchanged: an acknowledged old
answer is not cancelled just because the owner changed scope.

## Observed evidence

- Before editing production code:
  `fvm flutter test test/review/answer_publication_fencing_test.dart --plain-name 'correct answer finishing after a scope switch leaves the new scope intact' --concurrency=1 --reporter=expanded`
  failed with `the stale answer republished its old scope`. The substring filter
  also selected **incorrect**; correct published three old states and incorrect
  published one after the new scope had loaded.
- After the fix, the first affected-file run reached the ownership/persistence
  assertions in all six scenarios, then failed on an incorrect assertion in the
  new test: stored event IDs are canonical, not occurrence IDs. Corrected that
  assertion against the actual event writer and repository lookup. No production
  behavior or existing assertion was weakened to accommodate it.
- Final affected-file run:
  `fvm flutter test test/review/answer_publication_fencing_test.dart --no-pub --concurrency=1 --reporter=expanded`
  reported **6 passed**. Covers correct, correct with commentary, incorrect,
  failed initial write, correct retry with actual exposure writes, and failed
  retry write. The test gates the real SQLite repository before its transaction,
  loads a different-side scope fully, releases the old answer, checks every
  publication, verifies storage/rollback, and grades the new scope's next answer.
- `fvm dart format lib/src/review/review_controller.dart test/review/answer_publication_fencing_test.dart`
  reported no changes on the final files.
- `fvm flutter analyze lib/src/review/review_controller.dart test/review/answer_publication_fencing_test.dart --no-pub`
  reported **No issues found**.
- Baseline `./scripts/gates.sh t1` passed. Post-commit gate result is recorded in
  the continuation report; a baseline empty diff does not prove the new diff.

The extra affected-file run corrected the new test's identity mistake, rather
than repeating a clean result. No more test files or wider suite were run.
The scripted fail-to-pass helper was not run: it creates a fresh checkout
without this worktree's generated files/native assets and would duplicate the
local runs. The observed before-fix failure and final pass above are the scoped
evidence, not a claim that G09's script ran.

## Still unverified / separate follow-ups

- Three independent-review sessions failed with harness decryption errors before
  returning any review. **Independent oracle/red-team review remains pending.**
  Do not mistake attempting delegation for receiving approval.
- `timeout --signal=INT --kill-after=10s 90s fvm flutter run -d linux --no-pub`
  exited **124 during Linux SDK download**, before launching the app. No real-app
  walkthrough or visual inspection occurred. See `docs/manual-test-log.md`.
- No push, PR, integrated CI, merge, or release. Main's prior Tests result does
  not cover this branch. Publishing still requires explicit owner authorization.
- No protected referee files changed. INV-032 already covers the repair;
  red-team corpus and escape-log maintenance require a separate protected-file
  change and owner approval.
- Scope loading races, other management operations, and same-generation
  service replacement are not claimed fully audited. Existing animation-time
  fencing remains unchanged. The generation guards added here cover publication
  after pending answer/retry writes and their error restoration, not the entire
  audit's contract matrix.
- Next recommended independent repair: INV-068 answer-driven fresh-cap bypass,
  per the original handoff. Preserve off-queue due traversal and migration rules.
