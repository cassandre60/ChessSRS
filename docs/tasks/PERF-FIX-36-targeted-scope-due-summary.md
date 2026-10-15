# PERF-FIX-36 — Avoid full library re-summarisation on scope changes

## 1. Why this is a brief at all

When a user interacts with the Review screen, they frequently change scopes:
- Switching between White and Black drawers (`selectSide`)
- Filtering to a specific study from the drawer
- Filtering to a specific opening family

In `ReviewController`:
```dart
Future<void> changeScope(ReviewScope scope) => _loadAndPublish(scope, ReviewMode.srs);
```
`_loadAndPublish` calls `_service.startSessionAndSummary(...)`, which:
1. Reloads all 31,182 decisions from the database.
2. Re-queries all review states.
3. Re-runs `_DueTally` across the entire database to compute `studyProgress`,
   `chapterProgress`, `openingProgress`, `sideProgress`, and `totalDueCount`.

### The waste
When changing from the White drawer to a study within White (or between drawers),
**no moves were answered and no study data changed**.
- The `studyProgress`, `chapterProgress`, `openingProgress`, and `studyDueCounts`
  are **identical** to what was already computed.
- Only `totalDueCount` (the number of due cards matching the new scope) changes!
- Re-reading 31,182 rows and re-aggregating the entire library on every tap
  causes a noticeable ~500 ms frame hitch when simply selecting a study or
  switching drawer tabs.

## 2. Read before touching anything

1. `lib/src/review/review_controller.dart` — `_loadAndPublish`, `changeScope`,
   `selectSide`.
2. `lib/src/review/review_service.dart` — `getDueSummary`, `startSession`,
   `_DueTally`.
3. SPEC **INV-030**:
   > Scopes filter exactly.
4. SPEC **INV-032**:
   > Stale sessions never take over.

## 3. Implementation Strategy

### Strategy A: Scoped Due Count Derivation from Existing Summary
If `ReviewController` already holds a valid, up-to-date `DueCountsSummary` from
the current session, and only `scope` is changing (no answer submitted, no
study active/pause toggled):
- For `ReviewScope.study(id)`: `dueCount = summary.studyDueCounts[id] ?? 0`!
- For `ReviewScope.opening(name)`: `dueCount = summary.openingDueCounts[name] ?? 0`!
- For `ReviewScope.side(s)`: `dueCount = summary.dueCountForSide(s)`!

Notice that `DueCountsSummary` **already contains** the due counts for every
study, opening, and side!
When switching to a study scope:
Starting the session for that study only needs to load the decisions and states
for that *single study* via `ReviewService.startSession(scope: scope)`. It does
**not** need to re-run `getDueSummary()` over all 31,182 decisions in the
library!

### Strategy B: Cache or Invalidate Summary on Mutations
Only invalidate and re-run full library `getDueSummary()` when:
1. A move is submitted (`submitMove`) and the queue changes.
2. A study is toggled active/inactive (`toggleStudyActive`).
3. A study is deleted (`deleteStudy`).
4. Material is imported.

On pure scope navigation (`changeScope`, `selectSide`), reuse the existing
`DueCountsSummary`, only updating `totalDueCount` and launching the scoped
`startSession(scope: scope)`.

## 4. Verification Steps

1. Verify scope changes still report the exact same due counts:
   - All tests in `test/review/review_controller_test.dart` must pass:
     ```bash
     fvm flutter test test/review/review_controller_test.dart
     ```
2. Verify side scope tests:
   ```bash
   fvm flutter test test/review/review_side_scope_test.dart
   ```
3. Runtime validation (`fvm flutter run -d linux`):
   - Switch between White and Black tabs in the drawer.
   - Tap into a study from the drawer.
   - Observe that the transition is instantaneous without the 500 ms hitch.

## 5. What counts as done

- `changeScope` does not re-query or re-aggregate the whole 31k-decision database.
- Tapping a study in the drawer loads only that study's session.
- All existing tests in `review_controller_test.dart` and `review_side_scope_test.dart` pass.
- `./scripts/gates.sh t1` passes.
