# ARCH-FIX-08 — Missing FK enforcement + NOT IN on nullable column (slow / wrong delete)

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

Two related SQLite correctness/perf bugs in the same subsystem:

### 8a. FKs are declared but never enforced

`srs_schema.dart:40-57` declares foreign keys:

```sql
FOREIGN KEY (studyId) REFERENCES srs_study(id) ON DELETE CASCADE
FOREIGN KEY (chapterId) REFERENCES srs_chapter(id) ON DELETE CASCADE
```

SQLite disables foreign-key enforcement by default. It must be enabled per
connection with `PRAGMA foreign_keys = ON` in `onConfigure`. `lib/src/db/database.dart:94-100`
currently does only `PRAGMA journal_mode=WAL` in `onConfigure` and never enables
FKs. The code works today because `deleteStudy`/`deleteChapter` manually cascade
(`sqlite_study_repository.dart:164-253, 321-379`), but an orphan row from any
other path (import transaction, direct `insert`, future repository method) would
not be caught, and deleting a study via raw `DELETE FROM srs_study` would leave
orphan chapters/decisions silently.

`docs/tech-debt-inventory.md` tracks this as `PRAGMA foreign_keys=ON` missing
from `onConfigure` (item 14 / architecture hardening).

### 8b. `NOT IN` on a nullable column forces a full scan / mishandles NULLs

`deleteStudy` (`sqlite_study_repository.dart:216-245`) guards shared canonical
rows with:

```sql
DELETE FROM position_knowledge_state
WHERE canonicalId IN (?,?,…)
  AND canonicalId NOT IN (
    SELECT canonicalStateId FROM srs_decision WHERE studyId != ? AND canonicalStateId IS NOT NULL
  )
```

And two more copies for `srs_review_state`/`srs_review_event` with
`decisionId NOT IN (SELECT canonicalStateId …)`. Three problems:

* Rows are written back to SQLite with the repeated query logic (duplicate
  canonical handling during import).
* `NOT IN` semantics: if the subquery yields a NULL (it is guarded with
  `IS NOT NULL` here, so protected, but the *outer* column is `TEXT` nullable-declared
  in older rows), SQLite `NOT IN` still requires a full scan and nullable handling
  per SQL semantics, bypassing the index. `NOT EXISTS` uses the index on
  `idx_srs_decision_canonicalStateId` and is NULL-safe.
* Each chunk executes the subquery **three times** (once per table) — same `SELECT
  canonicalStateId … WHERE studyId != ?` repeated. A CTE or a single shared
  pre-query hoists it.

The same `NOT IN (SELECT canonicalStateId …)` pattern appears in `deleteChapter`
(`sqlite_study_repository.dart:354-374`) as:

```sql
DELETE FROM position_knowledge_state
WHERE canonicalId = ?
  AND canonicalId NOT IN (SELECT canonicalStateId FROM srs_decision WHERE canonicalStateId IS NOT NULL)
```

(single-id loop variant — same fix: `NOT EXISTS`).

## 2. Files to read before touching anything

1. `lib/src/persistence/srs_schema.dart:40-91` — FK declarations, indexes
2. `lib/src/db/database.dart:88-114, 389-396` — `onConfigure`/`onOpen`, `_doesTableExist`, current PRAGMAs
3. `lib/src/persistence/sqlite_study_repository.dart:164-260` — `deleteStudy` cascade + the 3 `NOT IN` guards
4. `lib/src/persistence/sqlite_study_repository.dart:320-380` — `deleteChapter` cascade + `ownedElsewhere`
5. `lib/src/persistence/canonical_rekey_migration.dart` / `opening_name_repair_migration.dart` — migrations that run after `onConfigure` (FK enforcement timing matters: `onConfigure` fires before `onCreate`/`onUpgrade`/`onOpen`)
6. `test/persistence/sqlite_study_repository_test.dart` — deletion tests (study/chapter delete, shared transpositions)
7. `test/db/database_test.dart` (if exists) — DB open/config tests

## 3. The fix

### 3.1 Enable FKs (`8a`) — one line in `database.dart`

In `lib/src/db/database.dart:94-100` inside `onConfigure`, add after the WAL pragma:

