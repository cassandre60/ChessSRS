# POLISH-FIX-09 — Scope drawer breakpoint drift (768 vs 720) + maxHeight/maxWidth mismatch

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

`design/docs/02-tokens.md` §3 defines the responsive breakpoint as **app-area width ≥ 720** (via `LayoutBuilder`), and `lib/src/design/tokens.dart:318` pins it:

```dart
static const double wideBreakpoint = 720;
static bool isWide(double width) => width >= wideBreakpoint;
```

`SrsReviewLayout` respects it (via `LayoutBuilder` + `SrsLayout.isWide`). Two sheets do not:

* `lib/src/view/review/review_scope_drawer.dart:53, 84, 529, 814, 821`
  ```dart
  final isWide = MediaQuery.of(dialogContext).size.width >= 768;          // 768, not 720
  final maxHeight = math.min(mediaQuery.size.height * 0.82, 720.0);        // 82% vs spec H-80 (wide) / min(82%,720) (narrow)
  final maxWidth = isWide ? math.min(470.0, mediaQuery.size.width - 52.0) : double.infinity;
  // ...
  static const double _wideBreakpoint = 768;                                // StudyActionsSheet copy-pastes 768
  static const double _popoverWidth = 300;                                  // Library sheet uses 310 — undocumented drift
  ```
* `lib/src/view/review/repertoire_import_dialog.dart:49, 259` — same `>= 768` for the import sheet.

All three use `MediaQuery.size.width` (window) not the app-area `LayoutBuilder` box, and all three hardcode `768` instead of the token. On a split-screen tablet at ~730 px the spec says **wide** (side-anchored popover, fade transition) but the code shows the **narrow** bottom sheet with slide transition. `maxHeight` also diverges: spec is `H - 80` (wide) / `min(82%, 720)` (narrow); code uses `H*0.82` for both.

`docs/tech-debt-inventory.md` does not rank this but `design/docs/03-components.md` §6 pins the canonical sizing (`width min(470,W-52)`, `max-height H-80 / min(82%,720)`) and the `design/docs/02-tokens.md` breakpoint is the source of truth.

## 2. Files to read before touching anything

1. `lib/src/design/tokens.dart:318-329` — `SrsLayout.wideBreakpoint`, `isWide`, `boardSize`, padding constants
2. `lib/src/design/review_layout.dart` — canonical use of `LayoutBuilder` + `SrsLayout.isWide` (the correct pattern)
3. `lib/src/view/review/review_scope_drawer.dart:40-87, 814-826` — the two 768 sites + the `_wideBreakpoint` duplicate + `_popoverWidth`
4. `lib/src/view/review/repertoire_import_dialog.dart:34-60, 254-265` — the third 768
5. `design/docs/03-components.md:06` — Drawer spec (wide: `min(470,W-52)`, `H-80`; narrow: `min(82%,720)`, grabber)
6. `design/docs/02-tokens.md §3` — Layout/breakpoint definition (app-area, 720, `LayoutBuilder`)
7. `lib/src/design/srs_sheet.dart` (if exists) — `SrsSheetDismissible`, `SrsSheetSurface` sizing used by the Library sheet (310 width) — align to it
8. `test/view/review/review_scope_drawer_test.dart` (if exists) else `test/view/screenshot_capture_test.dart` — captures at 5 widths (used to eyeball before/after)

## 3. The fix

Align all drawer/sheet breakpoints and sizing to the token and to the spec, using app-area width where the dialog has access to it.

### 3.1 Replace hardcoded `768` with the token

* In `review_scope_drawer.dart`, replace every `>= 768` with `SrsLayout.isWide(width)` or `>= SrsLayout.wideBreakpoint`.
  * Line 53 (`show` transitionBuilder): switch to `SrsLayout.isWide(MediaQuery.sizeOf(dialogContext).width)` or, better, wrap the dialog content in a `LayoutBuilder` and read `box.maxWidth` (like `SrsReviewLayout` does). `MediaQuery` is acceptable if the sheet is shown via `showGeneralDialog` (no LayoutBuilder box above it) — but then use the token, not 768.
  * Line 84 (`build` isWide): same.
  * Line 529 (`transitionBuilder` for study actions sheet): same.
  * Line 814 (`_wideBreakpoint`): delete the field; use `SrsLayout.wideBreakpoint` directly.
* In `repertoire_import_dialog.dart:49,259`: same — replace `768` with `SrsLayout.wideBreakpoint` / `SrsLayout.isWide`.

Do not introduce a new constant — `SrsLayout.wideBreakpoint` **is** the constant.

### 3.2 Fix `maxHeight` / `maxWidth` to match the spec

Current:

```dart
final maxHeight = math.min(mediaQuery.size.height * 0.82, 720.0);
final maxWidth = isWide ? math.min(470.0, mediaQuery.size.width - 52.0) : double.infinity;
```

Spec (03 §6):
* **Wide**: `max-height H - 80` (no 720 cap), width `min(470, W - 52)`
* **Narrow**: `max-height min(82% of H, 720)` — which the current line happens to compute correctly, but only for narrow; wide should be `H - 80`.

Implement:

