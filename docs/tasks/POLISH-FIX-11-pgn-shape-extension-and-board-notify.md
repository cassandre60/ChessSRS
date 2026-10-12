# POLISH-FIX-11 — Triplicated PgnCommentShape→Shape extension + board notify churn

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

Two polish bugs, paired because each is a small deduplication with a non-trivial verification story.

### 11a. Triplicated `PgnCommentShape → Shape` extension (3 copies, byte-for-byte)

`tech-debt-inventory.md` item 1, flagged high value but **attempted and reverted** in batch 1 (§5) because it failed 68 `flutter test` cases:

| File | Line | Code |
|------|------|------|
| `lib/src/view/analysis/game_analysis_board.dart:72` | `extension on PgnCommentShape { Shape get chessground … }` |
| `lib/src/view/review/review_screen.dart:1293` | same 15 lines |
| `lib/src/view/study/study_screen.dart:503` | same 15 lines |

```dart
extension on PgnCommentShape {
  Shape get chessground {
    final shapeColor = switch (color) {
      CommentShapeColor.green => ShapeColor.green,
      CommentShapeColor.red => ShapeColor.red,
      CommentShapeColor.blue => ShapeColor.blue,
      CommentShapeColor.yellow => ShapeColor.yellow,
    };
    return from != to
        ? Arrow(color: shapeColor.color, orig: from, dest: to)
        : Circle(color: shapeColor.color, orig: from);
  }
}
```

### 11b. `AnalysisController.build` notify churn on every engine event (optional pairing)

`lib/src/model/analysis/analysis_controller.dart:146-310` (166-line `build`) mixes in three mixins shared with `StudyController` (`model/study/study_controller.dart:952-1015`) and rebuilds engine lines on every `onCurrentPathEvalChanged` without throttling. This is smaller value and higher risk than 11a, so the brief **requires 11a and makes 11b opt-in** — do 11a first, ship, then open a follow-up for 11b only if time remains. The two must not be in the same commit.

## 2. Files to read before touching anything

1. `lib/src/view/analysis/game_analysis_board.dart:60-90` — first copy of the extension, surrounding imports
2. `lib/src/view/review/review_screen.dart:1285-1310` — second copy (+ `import 'package:chessground/chessground.dart'`)
3. `lib/src/view/study/study_screen.dart:495-520` — third copy
4. `docs/tech-debt-inventory.md` §5 "Reverted: item 1" — why the previous attempt failed 68 tests, how bisect isolated it
5. `lib/src/model/analysis/analysis_controller.dart:146-310` + `lib/src/model/study/study_controller.dart:952-1015` — only if attempting 11b
6. `test/view/review/review_screen_test.dart`, `test/view/analysis/game_analysis_board_test.dart` (if exists), `test/view/study/study_screen_test.dart` — the 68 failing tests live in these view tests
7. `lib/src/design/tokens.dart` — to confirm no design coupling (none)

## 3. The fix — 11a only (11b is follow-up)

### 3.1 One shared extension

Create a single shared library that all three files import:

```dart
// lib/src/widgets/pgn_shapes.dart  (or lib/src/design/pgn_shapes.dart — pick one, be consistent)
// Pure presentation helper: maps PGN comment shapes to chessground Shapes.

import 'package:chessground/chessground.dart' show Arrow, Circle, Shape, ShapeColor;
import 'package:chess_srs/src/model/analysis/analysis_controller.dart' show PgnCommentShape, CommentShapeColor; // or wherever PgnCommentShape is defined

extension PgnCommentShapeChessground on PgnCommentShape {
  Shape get chessground {
    final shapeColor = switch (color) {
      CommentShapeColor.green => ShapeColor.green,
      CommentShapeColor.red => ShapeColor.red,
      CommentShapeColor.blue => ShapeColor.blue,
      CommentShapeColor.yellow => ShapeColor.yellow,
    };
    return from != to
        ? Arrow(color: shapeColor.color, orig: from, dest: to)
        : Circle(color: shapeColor.color, orig: from);
  }
}
```

Locate `PgnCommentShape` and `CommentShapeColor` precisely first — they were in `model/analysis/` or `model/common/` in the previous batch. Import exactly that file; do not duplicate the type.

Then in each of the three view files:

```dart
// Replace the 15-line extension block with:
import 'package:chess_srs/src/widgets/pgn_shapes.dart'; // or design/pgn_shapes.dart
```

Delete the local `extension on PgnCommentShape` block. The call site `pgnShape.chessground` stays identical — no call-site change.

### 3.2 Why batch 1 failed 68 tests (and how not to repeat it)

Previous batch moved the extension to a shared file, it compiled, but `flutter test` failed 68 cases deterministically in every config (items 1+5+11, item 1 alone — §5 table). The bisect proves the mechanism was *not* visible in the diff — extension resolution at the 3 call sites appeared correct and no second `chessground` extension on `PgnCommentShape` existed. Hypotheses that were **not** checked (do them now):

* `dart:ui` vs `package:chessground` re-export: if the shared file imports `chessground` via a different entry point than the 3 view files did, `Shape`/`Arrow`/`Circle` may resolve to different libraries.
* Extension precedence: a local extension takes precedence over an imported one if another extension on the same type is visible in scope — check for any other `extension on PgnCommentShape` in `lib/` (there was none then, but re-grep now).
* `part` / `part of` vs `import`: if any of the 3 files used `part` directives, moving the extension changes its library scope.

