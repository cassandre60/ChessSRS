# DATA-FIX-26 — savePositionKnowledgeState non-atomic: crash between PKS insert and mirror writes loses mirrors

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

`sqlite_study_repository.dart:472-491` — `savePositionKnowledgeState` performs
three separate writes:

1. `_db.insert` the `position_knowledge_state` row (line ~473)
2. `_db.insert` the canonical `srs_review_state` row (line ~479)
3. Loop: `_db.insert` mirror `srs_review_state` rows for each decision sharing
   the canonical id (lines ~487-490)

These are **not wrapped in a transaction**. If the app is killed between step 1
and step 3 (e.g. low-memory OOM, user force-stop, battery death), the canonical
state is saved but the per-decision mirrors are stale. The next review session
reads mismatched data — canonical says "reviewed", mirrors say "not reviewed" —
and may re-present already-answered positions or skip positions that need review.

Compare with `saveAnswerBatch` (line ~508) which correctly uses
`_db.transaction(...)`.

The batch version `savePositionKnowledgeStates` (line ~494-505) has the same
problem: it calls `_db.insert` in a loop for PKS rows, then calls
`saveReviewStates` as a separate batch outside any transaction.

## 2. Files to read before touching anything

1. `lib/src/persistence/sqlite_study_repository.dart:472-505` — both methods
2. `lib/src/persistence/sqlite_study_repository.dart:508-540` — `saveAnswerBatch`
   (correct transaction pattern)
3. `lib/src/domain/review_state.dart` — `ReviewState`, `PositionKnowledgeState`
4. `QUALITY.md` INV-005 (incremental persistence) and INV-007 (position identity)
5. `test/persistence/sqlite_study_repository_test.dart` — existing persistence tests
6. `SPEC.md` — any invariant about atomicity

## 3. The fix

Wrap each method in a single transaction:

### 3.1 `savePositionKnowledgeState` (single)

```dart
@override
Future<void> savePositionKnowledgeState(
  PositionKnowledgeState pks,
  List<ReviewState> mirrorStates,
) async {
  await _db.transaction((txn) async {
    await txn.insert(
      kTablePositionKnowledgeState,
      _knowledgeStateToRow(pks),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Canonical review state
    await txn.insert(
      kTableSrsReviewState,
      _reviewStateToRow(pks.toReviewState()),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Mirror review states for each decision sharing the canonical id
    for (final mirror in mirrorStates) {
      await txn.insert(
        kTableSrsReviewState,
        _reviewStateToRow(mirror),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  });
}
```

### 3.2 `savePositionKnowledgeStates` (batch)

```dart
@override
Future<void> savePositionKnowledgeStates(
  List<PositionKnowledgeState> states,
  List<ReviewState> allMirrorStates,
) async {
  await _db.transaction((txn) async {
    for (final pks in states) {
      await txn.insert(
        kTablePositionKnowledgeState,
        _knowledgeStateToRow(pks),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        kTableSrsReviewState,
        _reviewStateToRow(pks.toReviewState()),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    for (final mirror in allMirrorStates) {
      await txn.insert(
        kTableSrsReviewState,
        _reviewStateToRow(mirror),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  });
}
```

### 3.3 What NOT to change

* Do not change `saveAnswerBatch` — it already uses a transaction.
* Do not change the `_reviewStateToRow` / `_knowledgeStateToRow` helpers.
* Do not change `ReviewService.submitMove` — the caller is fine; only the
  persistence layer needs the transaction.
* Do not touch `SPEC.md`, `GATES.md`, `.gates/`, `pubspec.yaml`.

## 4. Verification

```bash
git worktree add ../chesssrs-data-fix-26 -b fix/data-fix-26-pks-transaction origin/main
cd ../chesssrs-data-fix-26
fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs

# Existing test — must stay green (the transaction makes the same writes, just atomic)
fvm flutter test test/persistence/sqlite_study_repository_test.dart --plain-name 'savePositionKnowledgeState'

# New test (add to same file): verify that after savePositionKnowledgeState,
# both the PKS row and all mirror review-state rows exist. This was true before
# (no crash scenario in test), but codifies the contract.

fvm flutter test test/persistence/sqlite_study_repository_test.dart

fvm flutter analyze

git add lib/src/persistence/sqlite_study_repository.dart test/persistence/sqlite_study_repository_test.dart
git commit -m "fix(persistence): wrap savePositionKnowledgeState in transaction (crash-safety)"
./scripts/gates.sh t1
git push -u origin fix/data-fix-26-pks-transaction
gh pr create -R cassandre60/ChessSRS --title "fix(persistence): wrap savePositionKnowledgeState in transaction" --body "Closes DATA-FIX-26."
```

## 5. Done when

* [ ] `savePositionKnowledgeState` uses `_db.transaction` wrapping PKS + canonical + mirrors
* [ ] `savePositionKnowledgeStates` uses `_db.transaction` wrapping all PKS + all mirrors
* [ ] Existing persistence tests pass unchanged
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green
* [ ] PR open against `cassandre60/ChessSRS`

## 6. Sequencing note

This brief touches `sqlite_study_repository.dart`, which is in the persistence
serialization lane: `07 → 14 → 13 → 08 → 15 → 16 → 26`. If any of the
persistence lane briefs land first, rebase on `main` before starting.