```dart
final isWide = SrsLayout.isWide(mediaQuery.size.width); // or LayoutBuilder variant
final maxHeight = isWide ? math.max(0, mediaQuery.size.height - 80) : math.min(mediaQuery.size.height * 0.82, 720.0);
final maxWidth = isWide ? math.min(470.0, mediaQuery.size.width - 52.0) : double.infinity;
```

For `StudyActionsSheet` (lines 918-927): the `_popoverWidth = 300` vs Library's 310 drift — if the design spec does not distinguish, align to 310 or note the deliberate difference; do not leave two unexplained nearby values. Prefer 310 if unsure, with a comment referencing `lib/src/design/srs_sheet.dart` or the Library sheet.

### 3.3 Prefer `LayoutBuilder` where possible

`SrsReviewLayout` is the model: it derives `wide` from `box.maxWidth` (app area), not `MediaQuery`. The scope drawer's `build` is inside a `showGeneralDialog` whose `pageBuilder` gets the window — `MediaQuery.sizeOf` is the only available source there, which is why the window/app-area distinction matters. If moving the `isWide` computation inside the sheet's own `LayoutBuilder` is trivial (wrap the `Container` child in `LayoutBuilder`), do it; otherwise switching the threshold to 720 on the `MediaQuery` width already closes ~95% of the drift (only split-screen/multi-window benefits from the `LayoutBuilder` refinement).

### 3.4 What NOT to change

* Do not change `SrsLayout.wideBreakpoint` (720) — it is the source of truth.
* Do not touch `SPEC.md`, `GATES.md`, protected paths. This is a view/design polish PR.
* Do not rework `SrsScopeDrawer` theming or tokens — only the breakpoint and sizing math.

## 4. How to make the work verifiable (no guessing)

### 4.1 Worktree setup — required

```bash
git worktree add ../chesssrs-polish-fix-09 -b fix/polish-fix-09-drawer-breakpoint origin/main
cd ../chesssrs-polish-fix-09
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze
```

Branch name is `fix/polish-fix-09-drawer-breakpoint`.

### 4.2 Failing-or-proving test

This is a visual/layout fix. Two complementary proofs:

**(a) Static grep proof (required):** Before the fix, `rg -n ">= 768|_wideBreakpoint = 768"` across `lib/` prints hits in the two dialogs. After, it must print nothing. Include this grep output in the PR description.

**(b) Widget test or capture proof (preferred if a harness exists):**

* If `test/view/review/review_scope_drawer_test.dart` exists, add a test that pumps the drawer at width **730** (between 720 and 768) and asserts `isWide` resolves to wide (popover, fade transition) — it currently resolves to narrow. Before the fix this fails; after it passes.
* If no drawer test exists, use `test/view/screenshot_capture_test.dart` (30 captures over 5 widths) — run it and eyeball the 730 px capture's transition (fade vs slide) and maxHeight.

At minimum ship (a) plus a manual grep; (b) if the file is trivial to add.

Citations:

```dart
// DESIGN 02 §3 (tokens): wide if app-area width >= 720 via LayoutBuilder.
// DESIGN 03 §6: drawer wide max-height H-80, width min(470, W-52).
```

Run targeted:

```bash
rg -n ">= 768|_wideBreakpoint" lib/src/view/review/
fvm flutter test test/view/review/review_scope_drawer_test.dart --plain-name 'breakpoint at 730 is wide'
```

### 4.3 Implement the fix — GREEN

Edit only `lib/src/view/review/review_scope_drawer.dart` and `lib/src/view/review/repertoire_import_dialog.dart`.
Optionally touch `lib/src/design/srs_sheet.dart` if you align the 300→310 popover width.

### 4.4 Verify

```bash
rg -n ">= 768|_wideBreakpoint" lib/
# must print nothing

fvm flutter analyze

# Whole file of the most-touched screen, once
fvm flutter test test/view/review/review_scope_drawer_test.dart
# or if that file does not exist:
fvm flutter analyze lib/src/view/review/review_scope_drawer.dart lib/src/view/review/repertoire_import_dialog.dart

git add lib/src/view/review/review_scope_drawer.dart lib/src/view/review/repertoire_import_dialog.dart
git commit -m "fix(design): align drawer breakpoint and sizing to tokens (720, H-80)"

./scripts/gates.sh t1
```

Gates read committed diff — run after committing (pre-commit is not evidence, see `AGENTS.md` Lesson 2026-10-07).

### 4.5 Push & PR

```bash
git push -u origin fix/polish-fix-09-drawer-breakpoint
gh pr create -R cassandre60/ChessSRS --title "fix(design): align drawer breakpoint and sizing to tokens (720, H-80)" --body "Closes POLISH-FIX-09. See docs/tasks/POLISH-FIX-09-drawer-breakpoint-and-sizing.md."
```

## 5. Done when

* [ ] No `>= 768` or `_wideBreakpoint = 768` remains in `lib/` (grep clean)
* [ ] Drawer and import sheet use `SrsLayout.wideBreakpoint` / `isWide`
* [ ] `maxHeight` is `H-80` when wide, `min(82%,720)` when narrow
* [ ] 300 vs 310 popover width reconciled or documented
* [ ] `fvm flutter analyze` 0 issues on touched files
* [ ] `./scripts/gates.sh t1` green on committed branch
* [ ] PR open against `cassandre60/ChessSRS`
