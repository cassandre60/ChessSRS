# ARCH-FIX-05 — Presentation imports DB/persistence directly (QUALITY.md §1.1 violations)

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

`QUALITY.md §1.1` says presentation (`view/`) must talk to application providers
only — never to `db/` or `persistence/` directly. Three screens currently violate
this:

| Screen | Direct import | Usage |
|--------|---------------|-------|
| `lib/src/view/settings/srs_settings_screen.dart:7` | `import 'package:chess_srs/src/db/database.dart'` | line 70: `ref.watch(getDbSizeInBytesProvider)` |
| `lib/src/view/review/study_chapters_screen.dart:9` | `import 'package:chess_srs/src/persistence/study_repository.dart'` | lines 46, 93, 176: `repo.getStudy`, `repo.getChaptersByStudy`, `repo.getPositionTree`, `repo.getStudy` |
| `lib/src/view/analysis/analysis_hub_screen.dart:9` | `import 'package:chess_srs/src/persistence/persistence.dart'` | lines 175, 189-191: `repo.getChaptersByStudy`, `ref.watch(srsStudyRepositoryProvider)` inside `_studiesProvider` + sheet |

`docs/tech-debt-inventory.md` item 14 logs these as tracked debt (boundary erosion).
They are not hypothetical — `ARCHITECTURE.md` §8 lists them as the three known
exceptions to the otherwise inward-only dependency rule.

**Why it hurts**: presentation now depends on SQLite API shape — mocking requires
faking the whole `StudyRepository`, and a schema migration touching those 3 queries
touches 3 screens plus a service. The application layer (`review/`) already exists
to own these queries; the screens should watch *it*.

## 2. Files to read before touching anything

