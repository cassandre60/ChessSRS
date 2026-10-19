# Red-team case: rt-06-trace-break

Status: active
Category: weaken-assertion (traceability)
Expected catcher(s): G05 spec traceability

## What the patch does
Deletes the `// SPEC coverage: INV-008.` citation line from
`test/app_links_service_test.dart` (line 1 at the recorded commit),
leaving the tests themselves intact. INV-008 is the only invariant whose
citation across every file under `test/` lives in exactly one place, and
that place is this header line, so deleting it orphans the invariant.

## Why it is wrong
The spec claims coverage the suite no longer demonstrates. (Deleting the
test instead would be caught by G08; this case proves G05 watches the
mapping itself.)

## Why a naive gate would pass it
The suite is green and no assertion was touched; only the trace check
notices the orphaned invariant.

## History
Re-registered 2026-10-18 against a new premise, after premise drift made
the old one false rather than after any gate weakened.

The original patch deleted `// SPEC coverage: INV-050.` from
`test/review/move_latency_test.dart` on the premise that "INV-050 is cited
nowhere else". That stopped being true — the runner correctly classified
the case as ESCAPED because G05 passes it, and G05 is right to pass it.
`spec_trace_check.py` unions the IDs found anywhere under `test/`, so one
invocation was never what the premise claimed. At the recorded commit:

```
rg -n "INV-050" test/
test/view/review/review_screen_test.dart:285:    // SPEC INV-050: RepaintBoundary isolates BoardWidget from outer widget repaints.
test/review/review_controller_test.dart:2175:    // SPEC INV-050. A graded move settles within one frame.
test/review/move_latency_test.dart:3:// SPEC coverage: INV-050.
```

Deleting one of three citations orphans nothing. The case's property —
deleting the LAST citation of an invariant is caught by G05 — is still
worth testing, so it now targets a genuinely single-cited invariant.
Candidates enumerated over all 132 files under `test/` at the recorded
commit were INV-004, INV-008, INV-040, INV-042, INV-060, INV-063 and
INV-064; INV-008 was chosen because, like the original, it is cited by a
dedicated one-invariant `// SPEC coverage:` header line, so the patch is a
single-line deletion and G05 — not G08 — is its only catcher.

Real escape 2026-10-02 (#129), same lineage as rt-08-sri-trace-break.

Patch file: `patch.diff` (git diff format, applies to the commit recorded below)
Recorded against: a9fbfe0fbfb87fc63921c5606aae4ec1b10dc8a9