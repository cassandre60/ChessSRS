# Red-team case: rt-03-added-suppression

Status: active
Category: suppression
Expected catcher(s): G08 test-weakening tripwire

## What the patch does
Adds a `// ignore: ...` comment to `lib/src/domain/study.dart` to silence
the analyzer instead of fixing the underlying lint.

## Why it is wrong
Suppressions hide real findings and accrete; each one needs a written reason
and human acknowledgement.

## Why a naive gate would pass it
`flutter analyze` is green either way; only a diff scan notices the new
suppression (and the G10 suppression ratchet on the next metrics run).

Patch file: `patch.diff` (git diff format, applies to the commit recorded below)
Recorded against: 21a137d67
