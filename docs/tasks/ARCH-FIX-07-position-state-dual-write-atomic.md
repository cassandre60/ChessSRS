# ARCH-FIX-07 — Dual-write of canonical state + review-state mirrors is not atomic

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

`SqliteStudyRepository` maintains **two** representations of the same SRS numbers:

* `position_knowledge_state` — canonical, keyed by `canonicalId` (shared across
  transpositions; one row per position).
* `srs_review_state` — legacy per-occurrence mirrors, keyed by `decisionId`
  (one row per `srs_decision.id` plus one row per `canonicalId`).

The batch path is correct — one SQLite transaction:

* `saveAnswerBatch` (`lib/src/persistence/sqlite_study_repository.dart:508-558`)
  does everything inside `await _db.transaction((txn) async { batch ... await batch.commit })`.

The single-write paths are **not**:

* `savePositionKnowledgeState` (`lib/src/persistence/sqlite_study_repository.dart:472-491`):
  ```dart
  await _db.insert(kTablePositionKnowledgeState, ...);          // txn 1 (implicit)
  await saveReviewState(state.toReviewState(state.canonicalId)); // txn 2
  final matchingDecisions = await _db.query(kTableSrsDecision, ...);
  for (final dec in matchingDecisions) {
    await saveReviewState(state.toReviewState(decId));           // txn 3..N
  }
  ```
  Three separate implicit transactions (each `insert`/`query` on `_db` outside a
  `transaction()` call opens its own commit). If the second write fails after
  the first committed, canonical and mirrors diverge and the position is scheduled
  from two different sets of numbers.

* `savePositionKnowledgeStates` (`lib/src/persistence/sqlite_study_repository.dart:494-505`):
  ```dart
  final batch = _db.batch();
  for (final s in states) { batch.insert(kTablePositionKnowledgeState, ...); }
  await batch.commit(noResult: true);
  await saveReviewStates(states.map((s) => s.toReviewState()).toList());
  ```
  First batch commits on `_db`; second batch commits separately via `saveReviewStates`
  on `_db` again — two commits. A crash between them leaves canonical updated
  but mirrors stale. `saveReviewStates` itself is a batch on `_db` (not on the
  transaction), so even that second write is not joined to the first.

This is **not** hypothetical drift like the old `saveAnswerBatch` raw-SQL mirrors
fixed in round 2 — those were inside the batch's `SELECT id … WHERE canonicalStateId`
and went in one commit. The single-save paths simply were not updated the same way.

`docs/tech-debt-inventory.md` item 14 / `ARCHITECTURE.md` §8 boundary erosion
note calls out persistence as high-risk; `review-4-orchestration-persistence.md`
documents the transactional contract these methods should honour (`review_service`
checkpoint + single `saveAnswerBatch`).

## 2. Files to read before touching anything

1. `lib/src/persistence/sqlite_study_repository.dart:471-558` — the two single-save methods + the correct batch
2. `lib/src/persistence/sqlite_study_repository.dart:640-680` — `_knowledgeStateRow`, `_reviewStateRow` builders (one row builder per table pattern)
3. `lib/src/persistence/srs_schema.dart` — table/col names, no FKs on these two tables (so no cascade to lean on)
4. `lib/src/persistence/study_repository.dart:76-89` — `StudyRepository` contract (do not change)
5. `lib/src/review/review_service.dart:282-329, 343-378` — `submitMove`/`retryMove` call `saveAnswerBatch` (batch path) vs any legacy single-save callers (search `savePositionKnowledgeState` across `lib/`)
6. `test/persistence/sqlite_study_repository_test.dart` — persistence tests, DB helper, existing `savePositionKnowledgeState` coverage
7. `AGENTS.md` §3.1 — local test budget (targeted file, once)

## 3. The fix

Make the single-save paths use the **same single-transaction batch shape** as
`saveAnswerBatch`. The raw-SQL mirrors are not optional — transposition-sharing
means one canonical maps to N occurrences and every occurrence's mirror must be
coherent with the canonical or `ReviewSession` sees two truths.

