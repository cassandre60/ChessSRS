# PERSIST-FIX-13 — Timestamps are local time with no offset — timezone change shifts every due date

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

All SRS timestamps are produced, written, and read as **local wall time without an offset**:

1. Produced local: `SystemClock.now() => DateTime.now()` (`lib/src/domain/clock.dart:22`) — local.
2. Written without offset: `s.firstReviewedAt?.toIso8601String()` (`lib/src/persistence/sqlite_study_repository.dart:650-653, 961-965`, `lib/src/persistence/json_adapters.dart:64-66, 90`) — for a local `DateTime` this emits `2026-10-08T10:00:00.000` with **no `Z`**.
3. Read back as local in the reader's current zone: `DateTime.parse(first)` (`sqlite_study_repository.dart:623-641, 939-953`, `json_adapters.dart:75-77, 98`) — an offset-less string is interpreted in the **reader's current zone**.

**Demonstrating input**: a card becomes due at 10:00 in Tunis (UTC+1), stored as `2026-10-08T10:00:00.000`. The user flies to New York (UTC−5) and opens the app — `DateTime.parse` yields 10:00 New York, i.e. 15:00 Tunis. The due card is now 5 hours late; the reverse direction manufactures a false backlog. This is `docs/review-4-orchestration-persistence.md` C2 (MEDIUM), tracing review-1's D4 end-to-end. SRS intervals are days, but the due instant is an absolute point on the timeline — it must survive a timezone change.

## 2. Files to read before touching anything

1. `lib/src/domain/clock.dart:19-23` — `SystemClock` (`DateTime.now()`) — the producer
2. `lib/src/persistence/sqlite_study_repository.dart:644-661, 738-785, 939-998` — `_knowledgeStateRow`, `_reviewStateRow`, `_reviewEventRow`, `_knowledgeStateFromRow`, `_reviewStateFromRow`, `_reviewEventFromRow`
3. `lib/src/persistence/json_adapters.dart:62-86, 96-102` — `reviewStateToJson` / `reviewStateFromJson` / `reviewEventToJson` (same local-time pattern; events use `when.toIso8601String()` / `DateTime.parse(json['when'])`)
4. `lib/src/domain/position_knowledge_state.dart` + `lib/src/domain/review_state.dart` + `lib/src/domain/review_event.dart` — field types (DateTime? / DateTime)
5. `lib/src/review/review_service.dart:300-330, 356-375` — where `PositionKnowledgeState.fromReviewState(...).copyWith(lastExposedAt: ...)` derives timestamps from `session.clock.now()` / `ReviewState`
6. `lib/src/db/database.dart:88-130` — `openAppDatabase` `onUpgrade` / `onCreate` (if a one-time migration is needed for existing rows)
7. `test/persistence/sqlite_study_repository_test.dart` — persistence round-trip tests
8. `test/persistence/json_adapters_test.dart` (if exists) or any `reviewStateToJson` test
9. `docs/review-4-orchestration-persistence.md` §C2 — full trace and the honest migration caveat (stored strings carry no original offset)

## 3. The fix

Write and read an **absolute instant** (UTC), not a wall time. Either epoch-milliseconds in an `INTEGER` column or `toUtc().toIso8601String()` with `DateTime.parse(...).toUtc()` symmetrically. Epoch is cleaner long-term, but `TEXT` UTC is the smaller diff and survives `DateTime.parse` round-tripping without a schema change — pick one and apply it consistently to every field touched below. The review that filed this recommends UTC text as the pragmatic migration: reinterpret existing offset-less strings as their written instant, then write UTC going forward.

### 3.1 Write side — every `toIso8601String()` on an SRS instant must be UTC

In `lib/src/persistence/sqlite_study_repository.dart`:
- `_knowledgeStateRow` — `firstReviewedAt`, `lastReviewedAt`, `nextDueAt`, `lastExposedAt`
- `_reviewStateRow` — `firstReviewedAt`, `lastReviewedAt`, `nextDueAt`
- `_reviewEventRow` — `whenTimestamp`
- Inline `saveAnswerBatch` raw-SQL args (`s.firstReviewedAt?.toUtc().toIso8601String()` etc., four fields × N states)

In `lib/src/persistence/json_adapters.dart`:
- `reviewStateToJson` — three nullable fields
- `reviewEventToJson` — `when`

Each becomes `value?.toUtc().toIso8601String()` (nullable) or `value.toUtc().toIso8601String()` (non-null `when`). That emits a trailing `Z`, making the stored string unambiguous.

### 3.2 Read side — interpret as UTC

Each corresponding `DateTime.parse(...)` becomes `DateTime.parse(...).toUtc()` (or, if storing epoch, `DateTime.fromMillisecondsSinceEpoch(..., isUtc: true)`). Apply symmetrically to:
- `_knowledgeStateFromRow` — `firstReviewedAt`, `lastReviewedAt`, `nextDueAt`, `lastExposedAt`
- `_reviewStateFromRow` — same three
- `_reviewEventFromRow` — `when`
- `reviewStateFromJson` / `reviewEventFromJson` — same

Do **not** call `.toLocal()` on read — the domain compares with `clock.now()` which after this fix must also be compared in UTC. `FixedClock` in tests can stay local if the test constructs both the clock value and the expected instant in the same zone; the point is that production storage no longer shifts when the device zone does.

### 3.3 Migration for existing rows

Existing rows were written without an offset, so the original zone is not recoverable from the data — this is stated honestly in the review (§C2 caveat). The pragmatic migration, per the review:

> Reinterpret existing values as UTC in place — a one-time shift of at most one timezone offset for pre-existing cards, after which all new writes are correct. Strictly better than the status quo where every future zone change shifts everything.

