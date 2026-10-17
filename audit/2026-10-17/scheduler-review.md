# Scheduler & review chapter (digest)

Source: full per-test walk of test/domain/scheduler_test.dart (26 tests),
test/domain/graph_aware_review_coordinator_test.dart (14 tests),
test/review/review_controller_test.dart (64 tests).
`srs_review_session_test.dart` does not exist anywhere in the repo; ReviewSession
is covered by test/review/review_service_test.dart and review_engine_test.dart
(whose own specific gaps remain with the 2026-10-16 conformance audit, F2/F4).

## Grade distribution

104 tests walked: 82 grade 3, 17 grade 2, 5 grade 1/0-notable.

## What is strong here (pattern, worth protecting)

- Scheduler tests pin exact values, not tolerances: `expect(s1.nextDueAt, equals(t0.add(const Duration(days: 1))))` — and the EaseScaling ladder recomputes expected milliseconds with the same `.round()` shape as the implementation, so ease/scaling-confusion mutants die.
- `graph_aware_review_coordinator_test.dart:116` re-implements the decay math in the test (`0.18 * math.exp(-(1 - 1) / 1.5)`) and checks per-depth bounds, untouched-field invariants and the depth ceiling in one test. Mutations it notices: exponent sign inversion, depth off-by-one, tau misuse, beta-weight changes.
- Controller tests drive the real SQLite store (sqflite_ffi) and mock at the HTTP layer, per REPO convention, and use condition-polling (`waitUntil`, 20ms interval/5s cap) rather than fixed pumps — only two lines in the whole file still use fixed waits (752: 100ms, 1430: 500ms).
- Race windows are armed deterministically where they matter: `_PrecheckMissRepository` (controller:55) for the import race, `GatedStudyRepository` Completers (controller:1100) for scope-change races, with the comment "screen and grader disagreed on which session is current".

## The weak set (each verified against the OSS of the cited line)

| File | Line | Claim | Problem |
|---|---|---|---|
| review_controller_test | 2194 | prewarmMoveCandidate pre-calculates on touch | calls `prewarmMoveCandidate` twice, asserts only `step.isCorrect` on a normal move — deleting the entire prewarm body leaves the test green |
| review_controller_test | 950 | skip moves back of queue | 2 studies × 1 prompt each: drop-vs-rotate indistinguishable; no ordering assert |
| review_controller_test | 689 | lapsed item re-tested: dues drop | every due assert is `totalDueCount, 0` — INV-068 means dues never surface, so the name's observable is never exercised |
| review_controller_test | 1045 | delete study publishes fresh prompt | `currentPrompt` id never asserted |
| review_controller_test | 1571 | scheduler preference relaunches session | test calls `controller.reload()` manually; the "automatic" path is not what is tested |
| review_controller_test | 633 | capture sound distinct | `contains(Sound.capture)` cannot distinguish also-played move |
| scheduler_test | 94/228 | lapse resets and records | never asserts stability field of the lapse branch (`scheduler.dart:107`, `:205` set it) — SimpleScheduler twin of the ledger-1 survivor |
| scheduler_test | 136/254 | interval capped | `lessThanOrEqualTo(cap)` only — a too-tight clamp passes |
| scheduler_test | 154 | dueItems filters | `containsAll` tolerates phantom extras |
| scheduler_test | 278 | stability-zero fallback | covers EaseScaling only; SimpleScheduler's identical fallback (`scheduler.dart:85-87`) is untested (matches ledger row's Stream-1 survivor) |
| scheduler_test | 287/298 | equality/hashCode | mechanical pins; `maximumInterval` never used as a differentiator (ledger equality-survivor confirmed) |

## Boundary audity (comments vs reality)

Tested: due-at-exact-instant (line 34); rep-count branch boundaries 0/1/ge2 (61/71/80);
both maximum-interval ceilings as <= only; EaseScaling stability-zero fallback (278).
NOT tested: cap equality as exact value; lapse on a never-due new item; answering
late (now >> nextDueAt — no test distinguishes anchoring to `lastReviewedAt` because
`now` always equals the due instant); SimpleScheduler stability-zero fallback;
EaseScaling `assert(ease >= 1.0)`; tau < 0 in GraphAwareParams.

## Corruption / crash paths

None of these four files opens a corrupted/garbage database — no truncated tree
JSON, no wrong-schema-version store, no broken blob on the SRS core. Nearest
anchors elsewhere: trigger-based exception test (`sqlite_study_repository_test:853`),
corrupt-chapter refusal (`review_flip_study_test:238`), prefs corrupt-backup suite
(`preferences_storage_test:68`). No test exercises a corrupt SQLite file failing
closed at launch instead of hanging.
