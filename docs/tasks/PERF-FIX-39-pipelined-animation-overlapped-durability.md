# PERF-FIX-39 — Pipeline move persistence with board animation for zero-latency touch response

## 1. Why this is a brief at all

Currently, when a user releases a piece on the board, `ReviewController.submitMove`
executes the following sequence:

```dart
// Line 1303 in lib/src/review/review_controller.dart:
final result = await _service.submitMove(from: from, to: to, promotion: promotion);

if (result.isCorrect) {
  await _handleCorrectAdvancement(
    currentState: currentState,
    result: result,
    userMove: move,
    isFirstAttempt: true,
  );
}
```

Inside `_service.submitMove`:
```dart
await repository.saveAnswerBatch(knowledgeStates: allKStates, event: result.event);
```

And inside `_handleCorrectAdvancement`:
```dart
// 1. Immediately show user's move on the board
state = AsyncData(
  currentState.copyWith(
    boardPosition: posAfterUser ?? currentState.boardPosition,
    ...
  ),
);
```

### The flaw
The UI does not display the user's move on the board until **after** SQLite
finishes writing the answer batch to disk!
- Even with WAL mode, SQLite disk writes take 2–6 ms.
- If background I/O or a checkpoint occurs, disk latency can spike to 15–30 ms.
- During this window, the user's finger has physically left the screen, but the
  piece sits frozen on its origin or mid-drag square waiting for SQLite before
  snapping to its destination square.
- This creates perceptible input drag.

## 2. Read before touching anything

1. `lib/src/review/review_controller.dart` — `submitMove`, `_handleCorrectAdvancement`.
2. `lib/src/review/review_service.dart` — `submitMove`, `session.submitMove`.
3. SPEC **INV-001**:
   > An acknowledged review answer survives process restart. Every review
   > answer, whether correct or incorrect, is committed to SQLite before the
   > user moves to the next card or leaves the screen.
4. `QUALITY.md §1.5`:
   > The in-memory session mutation and its persistence are transactional from
   > the caller's perspective: if the write fails, the session is rolled back
   > to its pre-answer state before the error is rethrown.
5. `QUALITY.md §4.1`:
   > Move response time < 16 ms.

## 3. The Solution: Overlapped Visuals & Durability

We can achieve **0.00 ms perceived move latency** without violating INV-001 or
loosening durability:

1. **Step 1 (Immediate UI feedback on frame 0):**
   When the user drops the piece, validate the move in memory via
   `session.submitMove` (which takes < 0.05 ms in pure Dart).
   Update `state = AsyncData(currentState.copyWith(boardPosition: posAfterUser))`
   immediately so the piece snaps to the target square on the very next display
   frame (120 FPS / 8.3 ms).
2. **Step 2 (Pipelined Persistence):**
   Start `repository.saveAnswerBatch(...)` asynchronously in parallel with the
   piece placement and audio cue.
3. **Step 3 (Durability Gate before Next Card):**
   `await` the persistence future *before* advancing to `nextPrompt`.
   - The user watches their move land and the opponent reply animate (150–250 ms).
   - SQLite finishes its write (2 ms) long before the visual animation completes.
   - If the write fails, roll back the board state and session checkpoint per
     `QUALITY.md §1.5`.

### Why this satisfies every invariant:
- **`INV-001` is 100% satisfied**: The persistence is fully committed to SQLite
  before the user can interact with the next card or leave the screen.
- **`QUALITY.md §1.5` is 100% satisfied**: Rollback semantics are preserved if
  the write throws.
- **Zero perceived latency**: The 2–6 ms disk latency is completely hidden
  behind the visual frame.

## 4. Verification Steps

1. Run review move latency tests:
   ```bash
   fvm flutter test test/review/move_latency_test.dart
   fvm flutter test test/review/review_controller_test.dart
   ```
2. Verify rollback on persistence failure:
   Ensure `_ToggleFailureRepository` tests in `review_service_test.dart` still
   pass and verify that a persistence error restores the checkpoint.
3. Runtime validation (`fvm flutter run -d linux`):
   Play rapid moves in review mode. Confirm pieces snap instantly to their
   squares with zero perceptible drag.

## 5. What counts as done

- User piece snaps to target square on the frame immediately following pointer release.
- SQLite write is initiated concurrently and awaited before card advance.
- All tests in `test/review/move_latency_test.dart` and `test/review/review_controller_test.dart` pass.
- `./scripts/gates.sh t1` passes.
