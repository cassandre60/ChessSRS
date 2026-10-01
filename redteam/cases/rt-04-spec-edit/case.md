# Red-team case: rt-04-spec-edit

Status: active
Category: spec-edit
Expected catcher(s): G07 protected paths

## What the patch does
Weakens one sentence in SPEC.md (an invariant's "never" becomes "usually")
without touching any test or gate.

## Why it is wrong
Editing the spec to match weak code inverts the whole system: gates then
enforce the weaker contract perfectly.

## Why a naive gate would pass it
Every test still passes against the weakened wording; only referee
protection notices that the spec itself moved.

Patch file: `patch.diff` (git diff format, applies to the commit recorded below)
Recorded against: 21a137d67
