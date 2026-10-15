# PERF-FIX-40 — Isolate board repaints and pre-warm upcoming prompt game data

## 1. Why this is a brief at all

In `lib/src/view/review/review_screen.dart`, the review board is rendered
inside `_ReviewActiveContentState`.

Whenever state changes occur—such as:
- Daily quota counter updates
- Comment box appearance
- Review screen diagnostics timer/ticker
- Banner fades

Flutter rebuilds `_ReviewActiveContentState.build(BuildContext context)`.

### Two performance opportunities

#### 1. Repaint Isolation (`RepaintBoundary`)
The `BoardWidget` renders 64 squares, board coordinates, SVG piece images, and
move highlights. Currently, `BoardWidget` sits inside the parent `Stack` without
its own dedicated `RepaintBoundary`. Any repaint in the parent widget hierarchy
(such as an animated opacity transition on a comment or banner) causes the
entire 64-square chessboard display list to be re-rasterized by the GPU!

Adding a targeted `RepaintBoundary` around `BoardWidget` caches its Skia/Impeller
render layer. Outer widget animations can composite over or beside the board
without re-painting a single chess square.

#### 2. Pre-warming Next Prompt `GameData`
When moving to the next prompt, `_buildGameData()` runs:
```dart
GameData _buildGameData() {
  final boardPrefs = ref.read(boardPreferencesProvider);
  final pos = widget.state.boardPosition ?? Chess.initial;
  ...
  return buildGameData(
    fen: pos.fen,
    variant: Variant.standard,
    position: pos,
    ...
  );
}
```
`pos.fen` generates a complete FEN string from the dartchess `Position` board,
which `buildGameData` parses.

Because `ReviewSession` prefetches prompts in batches, the *next* prompt's
`Position` is already in memory while the user is contemplating the current
prompt! Pre-constructing the next prompt's `GameData` offscreen ensures that
when `didUpdateWidget` fires, the board position transition requires zero
string formatting or object construction.

## 2. Read before touching anything

1. `lib/src/view/review/review_screen.dart` — `_ReviewActiveContentState`.
2. `lib/src/model/game/game_data.dart` — `buildGameData`.
3. Flutter documentation on `RepaintBoundary`:
   https://api.flutter.dev/flutter/widgets/RepaintBoundary-class.html

## 3. Implementation Steps for Agent

1. Wrap `BoardWidget` in `_ReviewActiveContentState` in a dedicated `RepaintBoundary`:
   ```dart
   RepaintBoundary(
     child: Semantics(
       container: true,
       label: _boardSemanticsLabel(prompt, state.boardOrientation),
       child: BoardWidget(
         ...
       ),
     ),
   )
   ```
2. In `_ReviewActiveContentState`, cache the precomputed `GameData` for the next
   prompt:
   When `didUpdateWidget` finishes setting the current prompt, if
   `ref.read(reviewControllerProvider).session?.nextPrompt` is non-null,
   asynchronously precompute `_precomputedNextGameData`.
3. When the prompt changes, use `_precomputedNextGameData` directly if it matches
   the incoming prompt FEN, falling back to `_buildGameData()` if not.

## 4. Verification Steps

1. Verify layout and board interaction tests pass:
   ```bash
   fvm flutter test test/view/review/
   ```
2. Run Flutter DevTools performance overlay or profile on Linux desktop:
   ```bash
   fvm flutter run -d linux --profile
   ```
   Inspect the "Raster" and "UI" frame thread bars. Verify that comment
   toggles and banner animations show 0 raster repaint flashes on the board.
3. Run gates:
   ```bash
   ./scripts/gates.sh t1
   ```

## 5. What counts as done

- `BoardWidget` is wrapped in a dedicated `RepaintBoundary`.
- Upcoming prompt board setup is warm before the user solves the active prompt.
- All review widget tests pass without regressions.
- `./scripts/gates.sh t1` passes after commit.
