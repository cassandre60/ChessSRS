# PERSIST-FIX-14 — Every persisted answer erases latency telemetry (INSERT OR REPLACE wipes columns)

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

`PositionKnowledgeState` is the canonical row (`position_knowledge_state`: `latencyEmaMs`, `latencySampleCount`, `lastExposedAt`) but the orchestor converts a `ReviewState` → `PositionKnowledgeState` and then writes with **`INSERT OR REPLACE`** (delete + reinsert) supplying only the 8 fields that `ReviewState` carries. `latencyEmaMs`/`latencySampleCount` have no counterpart on `ReviewState` (`lib/src/domain/review_state.dart:40-59` declares exactly eight fields) so they are absent on the written row, and `REPLACE` erases them:

| column | before | after any answer |
|---|---|---|
| `latencyEmaMs` | measured | `NULL` |
| `latencySampleCount` | N | `0` |

The conversion is hand-written identically at **three sites** in `lib/src/review/review_service.dart:287-296, 303-312, 358-367` (now via `PositionKnowledgeState.fromReviewState(..., canonicalId)` since review-4's D1 landed), and the write is `conflictAlgorithm: ConflictAlgorithm.replace` in `lib/src/persistence/sqlite_study_repository.dart` (`_knowledgeStateRow` call sites + `saveAnswerBatch`'s knowledge-state inserts). A single answer walks a 6-ply line and resets latency on all seven positions (`allKStates` in `review_service.dart:300-314`), none of which the user was asked about.

Severity is **MEDIUM**: nothing populates `latencyEmaMs` yet (`rg latencyEmaMs lib/` hits only `copyWith` + row reader), so nothing is lost today — but the schema reserves the columns (`srs_schema.dart:83-84`), the architecture doc says *"Latency (`latencyEmaMs`) is preserved as optional post-hoc telemetry only"*, and the moment telemetry is wired it will be destroyed on every answer, silently, with no test failure. This is `docs/review-4-orchestration-persistence.md` C1 + D1.

## 2. Files to read before touching anything

1. `lib/src/domain/position_knowledge_state.dart:75-110` — `fromReviewState`, `toReviewState`, `latencyEmaMs`, `latencySampleCount`, `copyWith`, `lastExposedAt` (persisted exposure cap — already handled correctly via `copyWith`, compare)
2. `lib/src/domain/review_state.dart:40-59` — confirms eight fields, no latency
3. `lib/src/persistence/srs_schema.dart:74-86` — `position_knowledge_state` column list
4. `lib/src/persistence/sqlite_study_repository.dart:507-558, 644-700` — `saveAnswerBatch` (two loops over `allKStates`), `savePositionKnowledgeState` path, `_knowledgeStateRow`, `_knowledgeStateFromRow`
5. `lib/src/review/review_service.dart:287-330, 356-375` — the three `fromReviewState(...).copyWith(lastExposedAt: ...)` sites and `saveAnswerBatch(knowledgeStates: allKStates, ...)`
6. `lib/src/persistence/json_adapters.dart` — not affected (ReviewState JSON only)
7. `test/persistence/sqlite_study_repository_test.dart` — existing persistence tests for knowledge states
8. `docs/review-4-orchestration-persistence.md` C1/D1 — full expected behaviour ("round-trip that preserves columns the caller does not mention") and fix options

## 3. The fix

Two parts, both small. Either alone is insufficient: a correct conversion still has nothing to copy from `ReviewState`, and a non-destructive write still needs the conversion to be used consistently.

### 3.1 Use the domain conversion consistently (already done — verify)

`PositionKnowledgeState.fromReviewState(ReviewState, {String canonicalId})` must be the **only** way a `ReviewState` becomes a `PositionKnowledgeState` at the call sites. Audit that all three sites in `review_service.dart` use it (do not reintroduce hand-written field copies). This was already landed as D1; this brief keeps it closed, not re-litigated.

### 3.2 Make the knowledge-state write non-destructive — preserve latency columns

Change every write to `position_knowledge_state` from **`REPLACE` (delete+insert)** to **an upsert that touches only the columns being written**, so columns the caller does not mention (`latencyEmaMs`, `latencySampleCount`) survive.

Preferred SQLite shape for each row (works inside the existing `Batch` + `transaction` in `saveAnswerBatch`):

```sql
INSERT INTO position_knowledge_state
  (canonicalId, firstReviewedAt, lastReviewedAt, nextDueAt, repetitionCount, lapseCount, stability, difficulty, lastExposedAt)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(canonicalId) DO UPDATE SET
  firstReviewedAt  = excluded.firstReviewedAt,
  lastReviewedAt   = excluded.lastReviewedAt,
  nextDueAt        = excluded.nextDueAt,
  repetitionCount  = excluded.repetitionCount,
  lapseCount       = excluded.lapseCount,
  stability        = excluded.stability,
  difficulty       = excluded.difficulty,
  lastExposedAt    = excluded.lastExposedAt
-- latencyEmaMs, latencySampleCount intentionally absent — preserved on conflict
```

