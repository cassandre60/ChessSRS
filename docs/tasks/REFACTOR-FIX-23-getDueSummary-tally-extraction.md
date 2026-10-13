# REFACTOR-FIX-23 — getDueSummary 255-line god-method → _DueTally extraction (tech-debt #10)

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

`ReviewService.getDueSummary` (`lib/src/review/review_service.dart:401-655`) is a
254-line single-pass aggregation that maintains 16 separate tally maps/sets. It is
correct and well-commented, but every new metric (like `studySideProgress` for
INV-030) adds ~15 lines to the loop body, threading a new counter through the
same 100-line conditional block. `tech-debt-inventory.md` item 10 (Impact 3,
Effort 3, Risk M) recommends extracting the per-decision tally into a small value
type (`_DueTally`) with an `add(decision, state, ...)` method and a `toSummary()`
builder.

### Structure:

* Lines 406-413: 5 DB queries to load metadata — **unchanged** (or replaced by
  targeted query if PERF-FIX-21 lands first).
* Lines 415-488: Initialize 16+ tally containers → **move into `_DueTally` constructor**.
* Lines 490-587: Single pass over `allDecisions` → **`_DueTally.add(decision, state, …)` per iteration**.
* Lines 589-654: Build `DueCountsSummary` from tallies → **`_DueTally.toSummary(…)`**.

After extraction `getDueSummary` becomes ~30 lines: queries, `_DueTally()`,
`for (d in allDecisions) tally.add(d, …)`, `return tally.toSummary(…)`.

## 2. Files to read before touching anything

1. `lib/src/review/review_service.dart:401-655` — the method
2. `lib/src/review/review_service.dart:56-107` — `DueCountsSummary` (output type)
3. `lib/src/domain/repertoire_progress.dart` — `RepertoireProgress` value type
4. `test/review/review_service_test.dart:306-400` — `getDueSummary` tests
5. `test/review/review_side_scope_test.dart` — side-scope tests
6. `test/review/review_order_test.dart` — order tests (no getDueSummary, but imports service)

## 3. The fix

Extract `_DueTally` as a **private class in `review_service.dart`** (or a new
`lib/src/review/_due_tally.dart` part file). It holds all 16 containers and
exposes two methods: `add` (per-decision) and `toSummary` (builder).

### Skeleton

```dart
class _DueTally {
  _DueTally({
    required List<Study> studies,
    required Map<String, String?> chapterOpenings,
    required Map<String, Side> chapterSides,
    required Map<String, String> chapterStudyIds,
    required Set<String> activeStudyIds,
  }) {
    // Lines 415-488 move here — initialize all 16 containers
  }

  // ... all 16 containers as fields ...

  var totalDueCount = 0;
  final accountedDueCanonicalIds = <String>{};

  void add(RepertoireDecision d, ReviewState? state, DateTime now, ReviewScope scope) {
    // Lines 490-587 move here — one iteration's body
  }

  DueCountsSummary toSummary({int? remainingDailyQuota}) {
    // Lines 589-654 move here — build maps + clamp
  }
}
```

`getDueSummary` becomes:

```dart
Future<DueCountsSummary> getDueSummary({...}) async {
  final activeStudyIds = studies.where((s) => s.isActive).map((s) => s.id).toSet();
  final chapterOpenings = await repository.getChapterOpenings();
  final chapterSides = await repository.getChapterOrientations();
  final chapterStudyIds = await repository.getChapterStudyIds();
  final allDecisions = await repository.getAllDecisions();
  final reviewStates = /* targeted or full load */;
  final now = clock.now();

  final tally = _DueTally(
    studies: studies,
    chapterOpenings: chapterOpenings,
    chapterSides: chapterSides,
    chapterStudyIds: chapterStudyIds,
    activeStudyIds: activeStudyIds,
  );

  for (final d in allDecisions) {
    final state = reviewStates[d.canonicalId] ?? reviewStates[d.id];
    tally.add(d, state, now, scope);
  }

  return tally.toSummary(remainingDailyQuota: remainingDailyQuota);
}
```

### What NOT to change

* Do not change the **logic** of any counter — only move it. The single-pass structure
  is preserved inside `_DueTally.add`. If the output of `getDueSummary` changes for
  any input, the refactor is wrong.
* Do not change `DueCountsSummary` — it is the public output type.
* Do not change `startSession` or `submitMove`.
* Do not touch `SPEC.md`, `GATES.md`, `.gates/`, `pubspec.yaml`.
* If PERF-FIX-21 has not landed, keep `getAllReviewStates()` as-is — this brief
  moves code, it does not change the query.

## 4. Verification

```bash
git worktree add ../chesssrs-refactor-fix-23 -b fix/refactor-fix-23-due-tally origin/main
cd ../chesssrs-refactor-fix-23
fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs

# Must be bit-for-bit equivalent output:
fvm flutter test test/review/review_service_test.dart --plain-name 'getDueSummary'
fvm flutter test test/review/review_service_test.dart
fvm flutter test test/review/review_side_scope_test.dart

fvm flutter analyze

git add lib/src/review/review_service.dart
git commit -m "refactor(review): extract _DueTally from getDueSummary's 255-line loop"
./scripts/gates.sh t1
git push -u origin fix/refactor-fix-23-due-tally
gh pr create -R cassandre60/ChessSRS --title "refactor(review): extract _DueTally from getDueSummary" --body "Closes REFACTOR-FIX-23."
```

## 5. Done when

* [ ] `getDueSummary` is ≤40 lines; tally logic lives in `_DueTally`
* [ ] All `getDueSummary` + side-scope tests pass unchanged (behaviour-preserving)
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green (G08: no test weakening)
* [ ] PR open against `cassandre60/ChessSRS`
