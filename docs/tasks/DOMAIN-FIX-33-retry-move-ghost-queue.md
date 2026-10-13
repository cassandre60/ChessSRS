# DOMAIN-FIX-33 — WITHDRAWN — retryMove ghost queue (intended retest contract)

> **Status 2026-10-13: withdrawn after verification against domain contract. Do not implement.**
> The premise of DOMAIN-FIX-33 contradicts the intentional spaced-repetition design.
> A lapsed item is intentionally re-tested at the end of the session, even if immediately
> reguessed/retried. Removing it broke 3 existing tests.
> This file is kept as an audit trail — read §1 before doing anything.

## 1. Withdrawal notice (read first)

In spaced repetition (Listudy, Anki, chessrs), an immediate reguess after a lapse only proves
working memory (the move was just shown or guessed 5 seconds ago). The item is intentionally
kept in the re-test queue so it is tested again at the end of the session to ensure actual
retention.

See `test/review/review_controller_test.dart:525-535`:
```dart
// Reguess correctly: proves the move was seen, but the re-test is still
// pending, so dues must NOT drop yet (the screen still shows a prompt).
final retry = await controller.onUserMove(const NormalMove(from: Square.d2, to: Square.d4));
expect(retry, isNotNull);
expect(retry!.isCorrect, isTrue);
state = container.read(reviewControllerProvider).requireValue;
expect(state.currentPrompt, isNotNull);
expect(state.totalDueCount, 1);

// Answer the re-test correctly first-try: now the item resolves.
final retest = await controller.onUserMove(const NormalMove(from: Square.d2, to: Square.d4));
expect(retest, isNotNull);
expect(retest!.isCorrect, isTrue);
state = container.read(reviewControllerProvider).requireValue;
expect(state.totalDueCount, 0);
```

Removing the decision from the queue on `retryMove` broke 3 existing tests:
- `test/review/review_controller_test.dart:531` (`ReviewController lapsed item is re-tested: dues drop when the re-test is answered`)
- `test/view/review/review_screen_test.dart:330` (`displays lapse feedback and allows user to reguess on the board`)
- `test/view/review/review_screen_test.dart:439` (`Reveal answer plays the study move and continues the session`)

The brief is withdrawn.

---

## 2. Original flawed proposal (archived)

In `lib/src/domain/review/review_session.dart:480-488` and `526-539`:

When a user makes an incorrect move, lines 482–488 re-queue the failed decision to
`_dueQueue` / `_unbufferedQueue` so the position is re-tested at the end of the session:
```dart
_dueQueue.add(prompt.decision);
_pendingRetest.add(prompt.decision.canonicalId);
```

If the user immediately retries via `retryMove` and plays the correct move, lines 531–532
remove the canonical ID from `_pendingRetest` and advance along the repertoire tree:
```dart
_pendingRetest.remove(prompt.decision.canonicalId);
```

**Bug:** `retryMove` does NOT remove `prompt.decision` from `_dueQueue` or `_unbufferedQueue`!
The failed decision remains sitting in the queue. Later in the same session, that same decision
is popped a second time as a fresh prompt, forcing the user to review the position an unnecessary
extra time.

## 2. Files to read before touching anything

1. `lib/src/domain/review/review_session.dart:475-545` — `submitMove` (lapse path) and `retryMove`
2. `lib/src/domain/review/review_session.dart:735-770` — `_advanceToNextPrompt` (how `_dueQueue` is consumed)
3. `test/review/review_engine_test.dart:1066-1120` — existing `retryMove` tests
4. `QUALITY.md` INV-001 (active recall loop integrity)

## 3. The fix

In `lib/src/domain/review/review_session.dart`, inside `retryMove`, when the move matches
(`expectedMatch != null`):

```dart
// Remove the decision from pending queues since the user resolved it via retry
_dueQueue.removeWhere((d) => d.id == prompt.decision.id);
_unbufferedQueue.removeWhere((d) => d.id == prompt.decision.id);
_pendingRetest.remove(prompt.decision.canonicalId);
```

Also verify whether `_queue` needs cleanup if the item was already buffered:
```dart
_queue.removeWhere((p) => p.decision.id == prompt.decision.id);
```

Check how `_dueQueue` and `_unbufferedQueue` are defined in `ReviewSession` (lines ~50-80) to use
exact field names.

### What NOT to change

* Do not change the lapse recording on initial failure (`submitMove`). The lapse count still increments.
* Do not change `retryMove` failure behavior (playing wrong move on retry).
* Do not touch `SPEC.md`, `GATES.md`, `.gates/`, `pubspec.yaml`.

## 4. Verification

### 4.1 Worktree setup

```bash
git worktree add ../chesssrs-domain-fix-33 -b fix/domain-fix-33-retry-ghost-queue origin/main
cd ../chesssrs-domain-fix-33
fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs
```

### 4.2 RED test

Add a unit test in `test/review/review_engine_test.dart`:

```dart
test('successful retryMove removes decision from due queue so it is not prompted again', () {
  // Create a session with 1 decision
  final decision = makeDecision('d1', 'e2e4');
  final session = makeSession([decision]);

  // Submit wrong move -> lapse
  final step1 = session.submitMove('d2d4');
  expect(step1.isCorrect, isFalse);

  // Successful retry
  final step2 = session.retryMove('e2e4');
  expect(step2.isCorrect, isTrue);

  // Advance -> queue should be empty, session should be complete
  session.advance();
  expect(session.currentPrompt, isNull);
  expect(session.isComplete, isTrue);
});
```

Verify RED on pre-fix code (without the fix, `session.advance()` re-prompts `d1` and `isComplete` is false).
Apply the fix -> verify GREEN.

### 4.3 Verify

```bash
fvm flutter test test/review/review_engine_test.dart --plain-name 'successful retryMove removes decision'
fvm flutter test test/review/review_engine_test.dart
fvm flutter analyze

git add lib/src/domain/review/review_session.dart test/review/review_engine_test.dart
git commit -m "fix(review): remove retried decision from due queue on successful retryMove"
./scripts/gates.sh t1
git push -u origin fix/domain-fix-33-retry-ghost-queue
gh pr create -R cassandre60/ChessSRS --title "fix(review): remove retried decision from queue on retryMove" --body "Closes DOMAIN-FIX-33."
```

## 5. Done when

* [ ] `retryMove` removes the retried decision from `_dueQueue`, `_unbufferedQueue`, and `_queue`
* [ ] Unit test proves queue is clean after retry and session completes without ghost prompt
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green
* [ ] PR open against `cassandre60/ChessSRS`
