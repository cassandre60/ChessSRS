# A11Y-FIX-30 — Analysis screen lacks semantic labels (sibling of A11Y-FIX-27)

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

`lib/src/view/analysis/analysis_screen.dart` — the explore/analysis surface
linked from every study — has exactly **one** accessibility annotation in 805
lines: a `tooltip` on the menu button (line ~740). Missing:

| Element | Approx. location | A11y gap |
|---------|------------------|----------|
| Variant picker | line ~585 | No `semanticLabel` — screen reader announces "button" with no context |
| Tab bar (moves / engine / etc.) | layout file | No `Semantics` on tab items |
| Engine evaluation lines | player widget | Eval scores render as bare text — no announcement of what they mean |
| Board interaction controls | layout file | Unlabeled icon buttons |
| Chapter/position context | header | No label tying the board to "Study X, chapter Y" |

Brief 27 fixed the same class of problem on `review_screen.dart`. This brief
applies the identical pattern to the analysis surface.

## 2. Files to read before touching anything

1. `lib/src/view/analysis/analysis_screen.dart` (805 lines) — the screen
2. `lib/src/view/analysis/analysis_layout.dart` — tab bar and control layout
3. `lib/src/view/analysis/analysis_player_widget.dart` — eval line rendering
4. `docs/tasks/A11Y-FIX-27-review-screen-semantics.md` — the sibling brief;
   copy its `Semantics` wrapper patterns exactly
5. `test/view/analysis/analysis_screen_test.dart` — existing tests (must stay green)

## 3. The fix

Same pattern as brief 27 — `Semantics(label: …)` wrappers, no visual changes:

* Variant picker: `Semantics(label: 'Choose variation', button: true, child: …)`
* Tab items: `Semantics(label: '<tab name> tab', selected: <bool>, child: …)`
* Eval lines: `Semantics(label: 'Engine evaluation: <score>, best move <move>', child: …)`
* Board controls: each icon button gets `Semantics(button: true, label: 'Flip board' / 'Next move' / …)`
* Header: `Semantics(header: true, label: '<study title> — analysis', child: …)`

Read each widget first; use the *actual* strings/state, not the examples above.

### What NOT to change

* Do not modify `chessground` — wrap at the screen level only.
* Do not change visual layout, tap targets, or navigation.
* Do not touch `SPEC.md`, `GATES.md`, `.gates/`, `pubspec.yaml`.

## 4. Verification

```bash
git worktree add ../chesssrs-a11y-fix-30 -b fix/a11y-fix-30-analysis-semantics origin/main
cd ../chesssrs-a11y-fix-30
fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs

rg -c "Semantics" lib/src/view/analysis/analysis_screen.dart
# Before: ~1 (tooltip only). After: 6+

fvm flutter test test/view/analysis/analysis_screen_test.dart
fvm flutter analyze

git add lib/src/view/analysis/
git commit -m "fix(a11y): add semantic labels to analysis screen"
./scripts/gates.sh t1
git push -u origin fix/a11y-fix-30-analysis-semantics
gh pr create -R cassandre60/ChessSRS --title "fix(a11y): add semantic labels to analysis screen" --body "Closes A11Y-FIX-30."
```

## 5. Done when

* [ ] `Semantics` wrappers on: variant picker, tab items, eval lines, board controls, header
* [ ] `rg Semantics lib/src/view/analysis/` shows 6+ hits
* [ ] Existing analysis screen tests pass unchanged
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green
* [ ] PR open against `cassandre60/ChessSRS`
