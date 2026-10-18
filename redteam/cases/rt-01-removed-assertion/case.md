# Red-team case: rt-01-removed-assertion

Status: active
Category: weaken-assertion
Expected catcher(s): G08 test-weakening tripwire

## What the patch does
Deletes one `expect(...)` line from `test/domain/scheduler_test.dart`
(the `maximumInterval` cap assertion `expect(interval, const Duration(days: 30));`,
line 160 at the recorded commit), leaving the test body otherwise
intact — the INV-026 comment explaining why the check must be an
equality stays, only the check itself goes.

(Re-recorded 2026-10-18: the original patch targeted the older
`expect(interval.inDays, lessThanOrEqualTo(30));` line, which #216-era
work replaced with an exact-equality cap check plus the SPEC INV-026
comment. The patch had gone STALE — it no longer applied — and the nightly
T3 recall run 39108873052 flagged it. Same gaming change, re-expressed
on the current line.)

## Why it is wrong
The test still passes but no longer checks the INV-026 bound it was written
for; a later clamp regression would go green.

## Why a naive gate would pass it
The suite is green, coverage is unchanged, and no file is skipped.

Patch file: `patch.diff` (git diff format, applies to the commit recorded below)
Recorded against: a9fbfe0fbfb87fc63921c5606aae4ec1b10dc8a9