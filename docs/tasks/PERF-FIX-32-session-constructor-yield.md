# PERF-FIX-32 — ReviewSession constructor blocks UI isolate: measure first, chunk-yield if needed

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing. **This is a measure-first brief: if the measurement
> shows no problem, close the brief with the numbers instead of changing code.**

## 1. What might be broken

`lib/src/domain/review/review_session.dart` — the `ReviewSession` constructor
(lines ~48-188) runs synchronously on the UI isolate:

* Builds 4 maps from `decisions` (`_studies`, `_chapters`, `_decisionsById`,
  `_decisionForNode`)
* Calls `_indexNodes` on **every chapter tree** — walks every node
  recursively
* Builds `_decisionsByCanonicalId`, `_decisionsByFenKey`,
  `_canonicalByFenMove` in a second pass over all decisions
* Builds the initial due queue in a third pass

Total: ~3 O(decisions) passes + 1 O(tree nodes) recursive walk. For a 10k-
decision repertoire this is plausibly 20-100 ms of blocked UI — one or more
dropped frames on session start. `Isolate.run` is **not** available as a fix:
the session holds a `GraphAwareReviewCoordinator` with a
`_SessionReviewStateRepository(this)` closure — not sendable across isolates.

## 2. Phase 1 — measure (do this first)

Add a temporary timing harness in `test/review/` (do not commit):

```dart
test('constructor timing with 10k decisions', () {
  final decisions = List.generate(10000, (i) => makeDecision(i));
  final chapters = [makeChapterWithTree(10000)];
  final sw = Stopwatch()..start();
  ReviewSession(studies: [...], chapters: chapters, decisions: decisions,
                reviewStates: const {});
  sw.stop();
  debugPrint('CTOR_MS=${sw.elapsedMilliseconds}');
});
```

Run it 5 times, take the median:

```bash
for i in 1 2 3 4 5; do
  fvm flutter test test/review/review_session_test.dart --plain-name 'constructor timing' 2>&1 | rg CTOR_MS
done
```

**Decision rule:**

* Median < 16 ms → **no problem exists**. Remove the timing test, open no PR
  changing the constructor. Instead open a PR adding *only* a comment to the
  constructor: `// Measured 2026-10: X ms for 10k decisions — sync
  construction is fine below ~50k decisions.` and close this brief.
* Median ≥ 16 ms → proceed to Phase 2.

## 3. Phase 2 — the fix (only if measurement says so)

Convert to an async factory with cooperative yielding — the constructor stays
private and synchronous; a new static `ReviewSession.build(...)` chunks the
indexing with event-loop yields so frames can render:

```dart
static Future<ReviewSession> build({
  required List<Study> studies,
  required List<Chapter> chapters,
  required List<RepertoireDecision> decisions,
  ... // same params
}) async {
  final session = ReviewSession._partial(...);  // maps only, no indexing
  await session._indexNodesChunked(chapters);   // yields every ~500 nodes
  await session._buildCanonicalIndexChunked(decisions);  // yields every ~1000
  session._buildInitialQueue(decisions);
  return session;
}
```

Implementation notes:

* Yield with `await Future<void>.delayed(Duration.zero)` every N items — N
  chosen so each chunk is ~4 ms (calibrate from Phase 1 numbers).
* The existing sync constructor **must remain** for tests (hundreds of
  existing tests call it directly) — `build` is additive, used by the
  production path in `review_service.dart` / `review_controller.dart`.
* Find the production construction site: `rg "ReviewSession(" lib/` — swap
  only that call to `await ReviewSession.build(...)`.
* Do not change session semantics: queue order, canonical dedupe, coordinator
  wiring all identical. This is a scheduling change, not a behavior change.

### What NOT to change

* Do not remove or alter the sync constructor — tests depend on it.
* Do not attempt `Isolate.run` — closures make it impossible.
* Do not change `_indexNodes` logic — only *when* it runs (chunked).
* Do not touch `SPEC.md`, `GATES.md`, `.gates/`, `pubspec.yaml`.

## 4. Verification

```bash
git worktree add ../chesssrs-perf-fix-32 -b fix/perf-fix-32-session-constructor origin/main
cd ../chesssrs-perf-fix-32
fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs

# Phase 1 measurement (see §2) — include CTOR_MS numbers in the PR body
# Phase 2 (if needed):
fvm flutter test test/review/review_session_test.dart
fvm flutter test test/review/review_service_test.dart
fvm flutter analyze

git add lib/src/domain/review/review_session.dart lib/src/review/review_service.dart
git commit -m "perf(review): chunk ReviewSession indexing with event-loop yields (CTOR_MS=X→Y)"
./scripts/gates.sh t1
git push -u origin fix/perf-fix-32-session-constructor
gh pr create -R cassandre60/ChessSRS --title "perf(review): chunk ReviewSession constructor indexing" --body "Closes PERF-FIX-32. Before: X ms / 10k decisions. After: chunked, worst frame Y ms."
```

GATES note: this is class `perf` — the PR body needs before/after numbers on
the pinned harness (the Phase 1 test) plus an equivalence argument (same maps
built, same queue order — existing tests cover it).

## 5. Done when

* [ ] CTOR_MS measurement for 10k decisions recorded in PR body (either way)
* [ ] If <16 ms: comment-only PR, brief closed with numbers
* [ ] If ≥16 ms: `ReviewSession.build` exists, production path uses it, sync ctor kept for tests
* [ ] All existing review tests pass unchanged
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green
* [ ] PR open against `cassandre60/ChessSRS`
