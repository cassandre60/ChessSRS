# Red-team case: rt-06-trace-break

Status: active
Category: weaken-assertion (traceability)
Expected catcher(s): G05 spec traceability

## What the patch does
Removes the `INV-069` fragment from the two `// SPEC coverage:` headers that
declare it (`test/persistence/canonical_rekey_migration_test.dart` and
`test/persistence/orphaned_review_state_sweep_test.dart`), leaving the
`INV-005` citation on both lines and every test body intact. INV-069 is then
cited nowhere under `test/`, so the invariant is orphaned.

## Why it is wrong
The spec claims coverage of the v19->v20 stranded-row sweep that the suite no
longer demonstrates. (Deleting either test instead would be caught by G08;
this case proves G05 watches the mapping itself.)

## Why a naive gate would pass it
The suite is green and no assertion was touched; only the trace check notices
the orphaned invariant.

## History
Re-registered 2026-10-22. The previous premise targeted INV-008 as the one
invariant cited in exactly one place, and that stopped being true when
`test/network/http_test.dart` added INV-008 to its header. At this recording
**no invariant under `test/` is cited exactly once** — the smallest citation
sets hold two IDs (INV-004, INV-008, INV-064, INV-069) — so uniqueness is no
longer a usable premise. Rather than follow whichever invariant is unique
next, the case now removes *every* citation of INV-069, which is the property
it exists to test: an invariant with no citation anywhere must fail G05.
Verify the premise before trusting the patch:

```
rg -n 'INV-069' test/
```

Expect exactly the two header lines above; a new citation means the patch no
longer orphans the ID and the case must be re-registered again.

Re-registered 2026-10-18 against a new premise, after premise drift made the
old one false rather than after any gate weakened. The original patch deleted
`// SPEC coverage: INV-050.` from `test/review/move_latency_test.dart` on the
premise that "INV-050 is cited nowhere else". That stopped being true — the
runner correctly classified the case as ESCAPED because G05 passes it, and
G05 is right to pass it. `spec_trace_check.py` unions the IDs found anywhere
under `test/`, so one invocation was never what the premise claimed. At that
commit:

```
rg -n "INV-050" test/
test/view/review/review_screen_test.dart:285:    // SPEC INV-050: RepaintBoundary isolates BoardWidget from outer widget repaints.
test/review/review_controller_test.dart:2175:    // SPEC INV-050. A graded move settles within one frame.
test/review/move_latency_test.dart:3:// SPEC coverage: INV-050.
```

Candidates enumerated over all 132 files under `test/` at that commit were
INV-004, INV-008, INV-040, INV-042, INV-060, INV-063 and INV-064; INV-008 was
chosen because, like the original, it was cited by a dedicated one-invariant
`// SPEC coverage:` header line, so the patch was a single-line deletion and
G05 — not G08 — was its only catcher.

Real escape 2026-10-02 (#129), same lineage as rt-08-sri-trace-break.

Patch file: `patch.diff` (git diff format, applies to the commit recorded below)
Recorded against: 91551994d3424cc8daf06ce60f0162fe589b33b6
