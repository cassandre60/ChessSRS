# Red-team case: rt-08-sri-trace-break

Status: active
Category: weaken-assertion (traceability)
Expected catcher(s): G05 spec traceability

## What the patch does
Deletes the `// SPEC coverage: INV-064.` citation line from
`test/network/socket_test.dart` and neutralises the only other mention (the
`INV-064` comment in the analysis-route test), leaving the oracle tests
themselves intact. INV-064 is cited nowhere else in `test/`, so the invariant
is orphaned.

## Why it is wrong
The spec claims wire-format coverage the suite no longer demonstrates.
(Deleting the oracle test instead would be caught by G08; dropping the `sri`
from the connect URL itself is caught only by the required Tests lane (G04) —
t1 recall runs no flutter tests, so that link escapes t1 by construction.
This case guards the trace link.)

## Why a naive gate would pass it
The suite is green and no assertion was touched; only the trace check notices
the orphaned invariant.

## History
Regenerated 2026-10-22: the recorded hunks stopped applying because #297
removed the blank line that used to follow the coverage header and moved the
analysis-route comment down the file. The premise was re-checked before
regenerating — `rg -n 'INV-064' test/` shows exactly the two lines the patch
removes and no other citation — so this is layout drift, not a gate
regression.

Regenerated 2026-10-03: #139 added the second mention, so the one-line patch
stopped orphaning the invariant and the case escaped t1 — the trace check
counts any mention by design.

Real escape 2026-10-02 (#129: every handshake refused with HTTP 400 while
the suite stayed green); the invariant was blocked until G-BASEINV was
fixed (#135/#137).

Patch file: `patch.diff` (git diff format, applies to the commit recorded below)
Recorded against: 91551994d3424cc8daf06ce60f0162fe589b33b6
