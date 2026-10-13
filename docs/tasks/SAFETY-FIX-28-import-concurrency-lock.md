# SAFETY-FIX-28 — Concurrent imports silently overwrite via ConflictAlgorithm.replace

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

Import has no service- or repository-level concurrency guard:

* `lib/src/view/review/repertoire_import_dialog.dart:73` — `_isImporting` is a
  **UI-only** boolean. It disables the button within one dialog instance, but
  nothing stops two imports running concurrently if they arrive via different
  paths (e.g. file pick + paste, or the dialog re-opened while a previous
  isolate import still writes).
* `lib/src/persistence/sqlite_study_repository.dart` `saveImportResult` uses
  `ConflictAlgorithm.replace` (line ~35). If two concurrent imports target the
  same study id (same PGN hash), the second write **silently overwrites** the
  first — including wiping and re-inserting decisions. If the two imports used
  different `repertoireSide` values, the user ends up with a mixed/corrupted
  study where the study row says "white" but some decisions were written by the
  "black" pass.

Worst case: user's first import is mid-write when the second completes; the
final state is a torn study (partial decisions from import A, study row from
import B).

## 2. Files to read before touching anything

1. `lib/src/persistence/sqlite_study_repository.dart:20-120` — `saveImportResult`
   and its `ConflictAlgorithm.replace` usage
2. `lib/src/view/review/repertoire_import_dialog.dart:60-260` — `_isImporting`,
   `_handlePgnImport`, `_pickPgnFile`
3. `lib/src/import/pgn_importer.dart:210-370` — `importPgn` / `importPgnAsync`
   entry points
4. `lib/src/review/review_controller.dart` — check who calls `saveImportResult`
   (is there a provider-level path beyond the dialog?)
5. `test/persistence/sqlite_study_repository_test.dart` — import persistence tests

## 3. The fix

### 3.1 Repository-level import lock

Add an in-memory mutex to `SqliteStudyRepository` so concurrent
`saveImportResult` calls serialize instead of racing:

```dart
// In SqliteStudyRepository class:
Future<void> _importLock = Future.value();

@override
Future<void> saveImportResult(ImportResult result) async {
  final completer = Completer<void>();
  final previous = _importLock;
  _importLock = completer.future;
  await previous; // wait for any in-flight import to finish
  try {
    // ... existing saveImportResult body, unchanged ...
  } finally {
    completer.complete();
  }
}
```

This is a simple FIFO chain: each import waits for the previous one's writes
to finish before starting its own. No `package:synchronized` dependency needed.

### 3.2 Duplicate-in-flight detection (optional but cheap)

Inside `saveImportResult`, after the lock is acquired, check whether a study
with the same `pgnHash` already exists **and** has a full decision set:

```dart
final existing = await _db.query(
  kTableStudy,
  where: 'pgnHash = ?',
  whereArgs: [result.study.pgnHash],
);
if (existing.isNotEmpty) {
  // Study already imported — do not overwrite.
  // The dedupe check in the UI should have caught this, but this is the
  // last line of defense against the race.
  return;
}
```

Check how `saveImportResult` currently handles the "study already exists" case
(read the body first) — if it already checks, the lock alone is sufficient and
this step is a no-op. Adapt to what the code actually does.

### 3.3 What NOT to change

* Do not change the UI `_isImporting` flag — it stays as UX polish.
* Do not change `importPgn` / `importPgnAsync` parsing — the fix is at the
  write layer only.
* Do not introduce `package:synchronized` or any new dependency.
* Do not touch `SPEC.md`, `GATES.md`, `.gates/`, `pubspec.yaml`.

## 4. Verification

```bash
git worktree add ../chesssrs-safety-fix-28 -b fix/safety-fix-28-import-lock origin/main
cd ../chesssrs-safety-fix-28
fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs
```

**RED test** — add to `test/persistence/sqlite_study_repository_test.dart`:

```dart
test('concurrent saveImportResult calls serialize (no interleaved writes)', () async {
  final resultA = makeImportResult(id: 'a', pgnHash: 'hashA');
  final resultB = makeImportResult(id: 'b', pgnHash: 'hashB');
  // Fire both without awaiting the first.
  final futureA = repo.saveImportResult(resultA);
  final futureB = repo.saveImportResult(resultB);
  await Future.wait([futureA, futureB]);
  // Both studies must be fully written — no torn state.
  final studies = await repo.getStudies();
  expect(studies.map((s) => s.id), containsAll(['a', 'b']));
});
```

Run it, then implement the lock, run again (GREEN). The test as written may
already pass (SQLite serializes within one connection), but it locks in the
contract.

```bash
fvm flutter test test/persistence/sqlite_study_repository_test.dart --plain-name 'concurrent saveImportResult'
fvm flutter test test/persistence/sqlite_study_repository_test.dart
fvm flutter analyze

git add lib/src/persistence/sqlite_study_repository.dart test/persistence/sqlite_study_repository_test.dart
git commit -m "fix(persistence): serialize concurrent imports with in-memory lock"
./scripts/gates.sh t1
git push -u origin fix/safety-fix-28-import-lock
gh pr create -R cassandre60/ChessSRS --title "fix(persistence): serialize concurrent imports with in-memory lock" --body "Closes SAFETY-FIX-28."
```

## 5. Done when

* [ ] `SqliteStudyRepository` has a FIFO lock serializing `saveImportResult`
* [ ] New concurrency test exists and passes
* [ ] Existing persistence tests pass unchanged
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green
* [ ] PR open against `cassandre60/ChessSRS`

## 6. Sequencing note

Persistence lane: `07 → 14 → 13 → 08 → 15 → 16 → 26 → 28`. Rebase on `main`
if any earlier lane member landed.