1. `lib/src/view/settings/srs_settings_screen.dart:1-75, 524-564` — the `getDbSizeInBytesProvider` usage
2. `lib/src/view/review/study_chapters_screen.dart:1-120` — `openStudyExplorer`, `openChapterAnalysis`, widget build
3. `lib/src/view/analysis/analysis_hub_screen.dart:1-192` — `_studiesProvider`, `_pickStudyToBrowse`
4. `lib/src/db/database.dart:78-86` — `getDbSizeInBytesProvider` definition (currently a `FutureProvider<int>` watching `databaseProvider`)
5. `lib/src/review/review_service.dart` / `lib/src/review/review_controller.dart` — where application providers live; `reviewControllerProvider` already surfaces studies/chapters
6. `lib/src/persistence/study_repository.dart` — `StudyRepository` contract, `srsStudyRepositoryProvider`
7. `ARCHITECTURE.md` §2, §8 + `QUALITY.md` §1.1` — the invariant being restored
8. `test/view/review/study_chapters_screen_test.dart` (if exists) + `test/view/settings/*` — screen tests to keep green
9. `test/review/review_controller_test.dart` — shows how controllers are mocked (HTTP-layer mocking, not provider overrides where possible)

## 3. The fix

Move the three reads behind application-layer providers. No screen should import
`db/` or `persistence/` after this patch.

### 3.1 Screen 1 — `srs_settings_screen.dart` DB size

`getDbSizeInBytesProvider` (in `db/database.dart`) is itself a provider that
opens the DB file to measure its size. Its only consumer is this screen.
Lift it (or wrap it) via the application layer:

* Option A (minimal diff): keep `getDbSizeInBytesProvider` where it is, but have
  `review_service.dart` (or a new `lib/src/review/srs_settings_providers.dart`)
  re-export it as `srsDbSizeProvider` and let the screen watch *that* alias.
  The screen then imports `review/review_service.dart` (or the new file), not `db/database.dart`.
  This is a one-import swap plus removing `import '.../db/database.dart'`.

* Option B (cleaner): move the `FutureProvider` definition itself into
  `lib/src/review/review_service.dart` or a dedicated `lib/src/review/db_providers.dart`
  and delete the import from the screen. Same effect; B is preferred if the file is tiny.

Pick one; either restores the layering. Do not duplicate the provider — have one
source of truth and one import from view.

### 3.2 Screens 2 & 3 — studies/chapters for the explorer

`openStudyExplorer` / `openChapterAnalysis` / `_pickStudyToBrowse` / `_studiesProvider`
all fetch `Study`/`Chapter`/`PositionTree` for navigation. These are read-only
lookups with no review semantics, but they still cross the persistence boundary.

Create two application-layer helpers (names are suggestions — match existing naming):

```dart
// lib/src/review/review_service.dart  (or a new lib/src/review/study_browser_providers.dart)

/// Lists studies for the picker — replaces direct srsStudyRepositoryProvider reads in view.
final studyListProvider = FutureProvider.autoDispose<List<Study>>((ref) async {
  final repo = await ref.watch(srsStudyRepositoryProvider.future);
  return repo.getAllStudies();
});

/// Chapters for a study — replaces getChaptersByStudy calls in view.
final studyChaptersProvider = FutureProvider.autoDispose.family<List<Chapter>, String>((ref, studyId) async {
  final repo = await ref.watch(srsStudyRepositoryProvider.future);
  return repo.getChaptersByStudy(studyId);
});

/// A hydrated chapter (with tree) for analysis navigation.
Future<Chapter> hydratedChapterProvider(Ref ref, Chapter chapter) async {
  if (chapter.root != null) return chapter;
  final repo = await ref.read(srsStudyRepositoryProvider.future);
  final root = await repo.getPositionTree(chapter.id);
  return chapter.copyWith(root: root);
}
```

Then update call sites:

* `study_chapters_screen.dart`: replace `await ref.read(srsStudyRepositoryProvider.future)` +
  `repo.getStudy/getChaptersByStudy/getPositionTree` with the new providers / helper.
  The widget `build` already has `Study`/`chapters` passed in — only the two top-level
  functions need changing.
* `analysis_hub_screen.dart`: replace `_studiesProvider` body from
  `ref.watch(srsStudyRepositoryProvider.future) + repo.getAllStudies()` to
  `ref.watch(studyListProvider.future)` (or delegate entirely to the new provider and
  delete `_studiesProvider`). Replace `_pickStudyToBrowse`'s `repo.getChaptersByStudy`
  with `studyChaptersProvider` or the helper.

After:
* `srs_settings_screen.dart` imports no `db/` provider.
* `study_chapters_screen.dart` and `analysis_hub_screen.dart` import no `persistence/` provider.
* Verify with a grep before you claim done:

```bash
rg -n "from.*persistence|from.*db/database" lib/src/view/settings/srs_settings_screen.dart lib/src/view/review/study_chapters_screen.dart lib/src/view/analysis/analysis_hub_screen.dart
# must print nothing
```

### 3.3 What NOT to change

* Do not change the `StudyRepository` contract — this is a consumer move, not a repository redesign.
* Do not introduce a new package dependency.
* Do not touch `SPEC.md`, `GATES.md`, `QUALITY.md`, `AGENTS.md`, `pubspec.yaml`, `.gates/`, `.github/`.
* `review/review_controller.dart` already imports both repositories legitimately
  (application layer may import persistence) — leave it.
* Keep FVM pinned (see `AGENTS.md` §4); no `flutter build appbundle`.

## 4. How to make the work verifiable (no guessing)

### 4.1 Worktree setup — required

```bash
git worktree add ../chesssrs-arch-fix-05 -b fix/arch-fix-05-db-boundary origin/main
cd ../chesssrs-arch-fix-05
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze   # 0 issues before you start
```

Branch name is `fix/arch-fix-05-db-boundary`. Not `agent1/...`.

### 4.2 Tests first

No failing-test invention required for a layering move, but prove no behavior change:

1. Before the edit, run the three screens' tests (if present) and a representative
   controller test to capture the baseline — each individually:

```bash
fvm flutter test test/view/review/study_chapters_screen_test.dart --plain-name 'opens explorer'  # or the real name
```

2. After the edit, the same tests must still pass and no new `flutter analyze`
   warnings appear on the touched files. This is a refactor — G08 expects
   "no test files modified + behaviour-equivalence evidence". Keep tests intact.

### 4.3 Verify

```bash
# 1. Grep the boundary — must be clean
rg -n "from.*persistence|from.*db/database" lib/src/view/settings/srs_settings_screen.dart lib/src/view/review/study_chapters_screen.dart lib/src/view/analysis/analysis_hub_screen.dart
# prints nothing

# 2. Targeted analyze on touched files, once
fvm flutter analyze

# 3. One targeted screen test file (the one you changed most), then stop — full suite is CI's job
fvm flutter test test/view/review/study_chapters_screen_test.dart

# 4. Commit, then gates — gates read committed diff, not working tree
git add lib/src/view/settings/srs_settings_screen.dart lib/src/view/review/study_chapters_screen.dart lib/src/view/analysis/analysis_hub_screen.dart lib/src/review/review_service.dart
git commit -m "refactor(view): move study/DB reads behind application providers

Presentation no longer imports db/persistence directly (QUALITY.md §1.1).
Covers srs_settings_screen (db size), study_chapters_screen and
analysis_hub_screen (study/chapter lookups).

Harness: OpenCode
Model: cleanapis/claude-fable-5.1"
./scripts/gates.sh t1   # must be green (especially G03 banned APIs, G07 protected paths, G08 no test weakening)
```

A pre-commit `./scripts/gates.sh t1` is worthless — the diff gates read `origin/main...HEAD`
on committed history (see `AGENTS.md` Lesson 2026-10-07). Run after committing.

### 4.4 Push & PR

```bash
git push -u origin fix/arch-fix-05-db-boundary
gh pr create -R cassandre60/ChessSRS --title "refactor(view): move study/DB reads behind application providers" --body "Closes ARCH-FIX-05. See docs/tasks/ARCH-FIX-05-presentation-db-boundary.md.

---
Harness: OpenCode
Model: cleanapis/claude-fable-5.1"
```

## 5. Done when

* [ ] No `lib/src/view/**/srs_settings_screen.dart|study_chapters_screen.dart|analysis_hub_screen.dart` imports `db/` or `persistence/`
* [ ] All three screens build via application-layer providers; behavior unchanged
* [ ] `fvm flutter analyze` 0 issues on touched files
* [ ] `./scripts/gates.sh t1` green on the committed branch (G03/G07/G08)
* [ ] PR open against `cassandre60/ChessSRS`
