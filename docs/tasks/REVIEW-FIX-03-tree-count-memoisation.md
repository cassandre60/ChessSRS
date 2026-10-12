# REVIEW-FIX-03 — Unbounded recomputation of due counts in subtree selection

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

`ReviewSession._selectOpponentChild` and `_selectUserContinuation` pick the
opponent's reply / user's auto-play continuation during auto-traversal. Each
calls `_countDueDecisionsInSubtree` per child, per level:

`lib/src/domain/review/review_session.dart:911-982`

```dart
RepertoireNode _selectOpponentChild(RepertoireNode node, DateTime now) {
  final dueCounts = <RepertoireNode, int>{};
  for (final child in node.children) {
    dueCounts[child] = _countDueDecisionsInSubtree(child, now); // walks whole subtree
  }
  // ... then picks weighted, or falls back to _nodeCountCache for subtree sizes
}

int _countDueDecisionsInSubtree(RepertoireNode node, DateTime now) {
  var count = 0;
  final decision = _decisionForNode[node.id];
  if (decision != null) {
    final state = _reviewStates[decision.canonicalId] ?? _reviewStates[decision.id];
    final isDue = mode == ReviewMode.practice || state == null || state.isDueAt(now);
    if (isDue) count++;
  }
  for (final child in node.children) {           // recursion — O(N) per call
    count += _countDueDecisionsInSubtree(child, now);
  }
  return count;
}
```

`_nodeCountCache` memoises only total node counts (`_countNodesInSubtree`), not
due counts. So for a tree with depth D and branching B, a single `submitMove`
that auto-traverses L levels pays roughly `O(B * N_subtree)` per level, where
`N_subtree` is the size of each child's subtree — and overlapping subtrees are
re-walked repeatedly with no memo. On a 12-chapter imported repertoire with deep
variations this is visibly slow ( frame drops, late opponent animation ).

Due counts depend on `now` (via `isDueAt(now)`) and on `_reviewStates` mutations
after each `submitMove`. They are stable *within* one `submitMove` call.

## 2. Files to read before touching anything

1. `lib/src/domain/review/review_session.dart:911-990` — the two selectors + counters + cache
2. `lib/src/domain/review/review_session.dart:554-697` — `_continueWithCorrectMove` (the caller in a loop)
3. `lib/src/domain/review_state.dart` — `ReviewState.isDueAt`
4. `lib/src/domain/review/review_mode.dart` — practice bypasses due check
5. `test/review/review_session_test.dart` and `test/domain/*` — due-aware selection tests
   (search `selectOpponentChild`, `due-aware`, `weighted`)
6. `docs/tech-debt-inventory.md` item P-1 (if present) — prior analysis of this hotspot

## 3. The fix

Memoise due counts for the duration of one move's traversal, keyed by `(node.id, now)`.

### Concrete shape (pick one, simplest first)

**Option A — per-call memo map (minimal diff):**

```dart
// Inside _selectOpponentChild and _selectUserContinuation, thread a Map through
// the recursion. Easiest: add a private helper that closes over a cache:

int _countDueInSubtreeMemo(RepertoireNode node, DateTime now, Map<String, int> memo) {
  final cached = memo[node.id];
  if (cached != null) return cached;
  var count = 0;
  final dec = _decisionForNode[node.id];
  if (dec != null) {
    final st = _reviewStates[dec.canonicalId] ?? _reviewStates[dec.id];
    if (mode == ReviewMode.practice || st == null || st.isDueAt(now)) count++;
  }
  for (final c in node.children) count += _countDueInSubtreeMemo(c, now, memo);
  memo[node.id] = count;
  return count;
}
```

Then `_selectOpponentChild` creates `final memo = <String,int>{};` once and uses
`_countDueInSubtreeMemo(child, now, memo)` for each child. Same for
`_selectUserContinuation` (or extract a shared helper that both call).

Do NOT make the memo a field on `ReviewSession` — it would go stale when `now`
advances or `_reviewStates` mutate. A per-traversal local map is sufficient:
one `submitMove` traversal is one `now`, and the session mutates state only
between traversals (via `GraphAwareReviewCoordinator`), so caching inside the
traversal is safe.

