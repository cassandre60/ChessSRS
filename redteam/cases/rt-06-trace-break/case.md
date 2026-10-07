# Red-team case: rt-06-trace-break

Status: active
Category: weaken-assertion (traceability)
Expected catcher(s): G05 spec traceability

## What the patch does
Deletes the `// SPEC coverage: INV-050.` citation line from
`test/review/move_latency_test.dart`, leaving the test itself intact.
INV-050 is cited nowhere else, so the invariant is orphaned.

## Why it is wrong
The spec claims coverage the suite no longer demonstrates. (Deleting the
test instead would be caught by G08; this case proves G05 watches the
mapping itself.)

## Why a naive gate would pass it
The suite is green and no assertion was touched; only the trace check
notices the orphaned invariant.

Patch file: `patch.diff` (git diff format, applies to the commit recorded below)
Recorded against: 21a137d67
