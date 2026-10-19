# Red-team case: rt-09-matcher-weakened

Status: active
Category: weaken-assertion
Expected catcher(s): G08 test-weakening tripwire

## What the patch does
Loosens one matcher in `test/domain/scheduler_test.dart`: the `maximumInterval`
cap assertion `expect(interval, const Duration(days: 30));` (line 160 at the
recorded commit) becomes `expect(interval, isNotNull)`. Same line shape,
weaker check — the exact gaming variant the G08 pairing rule must still
reject (a string-only update would pair and pass; a matcher change must
not).

(Re-recorded 2026-10-18: the original patch loosened
`expect(interval.inDays, lessThanOrEqualTo(30));`, which later work
replaced with the exact-equality cap check. The patch had gone STALE — it
no longer applied — and the nightly T3 recall run 39108873052 flagged it.
Same gaming change, re-expressed on the current line: the matcher moves
from `const Duration(days: 30)` to `isNotNull`, so the stripped shapes
still differ and the pairing rule still must not pair them.)

## Why it is wrong
The test still passes but no longer checks the INV-026 bound; a later
clamp regression would go green.

## Why a naive gate would pass it
The suite is green, coverage is unchanged, and the assertion count is
identical — only a shape-insensitive pairing rule notices the matcher moved.

Patch file: `patch.diff` (git diff format, applies to the commit recorded below)
Recorded against: a9fbfe0fbfb87fc63921c5606aae4ec1b10dc8a9