Implement it as `batch.rawInsert(...)` with the 9 placeholders — do not build a new `Map` via `_knowledgeStateRow` for this table, because that map contains the two latency columns and would reintroduce the erasure even if the conflict algorithm were changed elsewhere. Keep `_knowledgeStateRow` for reads/tests but **not** for these writes, or make it emit a map without latency keys when used for upserts.

Scope: both loops in `saveAnswerBatch` (knowledge states + review-state mirrors already have their own semantics — leave the `srs_review_state` writes as `REPLACE`, they carry no latency) and the standalone `savePositionKnowledgeState` path (grep for any other direct `_db.insert(isolate)` on `position_knowledge_state` outside `saveAnswerBatch`).

### 3.3 What NOT to change

* Do not change `PositionKnowledgeState.toReviewState()` — it correctly drops latency (one-way, documented).
* Do not change `srs_review_state` writes — they have no latency columns to preserve.
* Do not change `SPEC.md`, `GATES.md`, protected paths. Do not bundle `PERSIST-FIX-13` (same files, different invariant — one fix per PR).
* Do not add latency population — this PR preserves whatever `saveAnswerBatch` does not mention; it does not produce latency.

## 4. How to make the work verifiable (no guessing)

### 4.1 Worktree setup — required

```bash
git worktree add ../chesssrs-persist-fix-14 -b fix/persist-fix-14-latency-preservation origin/main
cd ../chesssrs-persist-fix-14
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze
```

Branch name is `fix/persist-fix-14-latency-preservation`.

### 4.2 Failing test first — RED

Add a test that fails on the current code and passes after the fix. The review prescribes it:

1. Seed a canonical row with non-trivial latency: `PositionKnowledgeState(canonicalId: k, latencyEmaMs: 1234.5, latencySampleCount: 7, stability: 10.0, lastExposedAt: …)` via `repo.savePositionKnowledgeState` (or direct `db.insert` + `getPositionKnowledgeState`).
2. Simulate an answer that walks the line: call `repo.saveAnswerBatch(knowledgeStates: [PositionKnowledgeState.fromReviewState(reviewState, canonicalId: k).copyWith(lastExposedAt: throttle[k])])` where `reviewState` is a normal `ReviewState` (no latency fields).
3. Read back with `repo.getPositionKnowledgeState(k)`.
4. Assert `read.latencyEmaMs == 1234.5` and `read.latencySampleCount == 7` — before the fix they are `null` / `0`; after they survive. Also assert the seven fields that *were* mentioned did update (e.g. `stability` changed to the new value).

A second assertion covering the auto-traversal side effects: seed latency on a canonical that appears in `allKStates` as a side effect (contagion/sibling/exposure), persist a batch containing it, assert its latency survives too.

```dart
// DOC review-4 C1: every persisted answer must preserve latency telemetry.
// INSERT OR REPLACE must not erase columns the caller did not mention (upsert).
```

Run targeted:

```bash
fvm flutter test test/persistence/sqlite_study_repository_test.dart --plain-name 'latency survives answer'
```

(Use the real plain name you chose; grep `latency` after adding.)

### 4.3 Implement the fix — GREEN

Edit only the persistence writes listed in §3.2 (and add the test file).

### 4.4 Verify

```bash
fvm flutter test test/persistence/sqlite_study_repository_test.dart --plain-name 'latency survives answer'
fvm flutter test test/persistence/sqlite_study_repository_test.dart   # whole file, once

fvm flutter analyze

# Commit, then gates — gates read committed diff, not working tree
git add lib/src/persistence/sqlite_study_repository.dart test/persistence/sqlite_study_repository_test.dart
git commit -m "fix(persistence): preserve latency telemetry across answer persistence (upsert, not REPLACE)"
./scripts/gates.sh t1
```

Gates read `origin/main...HEAD` on committed history — a pre-commit `gates.sh t1` that reports "clean" means nothing. Run after committing.

### 4.5 Push & PR

```bash
git push -u origin fix/persist-fix-14-latency-preservation
gh pr create -R cassandre60/ChessSRS --title "fix(persistence): preserve latency telemetry across answer persistence (upsert, not REPLACE)" --body "Closes PERSIST-FIX-14. See docs/tasks/PERSIST-FIX-14-latency-preservation.md."
```

(Stamp `Harness:`/`Model:` only in the PR body, per `AGENTS.md` GitHub PR Attribution.)

## 5. Done when

* [ ] Writes to `position_knowledge_state` use `ON CONFLICT…DO UPDATE SET` on the 8-9 SRS columns, not `REPLACE`; latency columns absent from the `SET` list
* [ ] `_knowledgeStateRow` is not used for these writes (or is split so it cannot emit latency keys)
* [ ] Tests assert seeded `latencyEmaMs`/`latencySampleCount` survive `saveAnswerBatch` + side-effect path
* [ ] `fvm flutter analyze` 0 issues on touched files
* [ ] `./scripts/gates.sh t1` green on committed branch
* [ ] PR open against `cassandre60/ChessSRS`
