# PERSIST-FIX-16 — Review-state mirroring is undocumented + getReviewStatesByDecisions name misleads

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

Two polish/doc issues left from `docs/review-4-orchestration-persistence.md` D2/D4 — intentionally bundled because each is a small, docs-or-comment change that would otherwise idle an agent between PRs:

### 16a. Review-state mirroring is correct but undocumented

`lib/src/persistence/sqlite_study_repository.dart:507-558` (`saveAnswerBatch`) writes **`srs_review_state` twice per state**:

* Once keyed by the canonical SHA-1 (`:523-527`): `batch.insert(kTableSrsReviewState, _reviewStateRow(s.toReviewState(s.canonicalId)))`
* Once per occurrence via `INSERT … SELECT id … WHERE canonicalStateId = ?` (`:529-549`): `batch.rawInsert('INSERT OR REPLACE INTO srs_review_state SELECT id, … FROM srs_decision WHERE canonicalStateId = ?')`

Verified sound — the read path (`lib/src/review/review_service.dart:226-234`) queries `{...decisionIds, ...canonicalIds}` and then overlays from `getKnowledgeStatesByCanonicalIds`, and `ReviewSession` looks up `_reviewStates[decision.canonicalId] ?? _reviewStates[decision.id]`. But it is **undocumented** and doubles the row volume on that table for no stated reason. The next maintainer has no way to know the double write is deliberate without reading the review. `docs/review-4-orchestration-persistence.md` D2 says: *"Worth a comment saying the mirroring is deliberate and what reads depend on it."*

### 16b. `getReviewStatesByDecisions` name says decisions but half the argument is canonical ids

`lib/src/persistence/study_repository.dart:93` + `sqlite_study_repository.dart:764-783` declare/implement `getReviewStatesByDecisions(List<String> decisionIds)`. `lib/src/review/review_service.dart:226-229` calls it with **`{...decisionIds, ...canonicalIds}`** — correct, given the mirroring in 16a, and the service even seeds a second read from `getKnowledgeStatesByCanonicalIds`. But the name says "by decisions" while half the argument is canonical ids, so the behaviour is right but the name misleads. D4 says: *"The name will mislead whoever maintains it next."*

## 2. Files to read before touching anything

1. `lib/src/persistence/sqlite_study_repository.dart:507-560, 738-785` — `saveAnswerBatch` double write + `getAllReviewStates` / `getReviewStatesByDecisions`
2. `lib/src/persistence/study_repository.dart:91-93` — `getAllReviewStates`, `getDueReviewStates`, `getReviewStatesByDecisions` declarations
3. `lib/src/review/review_service.dart:226-234` — the `{...decisionIds, ...canonicalIds}` call site + the `getKnowledgeStatesByCanonicalIds` overlay
4. `lib/src/domain/review/review_session.dart` — session lookup `_reviewStates[decision.canonicalId] ?? _reviewStates[decision.id]` (confirms both key kinds resolve)
5. `test/persistence/sqlite_study_repository_test.dart` — existing tests for `getReviewStatesByDecisions` / `getKnowledgeStatesByCanonicalIds`
6. `docs/review-4-orchestration-persistence.md` D2/D4 — the two findings as filed

## 3. The fix

Two small changes, same PR — both are doc/naming polish, neither changes scheduling:

### 3.1 Document the mirroring (16a)

Add a doc comment at the `saveAnswerBatch` double-write, and a brief comment at the service read site, both naming the contract:

In `lib/src/persistence/sqlite_study_repository.dart` above `saveAnswerBatch`:

```dart
/// Persists an answer's canonical state **and** its per-occurrence mirrors.
///
/// `srs_review_state` is written **twice per state** on purpose:
///
/// 1. Once keyed by the canonical id (shared position knowledge — one row
///    per unique position).
/// 2. Once per occurrence via `SELECT id FROM srs_decision WHERE canonicalStateId = ?`
///    (one row per `srs_decision.id` that reaches the same position via a
///    transposition). Reads query both key kinds
///    (`review_service.dart: getReviewStatesByDecisions({…decisionIds, …canonicalIds})`
///    plus `getKnowledgeStatesByCanonicalIds`) and the session looks up
///    `reviewStates[canonicalId] ?? reviewStates[decisionId]`. Doubling the
///    row volume is deliberate and what keeps transposition reads coherent.
Future<void> saveAnswerBatch({ ... }) async { … }
```

