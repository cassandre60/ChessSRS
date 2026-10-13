# POLISH-FIX-10 — Isolate threshold split (8192 vs 65536) + notation line collapse when history off

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

Two independent polish bugs, bundled because each is a few lines and both were flagged in `docs/tech-debt-inventory.md`:

### 10a. Isolate-offload thresholds disagree

`lib/src/import/pgn_importer.dart:70, 362`:
```dart
if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST') || pgnText.length < 8192) {
  return Future.value(computePgnHash(pgnText)); // or importPgn(...)
}
return Isolate.run(() => ...);
```

`lib/src/review/review_controller.dart:1433`:
```dart
if (!Platform.environment.containsKey('FLUTTER_TEST') && pgnText.length >= 65536) {
  result = await importPgnAsync(...);
} else {
  result = importPgn(...);
}
```

So hash computation offloads at **8 KB**, but tree building only at **64 KB**. A 20 KB PGN hashes on a worker while its parse+tree blocks the UI isolate — the expensive part runs inline. Also the `dart:io` `Platform.environment` sniff is duplicated across 3 sites, and the hash helper's own 8 KB guard means `importPgnAsync` (which re-parses) is sometimes *not* called even though `review_controller` expected it to be. `tech-debt-inventory.md` item 8 tracks this as "one helper with one documented threshold; keeps `dart:io` in one place."

### 10b. Notation line vanishes and board jumps when history is disabled

`lib/src/view/review/review_screen.dart:822-829`:
```dart
line: showMoveHistory
    ? SrsNotationLine(
        moves: prompt.moveHistory,
        answerSan: isAnswerRevealed ? prompt.expectedMoves.firstOrNull?.san : null,
        showBlank: !isAnswerRevealed,
        wide: wide,
        wideWidth: appWidth,
      )
    : null,
```

`SrsReviewSide` (`lib/src/design/review_layout.dart:155-161`) reserves a 2-line min-height only when `line != null`:
```dart
if (line != null) ...[
  SizedBox(height: wide ? 22 : 10),
  ConstrainedBox(
    constraints: BoxConstraints(minHeight: lineH * 2),
    child: line,
  ),
]
```

When `showMoveHistory` is off, `line` is `null`, the `ConstrainedBox` and its gap disappear, the slot grows by ~2× `lineH` + gap, and the board's `SrsLayout.boardSize(H_content - 222)` allocation shifts between turns. Design says "feedback region never changes height; board never moves" (`design/docs/00` Definition of Done, `design/docs/03-components.md` §4 min-height = 2 lines). Findings U-5 in the decomposition flagged this.

## 2. Files to read before touching anything

1. `lib/src/import/pgn_importer.dart:68-82, 354-376` — the two 8192 guards + `computePgnHashAsync` / `importPgnAsync`
2. `lib/src/review/review_controller.dart:1388-1450` — `importPgnText`'s 65536 branch + the earlier `computePgnHashAsync` call
3. `lib/src/design/review_layout.dart:112-188` — `SrsReviewSide` fixed regions (meta, line with minHeight, slot, actions)
4. `lib/src/view/review/review_screen.dart:756-850` — `showMoveHistory` read + `SrsNotationLine` wiring
5. `lib/src/domain/review/review_session.dart` — `prompt.moveHistory` derivation (to confirm history is still computed even when not shown — it is)
6. `design/docs/03-components.md §4` — Notation line min-height = 2 lines (even when history is off)
7. `design/docs/02-tokens.md §3` — Layout/breakpoint is unrelated but read for context on fixed regions
8. `test/view/review/review_screen_test.dart` — review screen tests (notation line, move history toggle if present)
9. `test/import/pgn_importer_test.dart:595` — `computePgnHashAsync and importPgnAsync work across isolate boundaries`

## 3. The fix

### 3.1 One threshold, one helper (`10a`)

Create a single helper that owns the "when to offload PGN work" decision, keeps `dart:io` in one place, and uses one documented threshold.

**Recommended location**: `lib/src/import/pgn_importer.dart` (where both helpers already live), or a new `lib/src/import/pgn_offload.dart`. Do not create a third copy in `review/`.

