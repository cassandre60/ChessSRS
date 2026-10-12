# REVIEW-FIX-04 — N+1 backfill in getStudyByPgnHash + sequential updates on import path

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

`SqliteStudyRepository.getStudyByPgnHash` (`lib/src/persistence/sqlite_study_repository.dart:87-127`)
is called by `ReviewController.importPgnText` to detect duplicate imports before
writing. When the hash is not found among indexed rows, it falls through to a
backfill for old studies whose `pgnHash IS NULL` (pre-v9 rows):

```dart
final unhashedRows = await _db.query(kTableSrsStudy, where: 'pgnHash IS NULL');
for (final row in unhashedRows) {
  final study = _studyFromRow(row);
  final chapters = await getChaptersByStudy(study.id); // ← N+1: one query per study
  if (chapters.isNotEmpty) {
    final computedHash = computeRepertoireTreeHash(chapters);
    await _db.update(                                // ← sequential write per study
      kTableSrsStudy,
      {'pgnHash': computedHash},
      where: 'id = ?',
      whereArgs: [study.id],
    );
    if (computedHash == pgnHash &&
        (forSide == null || chapters.every((c) => c.orientation == forSide))) {
      return study.copyWith(pgnHash: computedHash);
    }
  }
}
```

With 40 unhashed studies this does 40 sequential `SELECT` round-trips plus 40
sequential `UPDATE`s, all on the UI thread before `saveImportResult` can run.
On first import after upgrading from pre-v9, the user stalls.

A second, smaller N+1 is in `savePositionKnowledgeState` single-save path vs
`saveAnswerBatch` — but that is not this task. This task fixes only the backfill.

## 2. Files to read before touching anything

1. `lib/src/persistence/sqlite_study_repository.dart:87-127` — the method
2. `lib/src/persistence/srs_schema.dart` — table/col names, `kTableSrsStudy`, `kTableSrsChapter`
3. `lib/src/import/pgn_importer.dart` — `computeRepertoireTreeHash`
4. `lib/src/review/review_controller.dart` — `importPgnText` call site (duplicate check)
5. `lib/src/db/database.dart` — schema version / migrations (v9 added `pgnHash`)
6. `test/persistence/sqlite_study_repository_test.dart` or `test/persistence/*`
   — existing repository tests, `SQFliteTest` helpers, `getStudyByPgnHash` tests

## 3. The fix

Batch the backfill: fetch all unhashed studies' chapters in fewer round-trips and
write the backfilled hashes in a batch.

### Minimal correct change

```dart
Future<Study?> getStudyByPgnHash(String pgnHash, {Side? forSide}) async {
  final rows = await _db.query(
    kTableSrsStudy,
    where: forSide == null
        ? 'pgnHash = ?'
        : 'pgnHash = ? AND NOT EXISTS (SELECT 1 FROM $kTableSrsChapter c '
              'WHERE c.studyId = $kTableSrsStudy.id AND c.orientation != ?)',
    whereArgs: forSide == null ? [pgnHash] : [pgnHash, forSide.name],
    limit: 1,
  );
  if (rows.isNotEmpty) return _studyFromRow(rows.first);

  // Backfill: studies that predate the pgnHash column
  final unhashedRows = await _db.query(kTableSrsStudy, where: 'pgnHash IS NULL');
  if (unhashedRows.isEmpty) return null;

  // --- batched fetch: one query for all chapters of all unhashed studies
  final unhashedIds = unhashedRows.map((r) => r['id']! as String).toList();
  final placeholders = List.filled(unhashedIds.length, '?').join(',');
  final chapterRows = await _db.query(
    kTableSrsChapter,
    where: 'studyId IN ($placeholders)',
    whereArgs: unhashedIds,
    orderBy: 'studyId ASC, sourceOrder ASC',
  );

  // Group by studyId
  final chaptersByStudy = <String, List<Map<String, Object?>>>{};
  for (final r in chapterRows) {
    (chaptersByStudy[r['studyId']! as String] ??= []).add(r);
  }

  // --- compute hashes, batch the updates
  final batch = _db.batch();
  Study? match;
  for (final row in unhashedRows) {
    final study = _studyFromRow(row);
    final cRows = chaptersByStudy[study.id] ?? const [];
    final chapters = cRows.map(_chapterFromRow).toList();
    if (chapters.isEmpty) continue;
    final computedHash = computeRepertoireTreeHash(chapters);
    batch.update(
      kTableSrsStudy,
      {'pgnHash': computedHash},
      where: 'id = ?',
      whereArgs: [study.id],
    );
    if (match == null &&
        computedHash == pgnHash &&
        (forSide == null || chapters.every((c) => c.orientation == forSide))) {
      match = study.copyWith(pgnHash: computedHash);
    }
  }
  await batch.commit(noResult: true);
  return match;
}
```

Key points:

