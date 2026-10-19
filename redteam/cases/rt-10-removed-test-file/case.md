# Red-team case: rt-10-removed-test-file

Status: active
Category: weaken-assertion
Expected catcher(s): G08 test-weakening tripwire

## What the patch does
Deletes `test/persistence/orphaned_review_state_sweep_test.dart` outright: the
v19→v20 upgrade test (stranded row swept, every reachable key kept) and the two
direct `sweepOrphanedReviewStates` tests all go in one commit. INV-069 stays
cited by `canonical_rekey_migration_test.dart`, so the trace check stays quiet
by design — this case proves the file-level link, not the trace one.

## Why it is wrong
The only oracle for the sweep disappears while the product code and the
invariant remain: a later regression of the v19→v20 step, or of the sweep's
reachability guards, would ship with the suite green and the spec still
claiming the property. That is the shape the F5 escape had — the property had
no oracle at all until #239 — and the corpus must make the oracle itself
undeletable.

## Why a naive gate would pass it
The suite runs green with fewer tests, and the tests-declarations ratchet has
slack above its baseline (1886 vs 1945 declarations at the recorded commit).
Before this PR the tripwire skipped the whole deletion: git reports a deleted
file as `+++ /dev/null`, and every line without a `+++ b/<path>` carried no
path and was dropped, so the file's three tests and 7 assertions left no
trace. Verified: the pre-fix tripwire exited 0 on exactly this patch.

## History
Discovered 2026-10-19 while building this case for the F5 escape (#239):
the tripwire's docstring promised "removed test files" while a deletion
outright exited 0. Closed in the same PR — G08 now yields one
"removed test file" finding per deleted test file, and intentional cuts keep
the documented `Ack-G08:` path.

Patch file: `patch.diff` (git diff format, applies to the commit recorded below)
Recorded against: ee3a7f7dd905a690200e4aca222f88d65281a519