```dart
// lib/src/import/pgn_importer.dart (or pgn_offload.dart)

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Whether PGN work of [textLength] bytes should be offloaded to a worker isolate.
///
/// Threshold: 8192 (small = this isolate, large = Isolate.run). This keeps both
/// the hash and the tree build on the same side of the boundary — a file whose
/// hash is computed off-thread also has its parse off-thread.
bool shouldOffloadPgnWork({required int textLength}) {
  if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) return false;
  return textLength >= 8192; // or the consensus value after deliberate decision; document it
}
```

Then replace the three branches:

```dart
// pgn_importer.dart — computePgnHashAsync
Future<String> computePgnHashAsync(String pgnText) {
  if (!shouldOffloadPgnWork(textLength: pgnText.length)) return Future.value(computePgnHash(pgnText));
  return Isolate.run(() => computePgnHash(pgnText));
}

// pgn_importer.dart — importPgnAsync
Future<ImportResult> importPgnAsync(...) {
  if (!shouldOffloadPgnWork(textLength: pgnText.length)) return Future.value(importPgn(...));
  return Isolate.run(() => importPgn(...));
}

// review_controller.dart — importPgnText
if (shouldOffloadPgnWork(textLength: pgnText.length)) {
  result = await importPgnAsync(...);
} else {
  result = importPgn(...);
}
```

**Deliberate decision required**: 8192 vs 65536. Item 8 notes this is a *behaviour* decision. Recommend **8192** (the lower threshold) — tree building dominates hash cost, so isolating at 8 KB is cheaper on typical 10–30 KB repertoires. If the team prefers 65536, use that consistently. Either way, document the chosen value in a comment and make all three sites read it. Do not leave two thresholds coexisting.

