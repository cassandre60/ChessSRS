# PERF-FIX-21 — getDueSummary loads entire review-state table on every scope change

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

`ReviewService.getDueSummary` (`lib/src/review/review_service.dart:401-655`) is
called on every startup, scope change, study toggle, and study delete. Line 411:

```dart
final reviewStatesList = await repository.getAllReviewStates();
```

`getAllReviewStates` (`lib/src/persistence/sqlite_study_repository.dart:738-751`)
loads **every row** from both `srs_review_state` and `position_knowledge_state`
into a `Map<String, ReviewState>` in memory. For a user with 10k decisions this
transfers ~10k+ rows of 8 fields each, deserializes DateTime strings, and builds a
map — on every scope tap.

What `getDueSummary` actually needs from each state: only `isDueAt(now)` and
`repetitionCount > 0`. That is `(decisionId, nextDueAt, repetitionCount)` — 3 of
8 fields, and only the rows matching the decisions in scope.

`startSession` already demonstrates the targeted pattern: it uses
`getReviewStatesByDecisions(allQueryIds)` + `getKnowledgeStatesByCanonicalIds`
(lines 226-234), not `getAllReviewStates`. `getDueSummary` is the only production
caller of the full-table method.

## 2. Files to read before touching anything

1. `lib/src/review/review_service.dart:401-655` — `getDueSummary` (the caller)
2. `lib/src/persistence/sqlite_study_repository.dart:738-751` — `getAllReviewStates`
3. `lib/src/persistence/sqlite_study_repository.dart:764-783` — `getReviewStatesByDecisions` (targeted alternative)
4. `lib/src/persistence/sqlite_study_repository.dart:594-615` — `getKnowledgeStatesByCanonicalIds` (targeted)
5. `lib/src/domain/review_state.dart:61-63` — `isDueAt`, `isNew`, `isLearned`
6. `test/review/review_service_test.dart:306-400` — `getDueSummary` tests

## 3. The fix

Replace the full-table `getAllReviewStates()` call with a targeted query that
fetches only what `getDueSummary` needs.

### Option A — reuse existing targeted methods (minimal new code)

`getDueSummary` already loads `allDecisions` (line 410). Extract the decision ids
and canonical ids, then use the same pattern `startSession` uses:

```dart
// BEFORE
final reviewStatesList = await repository.getAllReviewStates();
final reviewStates = {for (final s in reviewStatesList) s.decisionId: s};

// AFTER — targeted, same as startSession lines 226-234
final decisionIds = allDecisions.map((d) => d.id).toList();
final canonicalIds = allDecisions.map((d) => d.canonicalId).toSet().toList();
final allQueryIds = {...decisionIds, ...canonicalIds}.toList();
final reviewStatesList = await repository.getReviewStatesByDecisions(allQueryIds);
final reviewStates = {for (final s in reviewStatesList) s.decisionId: s};
final kStates = await repository.getKnowledgeStatesByCanonicalIds(canonicalIds);
for (final k in kStates) {
  reviewStates[k.canonicalId] = k.toReviewState();
}
```

This replaces two full-table scans with two chunked `IN` queries. For 10k
decisions the `IN` chunks are 25 × 400 items — faster than 10k+ row
deserialization, and scales with scope, not with total database size.

### Option B — projected query (fewer bytes, new method)

Add a `getReviewSummaryProjection(List<String> ids)` that returns only
`(decisionId, nextDueAt, repetitionCount)` as a lightweight record. Avoids
deserializing stability/difficulty/timestamps that `getDueSummary` never reads.
More work, higher payoff. Preferred for large repertoires but harder for an agent
to test — Option A is the safe default.

### What NOT to change

* Do not change `getAllReviewStates` — other consumers may exist in tests.
* Do not change the single-pass tally loop (lines 490-587) — this brief fixes the
  *input* (what is loaded from SQLite), not the *aggregation* (how it is counted).
* Do not touch `SPEC.md`, `GATES.md`, `.gates/`, `pubspec.yaml`.
* Do not bundle with `PERSIST-FIX-16` (rename) — separate PR.

## 4. Verification

```bash
git worktree add ../chesssrs-perf-fix-21 -b fix/perf-fix-21-due-summary-targeted origin/main
cd ../chesssrs-perf-fix-21
fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs

# Targeted test
fvm flutter test test/review/review_service_test.dart --plain-name 'getDueSummary'
fvm flutter test test/review/review_service_test.dart  # whole file once
fvm flutter test test/review/review_side_scope_test.dart

fvm flutter analyze

git add lib/src/review/review_service.dart
git commit -m "perf(review): targeted review-state query in getDueSummary instead of full-table load"
./scripts/gates.sh t1
git push -u origin fix/perf-fix-21-due-summary-targeted
gh pr create -R cassandre60/ChessSRS --title "perf(review): targeted review-state query in getDueSummary" --body "Closes PERF-FIX-21."
```

## 5. Done when

* [ ] `getDueSummary` no longer calls `getAllReviewStates()` — uses targeted `getReviewStatesByDecisions` + `getKnowledgeStatesByCanonicalIds`
* [ ] `rg getAllReviewStates lib/src/review/` returns 0 hits
* [ ] All `getDueSummary` tests + side-scope tests pass unchanged
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green
* [ ] PR open against `cassandre60/ChessSRS`
