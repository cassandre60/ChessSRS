# DESKTOP-FIX-37 — Incomplete keyboard shortcuts in review training screen

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

In `lib/src/view/review/review_screen.dart:758-774`:

`_ActiveReviewViewState` currently binds only two keyboard shortcuts in `CallbackShortcuts`:
- `Space`: calls `onContinue()` when `state.isAwaitingAdvance == true`.
- `S`: calls `onRevealAnswer()` or `onSkip()`.

On desktop (Linux/macOS/Windows) and tablet with hardware keyboards, standard review workflows
are severely hindered:
1. **`Enter` and `NumpadEnter`** do nothing when awaiting advance (users naturally press Enter to continue).
2. **`ArrowRight`** does nothing when awaiting advance (chess training standard key to advance position).
3. **`Escape`** does nothing to exit/dismiss overlays.

## 2. Files to read before touching anything

1. `lib/src/view/review/review_screen.dart:755-780` — `CallbackShortcuts` bindings in `_ActiveReviewViewState`
2. `test/view/review/review_screen_test.dart` — widget tests for review screen

## 3. The fix

In `lib/src/view/review/review_screen.dart`, expand the `CallbackShortcuts` map:

```dart
CallbackShortcuts(
  bindings: <ShortcutActivator, VoidCallback>{
    const SingleActivator(LogicalKeyboardKey.space): () {
      if (state.isAwaitingAdvance) onContinue();
    },
    const SingleActivator(LogicalKeyboardKey.enter): () {
      if (state.isAwaitingAdvance) onContinue();
    },
    const SingleActivator(LogicalKeyboardKey.numpadEnter): () {
      if (state.isAwaitingAdvance) onContinue();
    },
    const SingleActivator(LogicalKeyboardKey.arrowRight): () {
      if (state.isAwaitingAdvance) onContinue();
    },
    const SingleActivator(LogicalKeyboardKey.keyS): () {
      if (state.canReveal) {
        onRevealAnswer();
      } else if (state.canSkip) {
        onSkip();
      }
    },
  },
  child: ...
)
```

### 3.1 Add widget test

In `test/view/review/review_screen_test.dart`, add a test verifying that pressing Enter and ArrowRight
advances the review position when awaiting advance:

```dart
testWidgets('pressing Enter or ArrowRight advances when awaiting advance', (tester) async {
  // Setup review screen awaiting advance
  ...
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
  // verify advanced
});
```

### What NOT to change

* Do not change piece movement logic or drag/drop behavior.
* Do not interfere with text input fields (e.g. search or edit dialogs).
* Do not touch `SPEC.md`, `GATES.md`, `.gates/`, `pubspec.yaml`.

## 4. Verification

```bash
git worktree add ../chesssrs-desktop-fix-37 -b fix/desktop-fix-37-keyboard-shortcuts origin/main
cd ../chesssrs-desktop-fix-37
fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter test test/view/review/review_screen_test.dart
fvm flutter analyze

git add lib/src/view/review/review_screen.dart test/view/review/review_screen_test.dart
git commit -m "fix(desktop): bind Enter, NumpadEnter, and ArrowRight to review advance"
./scripts/gates.sh t1
git push -u origin fix/desktop-fix-37-keyboard-shortcuts
gh pr create -R cassandre60/ChessSRS --title "fix(desktop): bind Enter and ArrowRight to review advance" --body "Closes DESKTOP-FIX-37."
```

## 5. Done when

* [ ] `Enter`, `NumpadEnter`, and `ArrowRight` trigger `onContinue` when awaiting advance
* [ ] Widget test covers keyboard advance
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green
* [ ] PR open against `cassandre60/ChessSRS`