Remove `import 'dart:io' show Platform` from `review_controller.dart` if it becomes unused after the helper move (keeping `dart:io` out of the application layer is a secondary win; G03's `banned_apis_check.py` flags it).

### 3.2 Keep the 2-line reserve even when history is off (`10b`)

Make `SrsReviewSide` reserve the notation-line min-height regardless of whether the line is shown, so the board never moves.

**Option A (preferred, one file):** Change `SrsReviewSide` (`lib/src/design/review_layout.dart:155-161`) to always emit the gap + `ConstrainedBox`:

```dart
// lib/src/design/review_layout.dart — SrsReviewSide.build
final effectiveLine = line ?? SizedBox(height: lineH * 2); // or SizedBox.shrink() inside the same ConstrainedBox
SizedBox(height: wide ? 22 : 10),
ConstrainedBox(
  constraints: BoxConstraints(minHeight: lineH * 2),
  child: line ?? const SizedBox.shrink(),
),
```

This preserves the spec's "min-height = 2 lines" invariant even with `showMoveHistory = false`. The board's `boardSize(H_content - 222)` allocation in `SrsLayout` stays stable between turns.

**Option B (two files, equivalent):** Keep the `if (line != null)` guard in `review_layout.dart` but pass a `SizedBox.shrink()` placeholder from `review_screen.dart` instead of `null` when history is off. Option A is cleaner — the layout owns its reserve, not the caller.

Do not add a user-visible placeholder text like "Move history hidden" — the spec says the line is absent but its *space* remains.

### 3.3 What NOT to change

* Do not change `prompt.moveHistory` derivation or `ReviewSession` indexing — history is still computed; only its presentation is gated.
* Do not touch `SPEC.md`, `GATES.md`, protected paths. This is polish, not spec.
* Do not introduce a new `pubspec.yaml` dependency.

## 4. How to make the work verifiable (no guessing)

### 4.1 Worktree setup — required

```bash
git worktree add ../chesssrs-polish-fix-10 -b fix/polish-fix-10-isolate-and-notation origin/main
cd ../chesssrs-polish-fix-10
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze
```

Branch name is `fix/polish-fix-10-isolate-and-notation`.

### 4.2 Proving tests

**For 10a (threshold unification):**

* Add a unit test in `test/import/pgn_importer_test.dart` (or new `test/import/pgn_offload_test.dart`) that asserts `shouldOffloadPgnWork` returns `false` for 81 chars in test env, `false` for 8191, `true` for 8192+ outside test — but since `FLUTTER_TEST` is always set in tests, the observable assertion is: in the test environment, `shouldOffloadPgnWork` is always `false` regardless of length. That proves the web/test sniff is centralised. Also assert `importPgnAsync` and `computePgnHashAsync` agree (both offload or both don't) for the same input length — before the fix they diverge between 8192 and 65535.

```dart
// TECH-DEBT item 8: one helper, one threshold, dart:io isolated.
```

**For 10b (reserve):**

* In `test/view/review/review_screen_test.dart`, if a test for `showMoveHistory` exists, extend it to assert that with `showMoveHistory = false` the notation-line region still has `minHeight >= lineH * 2` (or at least that `SrsReviewSide`'s child count / gap is preserved). If no such test exists, add one that pumps `_ActiveReviewView` with `showMoveHistory = false` and checks `find.byType(ConstrainedBox)` or the gap `SizedBox` is still present.

At minimum ship the 10a test; 10b is also required by this brief.

Run targeted:

```bash
fvm flutter test test/import/pgn_importer_test.dart --plain-name 'shouldOffload'
fvm flutter test test/view/review/review_screen_test.dart --plain-name 'history off preserves reserve'
```

### 4.3 Implement the fix — GREEN

Edit only:
* `lib/src/import/pgn_importer.dart` (or new `lib/src/import/pgn_offload.dart` + export from `design/` if you prefer)
* `lib/src/review/review_controller.dart` (replace 65536 branch)
* `lib/src/design/review_layout.dart` (reserve)
* Optionally `lib/src/view/review/review_screen.dart` only if you choose Option B for 10b.

### 4.4 Verify

```bash
rg -n "8192|65536|Platform\.environment" lib/src/import/pgn_importer.dart lib/src/review/review_controller.dart
# after: one threshold literal, one helper name, dart:io only in the helper file

rg -n "showMoveHistory" lib/src/view/review/review_screen.dart lib/src/design/review_layout.dart
# after: layout always reserves lineH*2 regardless

fvm flutter test test/import/pgn_importer_test.dart --plain-name 'shouldOffload'
fvm flutter test test/view/review/review_screen_test.dart --plain-name 'history off preserves reserve'

fvm flutter analyze
fvm flutter test test/import/pgn_importer_test.dart   # whole file once
fvm flutter test test/view/review/review_screen_test.dart  # whole file once if you touched it

git add lib/src/import/pgn_importer.dart lib/src/import/pgn_offload.dart lib/src/review/review_controller.dart lib/src/design/review_layout.dart test/import/pgn_importer_test.dart test/view/review/review_screen_test.dart
git commit -m "fix(import,design): one isolate threshold and preserve notation-line reserve"

./scripts/gates.sh t1
```

Gates read committed diff — run after committing.

### 4.5 Push & PR

```bash
git push -u origin fix/polish-fix-10-isolate-and-notation
gh pr create -R cassandre60/ChessSRS --title "fix(import,design): one isolate threshold and preserve notation-line reserve" --body "Closes POLISH-FIX-10. See docs/tasks/POLISH-FIX-10-isolate-threshold-and-notation-clip.md."
```

## 5. Done when

* [ ] One `shouldOffloadPgnWork` helper owns the threshold; `dart:io` is in one file; 8192 vs 65536 is reconciled and documented
* [ ] `computePgnHashAsync`, `importPgnAsync`, and `review_controller.dart` all read the same helper
* [ ] `SrsReviewSide` reserves `minHeight lineH*2` (+ gap) even when `showMoveHistory` is off; board does not jump
* [ ] Tests for both sub-fixes, green before/after as described
* [ ] `fvm flutter analyze` 0 issues on touched files
* [ ] `./scripts/gates.sh t1` green on committed branch
* [ ] PR open against `cassandre60/ChessSRS`