### 3.1 `savePositionKnowledgeState(PositionKnowledgeState state)`

Replace the three-await, N-txn body with one `transaction` + `batch`:

```dart
@override
Future<void> savePositionKnowledgeState(PositionKnowledgeState state) async {
  await _db.transaction((txn) async {
    final batch = txn.batch();
    batch.insert(
      kTablePositionKnowledgeState,
      _knowledgeStateRow(state),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    batch.insert(
      kTableSrsReviewState,
      _reviewStateRow(state.toReviewState(state.canonicalId)),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    batch.rawInsert(
      '''
      INSERT OR REPLACE INTO $kTableSrsReviewState(
        decisionId, firstReviewedAt, lastReviewedAt, nextDueAt,
        repetitionCount, lapseCount, stability, difficulty
      )
      SELECT id, ?, ?, ?, ?, ?, ?, ?
      FROM $kTableSrsDecision
      WHERE canonicalStateId = ?
      ''',
      [
        state.firstReviewedAt?.toIso8601String(),
        state.lastReviewedAt?.toIso8601String(),
        state.nextDueAt?.toIso8601String(),
        state.repetitionCount,
        state.lapseCount,
        state.stability,
        state.difficulty,
        state.canonicalId,
      ],
    );
    await batch.commit(noResult: true);
  });
}
```

Why the raw-SQL for mirrors instead of `SELECT id` + loop `INSERT`s: the batch
path already does it that way, one statement updates all N mirrors atomically
with no `query` inside the transaction. Looping `query` + `await saveReviewState`
inside a transaction still works but is slower and mixes `query` + `insert` styles;
match `saveAnswerBatch`'s single-statement mirror.

### 3.2 `savePositionKnowledgeStates(List<PositionKnowledgeState> states)`

Make it one transaction with one batch, not two commits:

```dart
@override
Future<void> savePositionKnowledgeStates(List<PositionKnowledgeState> states) async {
  if (states.isEmpty) return;
  await _db.transaction((txn) async {
    final batch = txn.batch();
    for (final s in states) {
      batch.insert(
        kTablePositionKnowledgeState,
        _knowledgeStateRow(s),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      batch.insert(
        kTableSrsReviewState,
        _reviewStateRow(s.toReviewState(s.canonicalId)),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      batch.rawInsert(
        '''
        INSERT OR REPLACE INTO $kTableSrsReviewState(
          decisionId, firstReviewedAt, lastReviewedAt, nextDueAt,
          repetitionCount, lapseCount, stability, difficulty
        )
        SELECT id, ?, ?, ?, ?, ?, ?, ?
        FROM $kTableSrsDecision
        WHERE canonicalStateId = ?
        ''',
        [
          s.firstReviewedAt?.toIso8601String(),
          s.lastReviewedAt?.toIso8601String(),
          s.nextDueAt?.toIso8601String(),
          s.repetitionCount,
          s.lapseCount,
          s.stability,
          s.difficulty,
          s.canonicalId,
        ],
      );
    }
    await batch.commit(noResult: true);
  });
}
```

Verify the `savePositionKnowledgeStates` plural callers: if none pass states
that also need per-occurrence mirrors, the loop is still correct — it just writes
the same canonical mirror twice (idempotent `REPLACE`).

### 3.3 What NOT to change

* Do not change `saveAnswerBatch` — it is already correct and tested.
* Do not change `saveReviewState` / `saveReviewStates` — they are low-level legacy
  singletons; the atomicity fix belongs in the canonical wrapper methods.
* Do not add a new public method or change `StudyRepository` contract.
* Do not touch `SPEC.md`, `GATES.md`, `QUALITY.md`, `.gates/`, `pubspec.yaml`,
  `analysis_options.yaml`, `.github/`.
* Keep the row builders (`_knowledgeStateRow`, `_reviewStateRow`) — single builder
  per table invariant (see header comments on those helpers).