**Before you commit**, run `flutter test` on the branch and read the failure messages (the previous environment could not read logs; this one can). The fix is only shippable when the 68 tests pass on the new location.

### 3.3 What NOT to change

* Do not change the `switch` mapping — keep `green→green, red→red, blue→blue, yellow→yellow` verbatim.
* Do not change `Arrow.color`/`Circle.color` construction.
* Do not move `PgnCommentShape` itself.
* Do not bundle 11b (analysis controller deduplication) — that is a separate PR with Riverpod/codegen and its own 1,199-line diff; it needs the toolchain fully available.
* Do not touch `SPEC.md`, `GATES.md`, protected paths.

## 4. How to make the work verifiable (no guessing)

### 4.1 Worktree setup — required

```bash
git worktree add ../chesssrs-polish-fix-11 -b fix/polish-fix-11-pgn-shapes origin/main
cd ../chesssrs-polish-fix-11
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze
```

Branch name is `fix/polish-fix-11-pgn-shapes`.

### 4.2 Failing-or-proving test — run the 68 before you claim green

**Step 0 — reproduce the previous failure on the current main (before your edit):**

```bash
fvm flutter test test/view/review/review_screen_test.dart test/view/analysis/game_analysis_board_test.dart test/view/study/study_screen_test.dart 2>&1 | tail -20
# Must be green on main. If any of these files do not exist, locate the 68 by:
# fvm flutter test 2>&1 | rg "FAILED|failed" | head -20
```

**Step 1 — apply the shared-extension move.**

**Step 2 — run the same tests again and read the failure output** (do not just count). If 68 fail again, the fix is not shippable — capture the first failure's message and stop. Common actionable messages:
* `The getter 'chessground' isn't defined for the class 'PgnCommentShape'` → import not visible at call site (fix the import path).
* `The extension 'PgnCommentShapeChessground' can't be applied...` → two extensions conflict.
* `Expected Shape, got _Shape` → library mismatch on `chessground` import.

**Step 3 — when green, add a tiny unit test** in `test/widgets/pgn_shapes_test.dart` (or alongside the shared file):

```dart
// TECH-DEBT item 1: one extension, three consumers, byte-for-byte identical.
test('PgnCommentShape.chessground maps green arrow', () {
  final s = PgnCommentShape(from: 'e2', to: 'e4', color: CommentShapeColor.green);
  final shape = s.chessground;
  expect(shape, isA<Arrow>());
  expect((shape as Arrow).color, ShapeColor.green.color);
});
test('PgnCommentShape.chessground maps yellow circle', () {
  final s = PgnCommentShape(from: 'e4', to: 'e4', color: CommentShapeColor.yellow);
  expect(s.chessground, isA<Circle>());
});
```

Run targeted:

```bash
fvm flutter test test/widgets/pgn_shapes_test.dart
```

### 4.3 Implement the fix — GREEN

Edit only:
* new `lib/src/widgets/pgn_shapes.dart` (or `lib/src/design/pgn_shapes.dart`)
* `lib/src/view/analysis/game_analysis_board.dart`
* `lib/src/view/review/review_screen.dart`
* `lib/src/view/study/study_screen.dart`

### 4.4 Verify

```bash
# Grep — one definition only
rg -n "extension on PgnCommentShape" lib/
# must print exactly one line (the shared file)

# The 68 — must be green
fvm flutter test test/view/review/review_screen_test.dart test/view/study/study_screen_test.dart

fvm flutter analyze

git add lib/src/widgets/pgn_shapes.dart lib/src/view/analysis/game_analysis_board.dart lib/src/view/review/review_screen.dart lib/src/view/study/study_screen.dart
git commit -m "refactor(view): share one PgnCommentShape→Shape extension"

./scripts/gates.sh t1
```

Gates read committed diff — run after committing. Expect G03 (banned APIs) clean; the shared file imports only `chessground` + the model type.

### 4.5 Push & PR

```bash
git push -u origin fix/polish-fix-11-pgn-shapes
gh pr create -R cassandre60/ChessSRS --title "refactor(view): share one PgnCommentShape→Shape extension" --body "Closes POLISH-FIX-11a. See docs/tasks/POLISH-FIX-11-pgn-shape-extension-and-board-notify.md."
```

## 5. Done when

* [ ] `rg -n "extension on PgnCommentShape" lib/` prints exactly one line (shared file)
* [ ] All 68 previously-failing view tests are green on the branch
* [ ] Small unit test for the extension's mapping passes
* [ ] `fvm flutter analyze` 0 issues on touched files
* [ ] `./scripts/gates.sh t1` green on committed branch
* [ ] PR open against `cassandre60/ChessSRS`

## 6. Follow-up (11b, not this PR)

`AnalysisController` vs `StudyController` near-duplicate (1,199 diff lines, shared mixins, `jumpToNthNodeOnMainline` + `onCurrentPathEvalChanged` duplication). Defer to a dedicated session with `flutter test` / `flutter analyze` fully available — do not bundle with 11a.
