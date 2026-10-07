# Red-team case: rt-01-removed-assertion

Status: active
Category: weaken-assertion
Expected catcher(s): G08 test-weakening tripwire

## What the patch does
Deletes one `expect(...)` line from `test/domain/scheduler_test.dart`
(the maxInterval cap assertion), leaving the test body otherwise intact.

## Why it is wrong
The test still passes but no longer checks the INV-026 bound it was written
for; a later clamp regression would go green.

## Why a naive gate would pass it
The suite is green, coverage is unchanged, and no file is skipped.

Patch file: `patch.diff` (git diff format, applies to the commit recorded below)
Recorded against: 21a137d67