## 4. How to make the work verifiable (no guessing)

### 4.1 Worktree setup — required

```bash
git worktree add ../chesssrs-arch-fix-07 -b fix/arch-fix-07-dual-write-atomic origin/main
cd ../chesssrs-arch-fix-07
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze
```

Branch name is `fix/arch-fix-07-dual-write-atomic`.

### 4.2 Failing test first — RED

Add a test proving the two representations stay in sync and that a mid-write
failure does not leave a partial commit. If injecting a failure is too invasive,
prove the sync property + transactional shape:

In `test/persistence/sqlite_study_repository_test.dart` (or a new file)
add a test:

1. Create a study with 2 chapters that transpose to the same canonical position
   (same `canonicalStateId` on two `RepertoireDecision`s) — see existing transposition
   fixtures or hand-craft two decisions sharing a `canonicalStateId`.
2. Call `savePositionKnowledgeState(state)` with `stability = 42.0`.
3. Assert: `getPositionKnowledgeState(canonicalId)` returns `stability 42`,
   `getReviewState(canonicalId)` returns `stability 42`, and `getReviewState(decisionId)`
   for **each** occurrence also returns `stability 42`. Before the fix the
   correctness is the same on the happy path — the atomicity difference only
   shows under failure — so also assert:
4. (**Optional but stronger**) Inject a failing second write: wrap the DB in a
   spy that throws on the second `insert` (or on `srs_review_state`), call
   `savePositionKnowledgeState`, catch, then assert **neither** table was updated
   (both reads return the old value). With the current N-txn code the first
   insert survives; after the fix the `transaction` rolls back.

At minimum ship (1)-(3) with an invariant citation; (4) is preferred if the test
DB adapter supports spying without pulling in `sqflite` internals.

```dart
// SPEC INV-020 / QUALITY §4.2: canonical + per-occurrence mirrors must be
// updated atomically — incremental persistence without divergence (one transaction).
```

Run targeted:

```bash
fvm flutter test test/persistence/sqlite_study_repository_test.dart --plain-name 'canonical mirrors are atomic'
```

### 4.3 Implement the fix — GREEN

Edit only `lib/src/persistence/sqlite_study_repository.dart`.

### 4.4 Verify

```bash
fvm flutter test test/persistence/sqlite_study_repository_test.dart --plain-name 'canonical mirrors are atomic'
fvm flutter test test/persistence/sqlite_study_repository_test.dart   # whole file, once
fvm flutter analyze
git add lib/src/persistence/sqlite_study_repository.dart test/persistence/sqlite_study_repository_test.dart
git commit -m "fix(persistence): atomically persist canonical state with its review-state mirrors

Single-save paths committed canonical and mirrors in separate
transactions; a mid-write failure left them divergent. Wrap each
path in one transaction + batch, matching saveAnswerBatch's shape
for its occurrence mirrors.

Harness: OpenCode
Model: cleanapis/claude-fable-5.1"
./scripts/gates.sh t1
```

Gates read committed diff — run after committing.

### 4.5 Push & PR

```bash
git push -u origin fix/arch-fix-07-dual-write-atomic
gh pr create -R cassandre60/ChessSRS --title "fix(persistence): atomically persist canonical state with its review-state mirrors" --body "Closes ARCH-FIX-07. See docs/tasks/ARCH-FIX-07-position-state-dual-write-atomic.md.

---
Harness: OpenCode
Model: cleanapis/claude-fable-5.1"
```

## 5. Done when

* [ ] Both single-save methods use one `transaction` + `batch` (or equivalent single-txn shape)
* [ ] Canonical insert, canonical mirror, and all occurrence mirrors commit together or not at all
* [ ] Test asserts post-save canonical + mirrors agree; failure-injection test shows full rollback if added
* [ ] `fvm flutter analyze` 0 issues on touched files
* [ ] `./scripts/gates.sh t1` green on committed branch
* [ ] PR open against `cassandre60/ChessSRS`
