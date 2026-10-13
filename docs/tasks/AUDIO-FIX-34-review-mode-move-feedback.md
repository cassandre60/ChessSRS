# AUDIO-FIX-34 — Review mode has zero sound or haptic feedback on user moves

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

In `lib/src/review/review_controller.dart`:

Move audio and haptic feedback is provided by `MoveFeedbackService` (via `moveFeedbackServiceProvider`).
Currently, `moveFeedback` is only called:
- Line ~997 for auto-played opponent replies.
- Line ~1361 for animated incoming pre-moves.

When the user moves a piece (`onUserMove` lines 1176–1250, `_handleCorrectAdvancement` lines 912–959):
**`moveFeedback` is NEVER called!**

Every user move in review training is completely silent with no haptics. In contrast, `StudyController`
and `AnalysisController` both trigger `moveFeedback(isCapture: isCapture)` whenever a piece moves.

## 2. Files to read before touching anything

1. `lib/src/review/review_controller.dart:910-970` — `_handleCorrectAdvancement`
2. `lib/src/review/review_controller.dart:1175-1250` — `onUserMove`
3. `lib/src/model/common/service/move_feedback_service.dart` — `MoveFeedbackService` API
4. `lib/src/model/analysis/analysis_controller.dart` — see how `moveFeedback` is called on player moves

## 3. The fix

In `lib/src/review/review_controller.dart`:

### 3.1 Play feedback on correct user move

In `_handleCorrectAdvancement` (or right after move validation in `onUserMove`):

```dart
// Check if move is capture from move data or board state
final isCapture = move.isCapture ?? false; // or determine from current position
ref.read(moveFeedbackServiceProvider).moveFeedback(isCapture: isCapture);
```

### 3.2 Add error feedback on incorrect move (lapse)

In `onUserMove`, when the move is incorrect (`!step.isCorrect`):

```dart
ref.read(moveFeedbackServiceProvider).errorFeedback(); // or HapticFeedback.vibrate()
```
Check what methods `MoveFeedbackService` exposes (e.g. `moveFeedback`, `errorFeedback`, etc.) and use the standard method.

### What NOT to change

* Do not change sound settings logic (`soundPreferencesProvider`).
* Do not change opponent reply audio (already working at line 997).
* Do not touch `SPEC.md`, `GATES.md`, `.gates/`, `pubspec.yaml`.

## 4. Verification

```bash
git worktree add ../chesssrs-audio-fix-34 -b fix/audio-fix-34-review-move-feedback origin/main
cd ../chesssrs-audio-fix-34
fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter test test/review/review_controller_test.dart
fvm flutter analyze

git add lib/src/review/review_controller.dart
git commit -m "fix(audio): trigger move feedback sound and haptics on user moves in review mode"
./scripts/gates.sh t1
git push -u origin fix/audio-fix-34-review-move-feedback
gh pr create -R cassandre60/ChessSRS --title "fix(audio): trigger move feedback on user moves in review" --body "Closes AUDIO-FIX-34."
```

## 5. Done when

* [ ] User moves in review mode invoke `moveFeedback` with capture detection
* [ ] Incorrect moves trigger error feedback
* [ ] Existing review controller tests pass
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green
* [ ] PR open against `cassandre60/ChessSRS`
