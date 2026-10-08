# Red-team case: rt-02-added-skip

Status: active
Category: skip-test
Expected catcher(s): G08 test-weakening tripwire, G10 ratchets (test_skips)

## What the patch does
Adds `skip: true` to one test in
`test/domain/repertoire_progress_test.dart`.

## Why it is wrong
A passing suite that silently runs one fewer test; the skipped behavior can
regress undetected.

## Why a naive gate would pass it
Skipped tests report success; only a skip counter or diff scan notices.

Patch file: `patch.diff` (git diff format, applies to the commit recorded below)
Recorded against: 21a137d67