```dart
onConfigure: (db) async {
  final version = await _getDatabaseVersion(db);
  _logger.info('SQLite version: $version');
  if (version != null && version >= 307000) {
    _logger.info('Enabling WAL journal mode');
    await db.rawQuery('PRAGMA journal_mode=WAL');
  }
  // Enforce declared FKs (srs_schema.dart). No-op on connections that do not
  // have FK tables, so ordering with onCreate is safe.
  await db.execute('PRAGMA foreign_keys = ON');
},
```

Verify that enabling FKs does not break existing tests: the manual cascades in
`deleteStudy`/`deleteChapter` delete children *before* parents inside the same
transaction, which is also the order SQLite's cascade would do — so both orders
are correct and the manual deletes remain (they handle shared canonicals, which
FK cascade would delete unconditionally). Do not remove the manual cascades.

Note: `sqflite`'s `onConfigure` is the right place (fires on every open before
any DDL). `onOpen` is too late — it fires after `onCreate`/`onUpgrade`.

### 3.2 Replace `NOT IN` with `NOT EXISTS` (+ optional hoist) (`8b`)

For each of the 4 deletion guards:

**Before** (deleteStudy, 3 statements per chunk; same shape in deleteChapter's loop):

```sql
DELETE FROM position_knowledge_state
WHERE canonicalId IN (...)
  AND canonicalId NOT IN (SELECT canonicalStateId FROM srs_decision WHERE studyId != ?)
```

**After**:

```sql
DELETE FROM position_knowledge_state
WHERE canonicalId IN (...)
  AND NOT EXISTS (
    SELECT 1 FROM srs_decision d2
    WHERE d2.canonicalStateId = position_knowledge_state.canonicalId
      AND d2.studyId != ?
  )
```

And for the review tables:

```sql
DELETE FROM srs_review_state
WHERE decisionId IN (...)
  AND NOT EXISTS (
    SELECT 1 FROM srs_decision d2
    WHERE d2.canonicalStateId = srs_review_state.decisionId
      AND d2.studyId != ?
  )
```

Same for `srs_review_event`.

For `deleteChapter`'s single-id loop, same transformation:

```sql
DELETE FROM position_knowledge_state
WHERE canonicalId = ?
  AND NOT EXISTS (
    SELECT 1 FROM srs_decision
    WHERE canonicalStateId = position_knowledge_state.canonicalId
  )
```

**Optional hoist** (only if it keeps the diff small): pre-read the shared
canonical ids once per chunk before the 3 deletes:

```dart
final sharedCanonicals = await txn.rawQuery(
  'SELECT DISTINCT canonicalStateId FROM $kTableSrsDecision WHERE studyId != ? AND canonicalStateId IS NOT NULL',
  [id],
);
final sharedSet = sharedCanonicals.map((r) => r['canonicalStateId']).toSet();
// then guard with: canonicalId IN (...) AND canonicalId NOT IN sharedSet-in-memory
```

Do NOT do this hoist and the `NOT EXISTS` rewrite in the same commit if either
one alone is reviewable — the `NOT EXISTS` fix is the correctness/perf win;
hoisting is a follow-up optimisation. This brief requires `NOT EXISTS` only.

### 3.3 Fix the string-interpolated table name (S-1, belongs here)

While touching `database.dart`, also fix `_doesTableExist`:

```dart
// BEFORE
final tableExists = await db.rawQuery(
  "SELECT name FROM sqlite_master WHERE type='table' AND name='$table'",
);

// AFTER — parameterised (allowlist is also acceptable)
final tableExists = await db.rawQuery(
  "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
  [table],
);
```

One-line fix. Include it in the same commit — it is the same file and the same
class of SQL-hygiene issue. Marked as `S-1` in `tech-debt-inventory.md`.

### What NOT to change

* Do not drop the manual cascades — FK cascade would delete shared canonical rows
  that still have occurrences in other studies (the `NOT EXISTS` guard exists for
  that reason).
* Do not add new FKs on `position_knowledge_state` / `srs_review_state` — those
  tables are keyed by canonical occurrence id, not by FK to `srs_decision`.
* Do not edit `SPEC.md`, `GATES.md`, `QUALITY.md`, `AGENTS.md`, `pubspec.yaml`,
  `.gates/`, `.github/`, `analysis_options.yaml`.
* Do not widen the PR to ARCH-FIX-05/06/07 — one fix per PR.

## 4. How to make the work verifiable (no guessing)

### 4.1 Worktree setup — required

```bash
git worktree add ../chesssrs-arch-fix-08 -b fix/arch-fix-08-foreign-keys-not-in origin/main
cd ../chesssrs-arch-fix-08
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze
```

Branch name is `fix/arch-fix-08-foreign-keys-not-in`.

### 4.2 Failing-or-proving test first

Add or extend a test that witnesses both fixes:

**(a) FK enforcement test** (smoke):

In `test/db/database_test.dart` or `test/persistence/sqlite_study_repository_test.dart`,
after opening the DB via `openAppDatabase` (or the repo helper), run:

```dart
final fkOn = await db.rawQuery('PRAGMA foreign_keys');
expect(fkOn.first.values.first, 1);
```

Before the fix this is `0`; after it is `1`. Tag as `// SPEC INV-040:` invariant if
one exists for DB integrity (else `// QUALITY.md §1 ARCH: FKs enforced`).

**(b) Correctness of NOT EXISTS under shared canonicals**:

Existing `deleteStudy` tests that cover transpositions (two studies sharing a
canonical position) already pass with `NOT IN` on happy paths because `IS NOT NULL`
guards it. After switching to `NOT EXISTS`, the same tests must still pass.
No new failure to manufacture — prove the guard still keeps the shared row:

1. Create study A and study B sharing a canonical position (same `canonicalStateId`
   on two decisions, one per study).
2. Delete study A.
3. Assert: `getPositionKnowledgeState(canonicalId)` still returns the row
   (shared with B), and `getReviewState(canonicalId)` still exists. Before either
   fix this also passes, so the test is a regression lock rather than a
   red→green proof — which is correct for a `NOT IN → NOT EXISTS` semantic
   refinement plus the `IS NOT NULL` guard already present.

Run targeted:

```bash
fvm flutter test test/persistence/sqlite_study_repository_test.dart --plain-name 'shared canonical not deleted'
fvm flutter test test/persistence/sqlite_study_repository_test.dart --plain-name 'foreign_keys'
```

### 4.3 Implement the fix — GREEN

Edit only `lib/src/db/database.dart` and `lib/src/persistence/sqlite_study_repository.dart`.

### 4.4 Verify

```bash
fvm flutter test test/persistence/sqlite_study_repository_test.dart --plain-name 'shared canonical not deleted'
fvm flutter test test/persistence/sqlite_study_repository_test.dart   # whole file once
fvm flutter test test/db/database_test.dart  # if the FK smoke lives there
fvm flutter analyze
git add lib/src/db/database.dart lib/src/persistence/sqlite_study_repository.dart test/persistence/sqlite_study_repository_test.dart test/db/database_test.dart
git commit -m "fix(db): enforce foreign_keys pragma and use NOT EXISTS for shared-canonical guard

FKs were declared but never enforced (onConfigure now sets
PRAGMA foreign_keys=ON). Delete guards used NOT IN on a nullable
shape which forces a scan / NULL semantics; NOT EXISTS uses the
existing index and is NULL-safe.

Harness: OpenCode
Model: cleanapis/claude-fable-5.1"
./scripts/gates.sh t1
```

Gates read committed diff — run after committing. Expect G03 (banned APIs) clean
— the `name=?` parameterisation fixes a `rawQuery` SAST flag if present.

### 4.5 Push & PR

```bash
git push -u origin fix/arch-fix-08-foreign-keys-not-in
gh pr create -R cassandre60/ChessSRS --title "fix(db): enforce foreign_keys pragma and use NOT EXISTS for shared-canonical guard" --body "Closes ARCH-FIX-08. See docs/tasks/ARCH-FIX-08-foreign-keys-and-not-in.md.

---
Harness: OpenCode
Model: cleanapis/claude-fable-5.1"
```

## 5. Done when

* [ ] `onConfigure` executes `PRAGMA foreign_keys = ON`
* [ ] `deleteStudy` + `deleteChapter` guards use `NOT EXISTS` (not `NOT IN`)
* [ ] `_doesTableExist` parameterises the table name (no `'$table'` interpolation)
* [ ] FK smoke test: `PRAGMA foreign_keys` returns 1 on the opened DB
* [ ] Shared-canonical deletion test still green (or added)
* [ ] `fvm flutter analyze` 0 issues on touched files
* [ ] `./scripts/gates.sh t1` green on committed branch
* [ ] PR open against `cassandre60/ChessSRS`