That means **no data migration that rewrites old strings** is required to close the bug — old strings are already in the repo's local shape, and `DateTime.parse(...).toUtc()` on read will treat them as UTC (i.e. the instant they looked like in local time). If the team wants a formal migration that rewrites the column (e.g. a `v17` `UPDATE ... SET nextDueAt = datetime(nextDueAt || 'Z')` or epoch rewrite), scope it as a separate follow-up migration in `lib/src/db/database.dart` — do not block the write/read fix on it. Document the decision in the commit/PR body.

### 3.4 What NOT to change

* Do not change `SystemClock` to return `DateTime.now().toUtc()` — the clock's job is to produce an instant; the persistence layer's job is to make the stored instant unambiguous. If both are changed, tests that compare `FixedClock(DateTime(2026,10,8,10))` to stored values will need a UTC tweak — keep the change in the boundary, not the clock.
* Do not change `SPEC.md`, `GATES.md`, protected paths. This is a persistence-boundary fix.
* Do not change `srs_schema.dart` column types unless you chose the epoch-INTEGER path — and if you did, add the schema change and the read/write pair together.
* Do not bundle `PERSIST-FIX-14` (latency preservation) — same files, different invariant; one fix per PR.

## 4. How to make the work verifiable (no guessing)

### 4.1 Worktree setup — required

```bash
git worktree add ../chesssrs-persist-fix-13 -b fix/persist-fix-13-timezone-utc origin/main
cd ../chesssrs-persist-fix-13
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze
```

Branch name is `fix/persist-fix-13-timezone-utc`.

### 4.2 Failing-or-proving test first

Add a test that fails on the current code and passes after the fix. The review prescribes the scenario:

**Round-trip is UTC, not wall time**:

1. Create a `PositionKnowledgeState` (or `ReviewState` + `ReviewEvent`) with a `nextDueAt` built as a **local** `DateTime(2026,10,8,10,0,0)` (no UTC flag).
2. Persist it via `repo.savePositionKnowledgeState(state)` (or `saveAnswerBatch` + `getPositionKnowledgeState` / `getReviewState`), then read it back with `repo.getPositionKnowledgeState(canonicalId)`.
3. Assert `read.nextDueAt!.toUtc().toIso8601String() == written.nextDueAt!.toUtc().toIso8601String()` — the instant is preserved — and `read.nextDueAt!.isUtc == true` (or that the stored string ends with `Z`). Before the fix the stored string has no `Z` and `read.nextDueAt` is local; after it is `…Z` and UTC.

A stronger variant, if the test harness allows setting `TZ` or mocking `DateTime.now()` zone: write in one zone, read in another, assert the instant does not shift. Even without zone mocking, the `Z` / `isUtc` assertion is sufficient to prove the boundary is now absolute.

Also assert the JSON adapters: `reviewStateFromJson(reviewStateToJson(state)).nextDueAt!.toUtc() == state.nextDueAt!.toUtc()` and the JSON string contains `Z`.

```dart
// DOC review-4 C2 / QUALITY §3.2: due instants survive a timezone change.
// Stored form is an absolute instant (UTC), not a wall time.
```

Run targeted:

```bash
fvm flutter test test/persistence/sqlite_study_repository_test.dart --plain-name 'timestamps are UTC'
fvm flutter test test/persistence/json_adapters_test.dart --plain-name 'review state round-trip is UTC'
```

### 4.3 Implement the fix — GREEN

Edit only the files listed in §3.1-3.2 (and `lib/src/db/database.dart` if you add a formal migration comment/migration).

### 4.4 Verify

```bash
fvm flutter test test/persistence/sqlite_study_repository_test.dart --plain-name 'timestamps are UTC'
fvm flutter test test/persistence/json_adapters_test.dart --plain-name 'review state round-trip is UTC'

# Whole-file runs, once each, then stop — full suite is CI's job
fvm flutter test test/persistence/sqlite_study_repository_test.dart
fvm flutter test test/persistence/json_adapters_test.dart

fvm flutter analyze

# Commit, then gates — gates read committed diff, not working tree
# (stamp Harness/Model only in the commit/PR, never inside repo files/docs)
git add lib/src/persistence/sqlite_study_repository.dart lib/src/persistence/json_adapters.dart test/persistence/sqlite_study_repository_test.dart test/persistence/json_adapters_test.dart lib/src/db/database.dart
git commit -m "fix(persistence): store SRS instants as UTC so a timezone change does not shift due dates"
./scripts/gates.sh t1
```

Gates read `origin/main...HEAD` on committed history — a pre-commit `gates.sh t1` that reports "clean" means nothing (see `AGENTS.md` Lesson 2026-10-07). Run after committing.

### 4.5 Push & PR

```bash
git push -u origin fix/persist-fix-13-timezone-utc
gh pr create -R cassandre60/ChessSRS --title "fix(persistence): store SRS instants as UTC so a timezone change does not shift due dates" --body "Closes PERSIST-FIX-13. See docs/tasks/PERSIST-FIX-13-timezone-utc.md."
```

(Stamp `Harness:`/`Model:` only in the PR body, per `AGENTS.md` GitHub PR Attribution.)

## 5. Done when

* [ ] Every SRS instant written via `toIso8601String()` is `toUtc().toIso8601String()` (ends with `Z`); every read is `DateTime.parse(...).toUtc()` (or epoch UTC)
* [ ] `sqlite_study_repository.dart` (row builders + inline batch args + row readers) and `json_adapters.dart` (both directions) are consistent
* [ ] Tests assert round-trip preserves the instant and stored form is UTC (`Z` / `isUtc`)
* [ ] `fvm flutter analyze` 0 issues on touched files
* [ ] `./scripts/gates.sh t1` green on committed branch
* [ ] PR open against `cassandre60/ChessSRS`