**Option B — reuse `_nodeCountCache` pattern with a second cache** is also valid,
but must be invalidated on `now` change / state mutation — local map is simpler
and harder to get wrong.

### Keep the existing `_nodeCountCache` for practice-mode fallback

`_selectOpponentChild`'s fallback weights by `_countNodesInSubtree` via
`_nodeCountCache` — leave it as-is. The bug is the due path, not the fallback.

### What NOT to change

* Do not change selection semantics (weighted-random, due-first) — only the cost
  of counting.
* Do not change `ReviewOrder` or queue construction.
* Do not add async/isolates — this is synchronous traversal on the review path
  (QUALITY.md §1.3 zero-latency invariant, <16ms). An isolate hop would worsen it.

## 4. How to make the work verifiable (no guessing)

### 4.1 Worktree setup — required

```bash
git worktree add ../chesssrs-review-fix-03 -b fix/review-fix-03-tree-count-memo origin/main
cd ../chesssrs-review-fix-03
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze
```

### 4.2 Failing-or-benchmark test first — RED

Two kinds of proof; provide at least one:

**(a) Correctness-preserving test** (always):

Add a test asserting that weighted due-aware selection returns the same result
before and after memoisation. Build a tree with 2 opponent children each covering
subtrees with known due counts (1 due vs 3 due), inject a `FakeClock` fixed `now`,
seed `reviewStates` so some are due, call `_selectOpponentChild` (via
`submitMove` → auto-traversal, or expose a test-only helper). Assert the due-denser
branch is preferred. This passes both before and after — run it stashed and unstashed
to prove no semantic drift.

**(b) Performance assertion** (if the repo has a latency gate):

If `test/review/move_latency_test.dart` or similar exists, ensure it stays green.
Otherwise add a micro-benchmark style correctness test that counts invocations:

* Wrap `_countDueDecisionsInSubtree` with a call counter (or add a temporary counter
  field cleared at the start of each traversal). On a tree with 100+ nodes, assert
  call count after fix is `<= N` (one visit per node) rather than `O(B*D*N)`.

Tag with invariant:

```dart
// SPEC INV-050 / QUALITY §4.1: move validation under 16ms; memoised due counts
// keep auto-traversal linear in tree size, not exponential in branching.
```

Run targeted:

```bash
fvm flutter test test/review/review_session_test.dart --plain-name 'memoised due counts'
```

### 4.3 Implement the fix — GREEN

Edit `lib/src/domain/review/review_session.dart` only.

### 4.4 Verify

```bash
fvm flutter test test/review/review_session_test.dart --plain-name 'memoised due counts'
fvm flutter test test/review/review_session_test.dart   # whole file once
# Prove no semantic drift:
git stash && fvm flutter test test/review/review_session_test.dart --plain-name 'memoised due counts'
git stash pop
fvm flutter analyze
git add lib/src/domain/review/review_session.dart test/review/review_session_test.dart
git commit -m "perf(review): memoise due counts during subtree selection"
./scripts/gates.sh t1
```

### 4.5 Push & PR

```bash
git push -u origin fix/review-fix-03-tree-count-memo
gh pr create -R cassandre60/ChessSRS --title "perf(review): memoise due counts during subtree selection" --body "Closes REVIEW-FIX-03. See docs/tasks/REVIEW-FIX-03-tree-count-memoisation.md."
```

## 5. Constraints

* Do not edit `SPEC.md`, `GATES.md`, `QUALITY.md`, `TEST_STRATEGY.md`, `AGENTS.md`,
  `pubspec.yaml`, `analysis_options.yaml`, `.gates/`, `scripts/gates/`, `.github/`.
* Pure domain layer stays pure — no Flutter/sqflite `dart:io` in `lib/src/domain/`
  (`G03` enforces it).
* One fix per PR. No drive-by refactors.
* Targeted tests only locally; full suite is CI's job (`AGENTS.md` §3.1).
* No local release builds.

## 6. Done when

* [ ] Test added proving selection semantics unchanged + traversal not exponential
* [ ] Test fails if memo removed (or call count proves linear bound)
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green on committed branch
* [ ] PR open against `cassandre60/ChessSRS`
