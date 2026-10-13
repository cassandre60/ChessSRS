# REVIEW-FIX-01 — Scope mismatch: summary counts one scope, session built for another

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

`ReviewController._loadState` (`lib/src/review/review_controller.dart:414-533`)
does two things that must agree on which scope they use, but they disagree:

```dart
// line ~431-438  — counts dues
final effectiveScope = studies.isEmpty
    ? scope
    : _resolveInitialScope(scope, await _repository.getChapterOrientations());

final summary = await _service.getDueSummary(
  studies: studies,
  scope: effectiveScope,          // ← resolved: all() → White or Black
  remainingDailyQuota: remainingQuota,
);

// ... 20 lines later, line ~461-466  — builds the review queue
final session = await _service.startSession(
  scope: scope,                   // ← BUG: original, unresolved all()
  mode: mode,
  remainingDailyQuota: remainingQuota,
  generation: generation,
);
```

`_resolveInitialScope` collapses a bare `all()` into `White` or `Black` based on
chapter orientations, so the user never sees an empty drawer. The summary is
computed for that collapsed scope; the session is built for the original one.

**User-visible symptom**: top bar says `N due` (from `summary`) but board shows
`Nothing due` / `currentPrompt == null` (from the session), or the queue contains
the wrong side's positions. Triggers whenever `White and Black orientation chapters`
coexist and neither drawer is selected — the common import default (`White`) plus a
flipped repertoire makes it routine.

## 2. Files to read before touching anything

1. `lib/src/review/review_controller.dart` — the bug is here
2. `lib/src/domain/review/review_scope.dart` — `ReviewScope`, `matches()`, side semantics
3. `lib/src/domain/review/review_session.dart` — how `scope.matches()` filters decisions
4. `lib/src/review/review_service.dart` — `getDueSummary` and `startSession` (both take a scope)
5. `test/review/review_controller_test.dart` — existing controller tests
6. `test/review/review_service_test.dart` — service tests, if you need scope fixtures

## 3. The fix

**One-line semantic change**: pass `effectiveScope` to `startSession` as well.

```dart
final session = await _service.startSession(
  scope: effectiveScope,   // was: scope
  mode: mode,
  remainingDailyQuota: remainingQuota,
  generation: generation,
);
```

That is the whole bug. No other file changes. Do not also change the two earlier
`scope` reads in the `orientation` fallback (lines ~489-499) — they deliberately
try `effectiveScope.chapterId/studyId` first, then fall back to chapter lookup,
which is correct: when `effectiveScope` is a side scope it has no chapter/study,
so the fallback finds the right orientation from the prompt.

### What else to check

* `toggleStudyActive`, `deleteStudy`, `reload` etc. already use `currentState.scope`
  directly (no `_resolveInitialScope` path) — out of scope.
* `build()` also calls `_loadState(scope: const ReviewScope.all())` — same path, so
  the same fix covers startup.
* Leave the `studies.isEmpty ? scope : effectiveScope` guard as-is: when there are
  no studies there is no orientation to resolve to.

## 4. How to make the work verifiable (no guessing)

### 4.1 Worktree setup — required

Generated files are gitignored. Every task starts the same:

```bash
git worktree add ../chesssrs-review-fix-01 -b fix/review-fix-01-scope-mismatch origin/main
cd ../chesssrs-review-fix-01
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze   # must be 0 issues before you start
```

Branch name is `fix/review-fix-01-scope-mismatch`. Not `agent1/...`.

### 4.2 Failing test first — RED

Add a test that fails on the current code and passes after the fix. Place it in
`test/review/review_controller_test.dart` (or a new
`test/review/review_scope_mismatch_test.dart` if the file is too noisy).

**Scenario** (adapt to the helpers the file already provides):

* Create two studies, one with a `White` chapter and one with a `Black` chapter
  (use `Chapter.copyWith(orientation: Side.black)` and matching decisions — see
  `review_service_test.dart` for fixtures).
* Call `controller.build()` or `changeScope(const ReviewScope.all())` with those
  studies in the repository.
* Assert that `state.value.totalDueCount` and `state.value.session.currentPrompt`
  agree: both zero, or both non-zero and the prompt's chapter orientation matches
  `state.value.scope.side` / `state.value.studyIdsBySide` membership. Before the
  fix they disagree (non-zero total but null prompt, or prompt from the wrong side).

The test must cite the invariant:
```dart
// SPEC INV-031: effective scope must be used consistently for summary and session.
// (and INV-066/INV-030 for oriented scopes — pick the one that matches.)
```

Run only this test at first (budget: one test, not the file):

```bash
fvm flutter test test/review/review_controller_test.dart --plain-name 'scope mismatch shows same due'
```

It must **fail** before your edit (stashed), **pass** after.

### 4.3 Implement the fix — GREEN

Edit `lib/src/review/review_controller.dart:461` — change `scope:` to `effectiveScope:`.

### 4.4 Verify

```bash
# 1. The one test (again)
fvm flutter test test/review/review_controller_test.dart --plain-name 'scope mismatch shows same due'

# 2. The whole file, once
fvm flutter test test/review/review_controller_test.dart

# 3. Fail-on-old-code: prove the test is not vacuous
git stash && fvm flutter test test/review/review_controller_test.dart --plain-name 'scope mismatch shows same due'
# must fail here
git stash pop

# 4. Lints on touched files, once
fvm flutter analyze

# 5. Commit, then gates — gates read committed diff, not working tree
git add lib/src/review/review_controller.dart test/review/review_controller_test.dart
git commit -m "fix(review): use effective scope for session as well as summary

Scope mismatch caused due counts and session queue to disagree
when all() resolved to White/Black."
./scripts/gates.sh t1   # BASE_REF defaults to origin/main; must be green
```

### 4.5 Push & PR

```bash
git push -u origin fix/review-fix-01-scope-mismatch
gh pr create -R cassandre60/ChessSRS --title "fix(review): use effective scope for session as well as summary" --body "Closes REVIEW-FIX-01. See docs/tasks/REVIEW-FIX-01-scope-mismatch.md."
```

## 5. Constraints

* Do not edit `SPEC.md`, `GATES.md`, `QUALITY.md`, `TEST_STRATEGY.md`, `AGENTS.md`,
  `pubspec.yaml`, `analysis_options.yaml`, `.gates/`, `scripts/gates/`, `.github/`.
* One fix per PR. No drive-by refactors.
* Never run the full suite locally as a safety net — CI runs it per push. Budget is
  targeted tests only (`AGENTS.md` §3.1). Full suite is a pre-push gate if needed,
  not an inner-loop step.
* Do not attempt a local release build (`flutter build appbundle` OOMs the machine).

## 6. Done when

* [ ] Failing test added, verified to fail on old code and pass on new code
* [ ] `fvm flutter analyze` 0 issues on touched files
* [ ] `./scripts/gates.sh t1` green on the committed branch
* [ ] PR open against `cassandre60/ChessSRS`
