# ARCH-FIX-06 — Triplicated scope branch setup in ReviewService.startSession

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

`ReviewService.startSession` (`lib/src/review/review_service.dart:157-224`) loads
studies/chapters/decisions for the active `ReviewScope`. Four of the five scope
branches repeat the same prologue:

```dart
} else if (scope.openingFamily != null) {
  final allStudies = await repository.getAllStudies();          // ← repeat
  final activeStudies = allStudies.where((s) => s.isActive).toList();
  final chapterOpenings = await repository.getChapterOpenings();
  // ... then filter chapters ...
} else if (scope.side != null) {
  final allStudies = await repository.getAllStudies();          // ← repeat
  final activeStudies = allStudies.where((s) => s.isActive).toList();
  // ... different filter, same prologue ...
} else {
  final allStudies = await repository.getAllStudies();          // ← repeat
  final activeStudies = allStudies.where((s) => s.isActive).toList();
  // ... loop getChaptersByStudy per active study ...
}
```

Three copies of `getAllStudies → filter isActive → loop getChaptersByStudy per active study`
plus two of them also fetch `getChapterOpenings` with near-identical filtering.
`docs/tech-debt-inventory.md` item 9 tracks this as triplicated setup. The risk is
not perf but *drift*: the `isActive` filter, the per-study chapter loop, and the
`openingFamily.trim()` normalisation each exist in three places and must stay in sync
when any of them changes (e.g. a new `archivedAt` filter).

Also: `_getOpeningDecisions` and `_getSideDecisions` then do a second full
`getAllDecisions()` + in-memory filter — the whole flow issues multiple full-table
reads that could be collapsed, but this task deduplicates the *setup* prologue only.
The full query consolidation is separate work.

## 2. Files to read before touching anything

1. `lib/src/review/review_service.dart:157-232` (+ helpers `657-688`) — the triplication
2. `lib/src/domain/review/review_scope.dart` — scope branches, `matches()` semantics
3. `lib/src/domain/review/review_scope.dart` + `lib/src/persistence/study_repository.dart` — `getActiveStudies` already exists alongside `getAllStudies`
4. `test/review/review_service_test.dart` — service tests, scope fixtures (950 lines per tech-debt note)
5. `test/review/review_side_scope_test.dart`, `test/review/review_order_test.dart` — side/order tests if they cover startSession
6. `AGENTS.md` §3.1 — local test budget (targeted only, CI runs the full suite)

## 3. The fix

Extract a small private helper that encapsulates the repeated prologue. Keep the
change narrow — no record return types or new public API unless needed.

### Recommended helper shape

```dart
// lib/src/review/review_service.dart — private helper, near startSession

/// Loads active studies and their chapters, optionally filtered.
Future<({List<Study> activeStudies, List<Chapter> chapters})> _loadActiveStudiesAndChapters({
  bool Function(Chapter)? chapterWhere,
  Future<Map<String, String?>> Function()? openingsLookup, // unused in most scopes — fetch lazily
}) async {
  final allStudies = await repository.getAllStudies();
  final activeStudies = allStudies.where((s) => s.isActive).toList();
  // Alternative that avoids fetching inactive studies at all:
  //   final activeStudies = await repository.getActiveStudies();
  // Either is fine; prefer the one that avoids a second in-memory filter and
  // matches the repo's indexed query. If you switch, update all call sites to
  // stop re-filtering. The current code fetches ALL then filters — that is the
  // drift source.

  final chapters = <Chapter>[];
  for (final s in activeStudies) {
    final studyChapters = await repository.getChaptersByStudy(s.id);
    chapters.addAll(chapterWhere == null ? studyChapters : studyChapters.where(chapterWhere));
  }
  return (activeStudies: activeStudies, chapters: chapters);
}
```

Then `startSession` branches become small specialisations:

```dart
} else if (scope.openingFamily != null) {
  final chapterOpenings = await repository.getChapterOpenings();
  final wantedIds = chapterOpenings.entries
      .where((e) => e.value?.trim() == scope.openingFamily!.trim())
      .map((e) => e.key).toSet();
  final loaded = await _loadActiveStudiesAndChapters(chapterWhere: (c) => wantedIds.contains(c.id));
  targetStudies = loaded.activeStudies;
  targetChapters = loaded.chapters;
  decisions = await _getOpeningDecisions(targetChapters, scope.openingFamily!, loaded.activeStudies);
} else if (scope.side != null) {
  final loaded = await _loadActiveStudiesAndChapters(chapterWhere: (c) => c.orientation == scope.side);
  targetStudies = loaded.activeStudies;
  targetChapters = loaded.chapters;
  decisions = await _getSideDecisions(targetChapters);
} else {
  final loaded = await _loadActiveStudiesAndChapters();
  targetStudies = await repository.getAllStudies(); // keep returning ALL studies (even inactive) for the session header — check current behavior!
  targetChapters = loaded.chapters;
  decisions = await _getActiveDecisions(loaded.activeStudies);
}
```