* One `SELECT ... WHERE studyId IN (...)` replaces N selects.
* One `Batch.commit` replaces N updates.
* Behaviour for `forSide` filtering is preserved — re-read the current condition:
  `chapters.every((c) => c.orientation == forSide)`.
* SQLite has a variable limit (999 by default) — if `unhashedIds.length > 900`,
  chunk the `IN` list the same way other repo methods chunk at 400. In practice
  there are rarely > 100 unhashed studies, so one batch is fine; chunking is
  defensive.
* Order must be `sourceOrder ASC` so `computeRepertoireTreeHash` sees chapters in
  canonical order (check what `getChaptersByStudy` orders by — reuse it).

### Alternative accepted

Doing `Future.wait(unhashedRows.map(...getChaptersByStudy...))` instead of one
`IN` query also collapses the sequential round-trips and is acceptable. The single
`IN` query is preferred because it is one round-trip not N concurrent ones.

### What NOT to change

* Do not move the backfill into a migration — it is already past the migration
  window (v9) and this is runtime remediation for rows missed by the migration.
* Do not drop the backfill entirely — old installs still have null hashes.
* Do not widen the fix to `savePositionKnowledgeState` dual writes — that is
  separate work.

## 4. How to make the work verifiable (no guessing)

### 4.1 Worktree setup — required

```bash
git worktree add ../chesssrs-review-fix-04 -b fix/review-fix-04-pgnhash-backfill origin/main
cd ../chesssrs-review-fix-04
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze
```

### 4.2 Failing-or-timing test first — RED

Add a test in `test/persistence/sqlite_study_repository_test.dart` (or a new
`test/persistence/pgnhash_backfill_test.dart`) that:

1. Inserts 10-20 studies with `pgnHash = null` each with 1-2 chapters
   (use the repo's test DB helper — see existing persistence tests).
2. Calls `getStudyByPgnHash(targetHash)` where `targetHash` matches the last study.
3. Asserts it returns the correct study and that afterwards all studies have
   non-null `pgnHash` (backfill happened).
4. Before the fix this test passes functionally but slowly — so also assert the
   operation count: if the test harness exposes query logging, or simply assert
   that the result is correct and that the method completes in bounded time.
   A simpler proof: count `SELECT` invocations by wrapping the `Database` with a
   spy that increments a counter; assert counter <= 3 (initial hash lookup,
   unhashed scan, one `IN` chapters fetch) rather than `1 + 2*N`.

Minimal passing assertion (works even without a spy):

```dart
// SPEC INV-014 / DSR Architecture: pgnHash backfill is batched, not N+1.
// With N unhashed studies, the backfill must not issue N sequential fetches.
```

Run targeted:

```bash
fvm flutter test test/persistence/sqlite_study_repository_test.dart --plain-name 'backfill is batched'
```

Prove it fails on old code if you use a call-count assertion (stash + rerun).
If you only assert correctness, at least demonstrate the before/after query
count in the commit description / PR body with a logged count.

### 4.3 Implement the fix — GREEN

Edit `lib/src/persistence/sqlite_study_repository.dart` only (87-127).

### 4.4 Verify

```bash
fvm flutter test test/persistence/sqlite_study_repository_test.dart --plain-name 'backfill is batched'
fvm flutter test test/persistence/sqlite_study_repository_test.dart  # whole file once
git stash && fvm flutter test test/persistence/sqlite_study_repository_test.dart --plain-name 'backfill is batched'
# with a count assertion this must fail on stashed code; with only-correctness it passes but slower
git stash pop
fvm flutter analyze
git add lib/src/persistence/sqlite_study_repository.dart test/persistence/sqlite_study_repository_test.dart
git commit -m "perf(persistence): batch pgnHash backfill instead of N+1 fetches"
./scripts/gates.sh t1
```

### 4.5 Push & PR

```bash
git push -u origin fix/review-fix-04-pgnhash-backfill
gh pr create -R cassandre60/ChessSRS --title "perf(persistence): batch pgnHash backfill instead of N+1 fetches" --body "Closes REVIEW-FIX-04. See docs/tasks/REVIEW-FIX-04-pgnhash-backfill-batching.md."
```

## 5. Constraints

* Do not edit `SPEC.md`, `GATES.md`, `QUALITY.md`, `TEST_STRATEGY.md`, `AGENTS.md`,
  `pubspec.yaml`, `analysis_options.yaml`, `.gates/`, `scripts/gates/`, `.github/`.
* One fix per PR. No drive-by refactors. In particular do not refactor
  `savePositionKnowledgeState` dual-write in the same PR.
* Targeted tests only locally; full suite is CI's job (`AGENTS.md` §3.1).
* SQLite `IN` list has a variable limit — chunk at 400 if you are defensive.
* No local release builds.

## 6. Done when

* [ ] Test added covering the backfill with multiple unhashed studies
* [ ] Test proves batching (call count) or at least documents before/after count
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green on committed branch
* [ ] PR open against `cassandre60/ChessSRS`
