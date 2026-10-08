# Red-team case: rt-09-matcher-weakened

Status: active
Category: weaken-assertion
Expected catcher(s): G08 test-weakening tripwire

## What the patch does
Loosens one matcher in `test/domain/scheduler_test.dart`: the maxInterval
cap assertion `expect(interval.inDays, lessThanOrEqualTo(30))` becomes
`expect(interval.inDays, isNotNull)`. Same line shape, weaker check — the
exact gaming variant the G08 pairing rule must still reject (a string-only
update would pair and pass; a matcher change must not).

## Why it is wrong
The test still passes but no longer checks the INV-026 bound; a later
clamp regression would go green.

## Why a naive gate would pass it
The suite is green, coverage is unchanged, and the assertion count is
identical — only a shape-insensitive pairing rule notices the matcher moved.

Patch file: `patch.diff` (git diff format, applies to the commit recorded below)
Recorded against: 07d0bc6307589539076c2a664632b622c91b50c7
