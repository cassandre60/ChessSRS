# PERSIST-FIX-15 — deleteDecisionsByStudy is dead code with an orphan leak (or a trap)

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

`StudyRepository.deleteDecisionsByStudy` (`lib/src/persistence/study_repository.dart:74`) is declared and implemented as a one-liner that deletes only the `srs_decision` rows:

`lib/src/persistence/sqlite_study_repository.dart:463-465`:
```dart
Future<void> deleteDecisionsByStudy(String studyId) async {
  await _db.delete(kTableSrsDecision, where: 'studyId = ?', whereArgs: [studyId]);
}
```

No review states, no knowledge states, no events. It has **no production callers** — only the interface declaration — while the live path `deleteStudy` (`sqlite_study_repository.dart:164-252`) correctly handles the hard case (a canonical position shared with a surviving study, via `sharedGuard` and `NOT IN` on `canonicalStateId`). If anyone wires up the shorter method, they inherit an orphan leak across three tables. `deleteDecisionsByStudy` was already called out in `docs/review-4-orchestration-persistence.md` D3 (LOW → trap).

`docs/tech-debt-inventory.md` §1 items 14/15 track the surrounding cascade-delete complexity; `ARCH-FIX-08` fixes the `NOT IN` shape but not this dead method.

## 2. Files to read before touching anything

1. `lib/src/persistence/study_repository.dart:74` — `deleteDecisionsByStudy` declaration
2. `lib/src/persistence/sqlite_study_repository.dart:164-252` — `deleteStudy` (correct guard, reuse)
3. `lib/src/persistence/sqlite_study_repository.dart:321-379` — `deleteChapter` (same shared-canonical guard)
4. `lib/src/persistence/sqlite_study_repository.dart:463-465` — the one-liner to fix or delete
5. `lib/src/persistence/srs_schema.dart` + `lib/src/db/database.dart` — FKs / `PRAGMA foreign_keys` (ARCH-FIX-08 enables FKs; if that lands first, orphaning would already be caught — but this method bypasses the transaction that would cascade)
6. `test/persistence/sqlite_study_repository_test.dart` — deletion tests (study/chapter delete, shared transpositions)
7. `docs/review-4-orchestration-persistence.md` D3 — recommended fix: delete or give same guard

## 3. The fix

The review recommends: **either delete it or give it the same guard `deleteStudy` has**. The safe choice is to **delete the method** — no caller, no reason to keep a trap. If the product wants a bulk-decision delete, it should call `deleteStudy` / `deleteChapter` instead.

### 3.1 Delete the method (preferred)

1. Delete `Future<void> deleteDecisionsByStudy(String studyId);` from `lib/src/persistence/study_repository.dart:74`.
2. Delete `Future<void> deleteDecisionsByStudy(String studyId) async { … }` from `lib/src/persistence/sqlite_study_repository.dart`.
3. `git grep -r deleteDecisionsByStudy lib/ test/` must be empty (only docs may still mention it).
4. Add a one-line note to `docs/review-4-orchestration-persistence.md` §D3 that the method was removed (follow-up PR or this one — do not touch protected docs if they are gated; otherwise note it in the PR description).

If the method must be kept (owner says so), fix it to delegate to the tested cascade instead of reimplementing:

```dart
Future<void> deleteDecisionsByStudy(String studyId) async {
  // Deleted: this method formerly orphaned review state / knowledge state / events.
  // Use deleteStudy for a full study delete; this now delegates to the same guard.
  final decisions = await _db.query(kTableSrsDecision, where: 'studyId = ?', whereArgs: [studyId]);
  if (decisions.isEmpty) return;
  // Reuse deleteStudy's guard via a helper extracted from it, or simply
  // query canonicalStateIds and apply the same sharedGuard / shared-canonical retention.
}
```

Preferred is deletion — far less risk, far smaller diff.

### 3.2 What NOT to change

* Do not change `deleteStudy` / `deleteChapter` logic — ARCH-FIX-08 already handles `NOT IN → NOT EXISTS` there.
* Do not add new FKs on `position_knowledge_state` / `srs_review_state`.
* Do not touch `SPEC.md`, `GATES.md`, protected paths. Delete the declaration + impl only.
* Do not bundle with `PERSIST-FIX-13` / `PERSIST-FIX-14` — one fix per PR.

## 4. How to make the work verifiable (no guessing)

### 4.1 Worktree setup — required

```bash
git worktree add ../chesssrs-persist-fix-15 -b fix/persist-fix-15-deleteDecisionsByStudy origin/main
cd ../chesssrs-persist-fix-15
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze
```

Branch name is `fix/persist-fix-15-deleteDecisionsByStudy`.

### 4.2 Failing-or-proving test — grep, not runtime

This is dead-code removal. The proof is static:

```bash
rg -n "deleteDecisionsByStudy" lib/ test/
# after: no hits

fvm flutter analyze
# 0 issues — no caller was broken by the removal
```

If the method is kept-with-guard instead, add a test: seed a study with a shared canonical (two studies, same `canonicalStateId`), call `deleteDecisionsByStudy(studyA.id)`, assert `getPositionKnowledgeState(sharedId)` still exists (shared with B), and orphan counts on `srs_review_state`/`srs_review_event` are zero for A's occurrence ids. Follow the shape of `deleteStudy` tests that already cover shared transpositions.

Run targeted (if kept-with-guard):

```bash
fvm flutter test test/persistence/sqlite_study_repository_test.dart --plain-name 'deleteDecisionsByStudy'
```

### 4.3 Implement the fix — GREEN

Edit only the two persistence files (and tests if keeping with guard).

### 4.4 Verify

```bash
fvm flutter analyze
# If kept-with-guard:
fvm flutter test test/persistence/sqlite_study_repository_test.dart --plain-name 'deleteDecisionsByStudy'
fvm flutter test test/persistence/sqlite_study_repository_test.dart  # whole file once

git add lib/src/persistence/study_repository.dart lib/src/persistence/sqlite_study_repository.dart test/persistence/sqlite_study_repository_test.dart
git commit -m "refactor(persistence): remove orphan-leaking deleteDecisionsByStudy"
./scripts/gates.sh t1
```

Gates read committed diff — run after committing.

### 4.5 Push & PR

```bash
git push -u origin fix/persist-fix-15-deleteDecisionsByStudy
gh pr create -R cassandre60/ChessSRS --title "refactor(persistence): remove orphan-leaking deleteDecisionsByStudy" --body "Closes PERSIST-FIX-15. See docs/tasks/PERSIST-FIX-15-deleteDecisionsByStudy-orphan-leak.md."
```

(Stamp `Harness:`/`Model:` only in the PR body.)

## 5. Done when

* [ ] `rg deleteDecisionsByStudy lib/ test/` is empty (or, if kept, guarded like `deleteStudy`)
* [ ] `fvm flutter analyze` 0 issues — no caller broken
* [ ] `./scripts/gates.sh t1` green on committed branch
* [ ] PR open against `cassandre60/ChessSRS`
