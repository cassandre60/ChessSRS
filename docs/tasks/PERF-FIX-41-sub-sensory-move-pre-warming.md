# PERF-FIX-41 — Sub-sensory move feedback pre-warming on drag start

## 1. Why this is a brief at all

In a review session, user interaction follows a physical sequence:
1. **Pointer Down / Drag Start ($t = 0\text{ ms}$)**: User touches a piece (e.g. Pawn on `e2`).
2. **Physical Transit Time ($t = 80\text{ to }200\text{ ms}$)**: User's finger physically drags across the glass toward `e4`.
3. **Pointer Up / Release ($t = 150\text{ ms}$)**: Piece is released on `e4`, triggering `onUserMove`.

Currently, the application does 100% of its work at $t = 150\text{ ms}$:
- Validates legality against the dartchess `Position`.
- Matches the move against `prompt.expectedMoves`.
- Computes `pos.play(move)` to generate the updated board state.
- Formats SAN strings and resolves commentary.
- Plays sound and haptic effects via `_playMoveFeedback(position, move)`.

This creates a burst of CPU work and audio trigger latency at the exact moment
the user expects the piece to settle.

## 2. The Opportunity

During the 80–200 ms transit window while the user is dragging:
The active `ReviewPrompt` already has its expected repertoire continuations in
memory:
```dart
prompt.decision.expectedMoves // e.g. [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')]
```

If the touched piece origin matches `expectedMoves.first.from`:
- The expected destination square is already known (`'e4'`).
- The resulting position `pos.play(expectedMove)` can be computed **during drag start**.
- The audio feedback (move sound vs capture sound) can be pre-determined.

When the finger releases on `e4`:
The resulting position, sound effect, and commentary resolution are already hot
in L1 cache. The board updates with zero computation latency.

## 3. Read before touching anything

1. `lib/src/review/review_controller.dart` — `onUserMove`, `_playMoveFeedback`.
2. `lib/src/view/review/review_screen.dart` — `BoardWidget.onMove`.
3. `QUALITY.md §4.1`:
   > Move response time < 16 ms.

## 4. Implementation Steps for Agent

1. In `ReviewController`, add an optional lightweight pre-warm hook:
   ```dart
   void prewarmMoveCandidate(String fromSquare) {
     final prompt = state.asData?.value.currentPrompt;
     if (prompt == null) return;
     final expected = prompt.expectedMoves.firstOrNull;
     if (expected != null && expected.from == fromSquare) {
       // Pre-calculate destination position and audio cues in background
       _prewarmedPosition = state.asData?.value.boardPosition?.play(expected.toMove());
       _prewarmedIsCapture = ...;
     }
   }
   ```
2. Connect drag-start in `BoardWidget` / `ReviewScreen` to notify the controller
   of the touched origin square.
3. In `onUserMove`, if the played move matches the pre-warmed candidate, reuse
   the precomputed `_prewarmedPosition` and feedback cues directly.

## 5. Verification Steps

1. Verify move latency tests:
   ```bash
   fvm flutter test test/review/move_latency_test.dart
   ```
2. Verify all review controller tests pass:
   ```bash
   fvm flutter test test/review/review_controller_test.dart
   ```
3. Runtime validation on desktop:
   Play fast moves. Verify sound, haptics, and move registration are
   imperceptibly instantaneous.

## 6. What counts as done

- Move destination state is pre-calculated during the physical drag phase.
- All existing tests in `move_latency_test.dart` and `review_controller_test.dart` pass.
- `./scripts/gates.sh t1` passes after commit.
