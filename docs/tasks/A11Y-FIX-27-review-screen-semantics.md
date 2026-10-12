# A11Y-FIX-27 — Review training screen lacks semantic labels for screen readers

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

The core review training screen (`lib/src/view/review/review_screen.dart`) is the
most-used surface in the app, but a screen reader user can interact with almost
nothing on it:

| Element | Line | A11y status |
|---------|------|-------------|
| Chessboard (the position being quizzed) | ~650 | No `semanticLabel` — the board is a custom `RenderBox` with no text alternative |
| Move prompt ("Your move as White") | ~720 | No `Semantics` wrapper — invisible to TalkBack/VoiceOver |
| "Tap to continue" overlay | ~810 | `GestureDetector` with no `semanticLabel` — screen reader cannot discover or activate it |
| Answer slot / expected move reveal | ~1058 | No `Semantics` — the "correct answer was Nf3" feedback is visual only |
| Progress indicator (due count) | ~900 | No `semanticLabel` — the bar is a `CustomPaint` ≡ silent |
| Verdict announcement | ~1049 | `_VerdictLiveRegion` with `Semantics(liveRegion: true)` — **this is the only accessible element** ✓ |

A screen reader user hears the verdict but cannot identify the position, the
expected move, or the progress. The chessboard itself is a chessground
`BoardWidget` — adding `Semantics` at that level is a chessground concern, but
the contextual labels (prompt, overlay, answer, progress) are our responsibility.

## 2. Files to read before touching anything

1. `lib/src/view/review/review_screen.dart:600-1100` — the training area widgets
2. `lib/src/view/review/review_screen.dart:1049` — `_VerdictLiveRegion` (existing pattern)
3. `lib/src/widgets/board.dart` — `BoardWidget` wrapper (check if it already has a `Semantics` parameter)
4. `design/docs/04-screens-and-flows.md` §4 (review session screen) — what the user should see/hear
5. `QUALITY.md` — any a11y invariants (WCAG)
6. `test/view/review/review_screen_test.dart` — existing tests

## 3. The fix

Add `Semantics` wrappers to the 5 unlabeled elements. Do NOT modify
`chessground` or `BoardWidget` — wrap at the review-screen level.

### 3.1 Move prompt

```dart
// BEFORE (approximate — read the actual widget first)
Text('Your move as White', style: ...)

// AFTER
Semantics(
  label: 'Your move as White',
  child: Text('Your move as White', style: ...),
)
```

### 3.2 "Tap to continue" overlay

```dart
// BEFORE
GestureDetector(
  onTap: controller.advance,
  child: Container(color: Colors.transparent),
)

// AFTER
Semantics(
  button: true,
  label: 'Tap to continue to next position',
  child: GestureDetector(
    onTap: controller.advance,
    child: Container(color: Colors.transparent),
  ),
)
```

### 3.3 Answer slot (expected move reveal)

```dart
// After the verdict, when the correct answer is shown:
Semantics(
  liveRegion: true,  // announce when it appears
  label: 'Expected move: ${expectedMoveSan}',
  child: /* existing answer widget */,
)
```

### 3.4 Progress indicator

```dart
Semantics(
  label: '${completedCount} of ${totalCount} positions reviewed',
  child: /* existing progress bar CustomPaint */,
)
```

### 3.5 Board context (position identification)

Wrap the board area with a `Semantics` that announces the position context:

```dart
Semantics(
  label: '${studyTitle}, chapter ${chapterTitle}. '
         '${sideToMove == Side.white ? "White" : "Black"} to move.',
  child: /* existing BoardWidget */,
)
```

### 3.6 What NOT to change

* Do not modify `chessground` or `package:chessground` — that is upstream.
* Do not change navigation, tap targets, or visual layout.
* Do not add `ExcludeSemantics` to anything — we are adding, not removing.
* Do not touch `SPEC.md`, `GATES.md`, `.gates/`, `pubspec.yaml`.

## 4. Verification

```bash
git worktree add ../chesssrs-a11y-fix-27 -b fix/a11y-fix-27-review-semantics origin/main
cd ../chesssrs-a11y-fix-27
fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs

# Grep for Semantics in the file — before: 1 hit (VerdictLiveRegion); after: 6+
rg -c "Semantics" lib/src/view/review/review_screen.dart
# Before: 1 (or small number)
# After: 6+

# Existing tests must pass
fvm flutter test test/view/review/review_screen_test.dart

# Runtime: launch on Linux desktop, enable the Accessibility Inspector
# (or Flutter's semantics debugger: `showSemanticsDebugger: true` in MaterialApp)
# and verify each element has a label.

fvm flutter analyze

git add lib/src/view/review/review_screen.dart
git commit -m "fix(a11y): add semantic labels to review training screen elements"
./scripts/gates.sh t1
git push -u origin fix/a11y-fix-27-review-semantics
gh pr create -R cassandre60/ChessSRS --title "fix(a11y): add semantic labels to review training screen" --body "Closes A11Y-FIX-27."
```

## 5. Done when

* [ ] `Semantics` wrappers on: move prompt, tap-to-continue overlay, answer slot, progress indicator, board context
* [ ] `_VerdictLiveRegion` unchanged (already correct)
* [ ] `rg Semantics lib/src/view/review/review_screen.dart` shows 6+ hits
* [ ] Existing review screen tests pass
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green
* [ ] PR open against `cassandre60/ChessSRS`
