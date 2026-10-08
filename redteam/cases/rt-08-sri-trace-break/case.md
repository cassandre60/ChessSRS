# Red-team case: rt-08-sri-trace-break

Status: active
Category: weaken-assertion (traceability)
Expected catcher(s): G05 spec traceability

## What the patch does
Deletes the `// SPEC coverage: INV-064.` citation line from
`test/network/socket_test.dart` and neutralises the only other mention
(the `INV-064` comment in the analysis-route test), leaving the oracle
tests themselves intact. INV-064 is then cited nowhere, so the invariant
is orphaned. (Regenerated 2026-10-03: #139 added the second mention, so
the one-line patch stopped orphaning it and the case escaped t1 — the
trace check counts any mention by design.)

## Why it is wrong
The spec claims wire-format coverage the suite no longer demonstrates.
(Deleting the oracle test instead would be caught by G08; dropping the
`sri` from the connect URL itself is caught only by the required Tests
lane (G04) — t1 recall runs no flutter tests, so that link escapes t1 by
construction. This case guards the trace link.)

## Why a naive gate would pass it
The suite is green and no assertion was touched; only the trace check
notices the orphaned invariant.

## History
Real escape 2026-10-02 (#129: every handshake refused with HTTP 400 while
the suite stayed green); the invariant was blocked until G-BASEINV was
fixed (#135/#137).

Patch file: `patch.diff` (git diff format, applies to the commit recorded below)
Recorded against: 832b79e07899f1751f3427ae7628a596bf54657f