**Important subtleties to preserve** (do not simplify incorrectly):

* `targetStudies` for the `side` and `all()` branches: current code sets
  `targetStudies = activeStudies` for `side` but `targetStudies = allStudies`
  (including inactive) for `all()` — `allStudies` is passed to the `ReviewSession`
  constructor for the drawer's header/progress counts, so the `all()` branch must
  keep `allStudies` even though chapters are only from active ones. Verify before
  changing — read `ReviewSession` constructor and `DueCountsSummary` callers.
* `isActive` filtering: if you switch to `getActiveStudies()`, `targetStudies` for
  `all()` needs the unfiltered list too — fetch both or keep `getAllStudies()` and
  filter in memory. The win is deduplicating the chapter loop, not saving one query.
* `openingFamily.trim()` — must stay trimmed at both ends; current code trims the
  stored opening and the scope value.

Do NOT change `_getActiveDecisions` / `_getSideDecisions` / `_getOpeningDecisions`
in this PR — they are the next refactor, not this one.

### What NOT to change

* Do not introduce `record` return types if `AGENTS.md` or the codebase avoids them
  — the note in `tech-debt-inventory.md` item 9 flags that no `lib/` file uses
  records yet. A small private class `class _ActiveLoad { final List<Study> activeStudies; ... }`
  is fine instead.
* Do not add `pubspec.yaml`, `SPEC.md`, `GATES.md`, protected-path edits.
* Do not change `StudyRepository` contract.

## 4. How to make the work verifiable (no guessing)

### 4.1 Worktree setup — required

```bash
git worktree add ../chesssrs-arch-fix-06 -b fix/arch-fix-06-scope-dedupe origin/main
cd ../chesssrs-arch-fix-06
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze
```

Branch name is `fix/arch-fix-06-scope-dedupe`.

### 4.2 Failing test? Not required — prove equivalence

This is a duplication collapse; behavior is *supposed* to be identical. Prove it
by showing existing tests still pass without modification (G08: no test weakening).

Run the service tests that already cover these branches:

```bash
fvm flutter test test/review/review_service_test.dart --plain-name 'side scope'
fvm flutter test test/review/review_service_test.dart --plain-name 'opening scope'
fvm flutter test test/review/review_service_test.dart --plain-name 'all scope'
# Use the real --plain-name values from that file — list with:
# fvm flutter test test/review/review_service_test.dart --plain-name '' 2>&1 | rg "^\s+[✓✗]"
```

Or run the whole file once at the end:

```bash
fvm flutter test test/review/review_service_test.dart
```

The key mutants to keep green: `review_side_scope_test.dart` and `review_order_test.dart`
if they exercise `startSession`.

### 4.3 Implement the fix — GREEN

Edit only `lib/src/review/review_service.dart`.

### 4.4 Verify

```bash
# 1. Whole service test file, once
fvm flutter test test/review/review_service_test.dart

# 2. Lints on touched file, once
fvm flutter analyze

# 3. Commit, then gates — must be green (especially G08: no assertions removed)
git add lib/src/review/review_service.dart
git commit -m "refactor(review): collapse triplicated scope setup in startSession

Three scope branches repeated getAllStudies → filter isActive → loop
getChaptersByStudy with identical shape. Extract helper so the active
filter and chapter loop have one source of truth.

Harness: OpenCode
Model: cleanapis/claude-fable-5.1"
./scripts/gates.sh t1

# 4. Fail-on-old-code sanity: stash, rerun one scope test, pop — it still passes
# (we are proving we did not break semantics, not that a new test fails)
```

### 4.5 Push & PR

```bash
git push -u origin fix/arch-fix-06-scope-dedupe
gh pr create -R cassandre60/ChessSRS --title "refactor(review): collapse triplicated scope setup in startSession" --body "Closes ARCH-FIX-06. See docs/tasks/ARCH-FIX-06-scope-setup-dedupe.md.

---
Harness: OpenCode
Model: cleanapis/claude-fable-5.1"
```

## 5. Done when

* [ ] Helper extracts the repeated `activeStudies + chapters(where)` prologue
* [ ] `openingFamily`, `side`, and `all` branches no longer each contain their own loop
* [ ] Existing `test/review/review_service_test.dart` (+ side/order tests) pass unchanged
* [ ] `fvm flutter analyze` 0 issues on touched files
* [ ] `./scripts/gates.sh t1` green on committed branch
* [ ] PR open against `cassandre60/ChessSRS`