And a one-line comment at the two writes inside it, e.g. `// canonical mirror` / `// per-occurrence mirrors (transpositions)`.

No logic change.

### 3.2 Rename to reflect that it accepts both key kinds (16b)

Rename `getReviewStatesByDecisions` → **`getReviewStatesByIds`** (or `getReviewStatesByDecisionOrCanonicalIds` if the team prefers verbosity). Apply consistently to:

* Declaration: `lib/src/persistence/study_repository.dart:93`
* Implementation: `lib/src/persistence/sqlite_study_repository.dart:764-783`
* Call site: `lib/src/review/review_service.dart:229`

Keep the method signature `(List<String> ids)` — same `List<String>` — only the name changes. If the repo uses a deprecation policy for repository names, add a one-line forwarding shim `@Deprecated` for one release; otherwise rename directly (no production callers outside the repo).

Also update the declaration comment to state: *"Reads from `srs_review_state` for any of the given ids, which may be per-occurrence `decisionId`s **or** canonical ids — see `saveAnswerBatch`'s mirroring."*

### 3.3 What NOT to change

* Do not change `saveAnswerBatch` double-write behaviour — document it only.
* Do not change `getAllReviewStates` / `getDueReviewStates`.
* Do not bundle with `PERSIST-FIX-13` / `PERSIST-FIX-14` — those are data-loss fixes, this is docs/naming.
* Do not touch `SPEC.md`, `GATES.md`, protected paths. Commit only lib + tests where the name appears.

## 4. How to make the work verifiable (no guessing)

### 4.1 Worktree setup — required

```bash
git worktree add ../chesssrs-persist-fix-16 -b fix/persist-fix-16-mirroring-docs-rename origin/main
cd ../chesssrs-persist-fix-16
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze
```

Branch name is `fix/persist-fix-16-mirroring-docs-rename`.

### 4.2 Proving test — grep + existing tests

This is a docs/rename. The proof is static + existing tests still green:

```bash
rg -n "getReviewStatesByDecisions" lib/ test/
# after: no hits (or one @Deprecated shim if used)

rg -n "canonical.*mirror|occurrence.*mirror|transposition.*mirror" lib/src/persistence/sqlite_study_repository.dart lib/src/review/review_service.dart
# after: hits — the new comments

fvm flutter test test/persistence/sqlite_study_repository_test.dart --plain-name 'review states by'
fvm flutter test test/persistence/sqlite_study_repository_test.dart  # whole file once
fvm flutter analyze
```

No new test file required — the existing `getReviewStatesByDecisions` tests now exercise `getReviewStatesByIds` under the new name and must still pass (rename without behaviour change).

### 4.3 Implement the fix — GREEN

Edit only the files listed in §3.1-3.2 (+ any test that references the old name).

### 4.4 Verify

```bash
rg -rn "getReviewStatesByDecisions" lib/ test/    # 0 hits (or shim only)
fvm flutter test test/persistence/sqlite_study_repository_test.dart
fvm flutter analyze
git add lib/src/persistence/study_repository.dart lib/src/persistence/sqlite_study_repository.dart lib/src/review/review_service.dart test/persistence/sqlite_study_repository_test.dart
git commit -m "docs(persistence): document review-state mirroring and rename getReviewStatesByDecisions → getReviewStatesByIds"
./scripts/gates.sh t1
```

Gates read committed diff — run after committing (pre-commit is not evidence).

### 4.5 Push & PR

```bash
git push -u origin fix/persist-fix-16-mirroring-docs-rename
gh pr create -R cassandre60/ChessSRS --title "docs(persistence): document review-state mirroring and rename getReviewStatesByDecisions → getReviewStatesByIds" --body "Closes PERSIST-FIX-16. See docs/tasks/PERSIST-FIX-16-review-state-mirroring-docs-and-rename.md."
```

(Stamp `Harness:`/`Model:` only in the PR body.)

## 5. Done when

* [ ] `saveAnswerBatch` carries a doc comment naming the double write, canonical vs per-occurrence, and the read sites that depend on it
* [ ] `getReviewStatesByDecisions` renamed → `getReviewStatesByIds` (or longer canonical-explicit name) across declaration, impl, and call site
* [ ] `rg getReviewStatesByDecisions lib/ test/` is clean (or shim only)
* [ ] Existing persistence tests green (rename without behaviour change)
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green on committed branch
* [ ] PR open against `cassandre60/ChessSRS`
