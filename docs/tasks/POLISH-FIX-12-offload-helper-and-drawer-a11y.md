# POLISH-FIX-12 — Offload helper naming/polish + drawer a11y (hardware-keyboard autofocus, reduced motion)

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

Two polish items left from the review/arch sweep, intentionally small so the agent has one more queued brief instead of idling between PRs:

### 12a. Offload helper follow-up (if POLISH-FIX-10 chose Option A vs doc wording)

`POLISH-FIX-10` introduces `shouldOffloadPgnWork({required int textLength})`. If the implementer chose a different name (`shouldOffloadPgnWork` vs `isLargePgn` vs `useIsolateForPgn`) or left `importPgnAsync` still branching on `kIsWeb` instead of delegating entirely to the helper, this brief reconciles the naming and removes the dead outer guard. The repo's style is established: helpers are named `should…` or `is…` and imported where branching happens — keep the name POLISH-FIX-10 actually shipped and clean up any remaining `kIsWeb || Platform.environment...` literal outside the helper (grep must show only the helper file contains `Platform.environment`).

### 12b. Drawer a11y: autofocus + reduced motion

* `lib/src/view/review/review_scope_drawer.dart:201` — `TextField(autofocus: isWide)` raises the soft keyboard on tablet portrait when `isWide` is miscomputed (before POLISH-FIX-09 it used window width 768). Spec `03` §6 says autofocus only with a hardware keyboard — `MediaQuery.disableAnimationsOf` / hardwareKeyboard detection, not `isWide`. After the breakpoint fix, the remaining issue is: on a phone in landscape that is technically wide, autofocus still raises the keyboard unexpectedly. Gate on `kIsWeb || HardwareKeyboard` (or `MediaQuery` + `Focus` + platform check as the repo already does elsewhere) so mobile stays unfocused.

* `lib/src/view/review/review_scope_drawer.dart:44-61, 530-536` — `transitionDuration: 180ms` and `SrsMoveArrow` draw-in 260 ms ignore `MediaQuery.disableAnimationsOf(context)` (§6: collapses to 0). `design/docs/02-tokens.md` §5 motion rules require respecting `disableAnimationsOf`.

Both are one-line conditional fixes; no new strings. `tech-debt-inventory.md` items 7/8 cover the surrounding debounce/offload helper already.

## 2. Files to read before touching anything

1. `lib/src/import/pgn_importer.dart` (or `lib/src/import/pgn_offload.dart` if POLISH-FIX-10 created it) — the helper name + `Platform.environment` grep surface
2. `lib/src/review/review_controller.dart` — verify no residual `Platform.environment` literal after POLISH-FIX-10
3. `lib/src/view/review/review_scope_drawer.dart:188-237, 44-64, 530-540` — search field `autofocus`, barrier/transition durations
4. `lib/src/design/move_arrow.dart` (or `lib/src/design/srs_move_arrow.dart`) — arrow 260 ms draw-in animation
5. `design/docs/03-components.md §6` — autofocus rule (hardware keyboard only), search spec
6. `design/docs/02-tokens.md §5` — reduced motion rule (`disableAnimationsOf → 0`)
7. `lib/src/design/tokens.dart:293-312` — `SrsMotion.resolve(BuildContext, Duration)` already exists — use it
8. `test/view/review/review_scope_drawer_test.dart` (if exists) — drawer tests for search semantics

## 3. The fix

### 3.1 Offload helper polish (`12a`) — only if needed

If `rg -n "Platform\.environment|kIsWeb.*FLUTTER_TEST.*8192|>= 65536" lib/src/review/review_controller.dart lib/src/import/pgn_importer.dart` still prints literals outside the helper after POLISH-FIX-10 landed, clean them:

```dart
// BEFORE (residual in review_controller)
if (!Platform.environment.containsKey('FLUTTER_TEST') && pgnText.length >= 65536) {

// AFTER — delegate to helper (name as shipped by POLISH-FIX-10)
if (shouldOffloadPgnWork(textLength: pgnText.length)) {
```

Delete `import 'dart:io' show Platform` from `review_controller.dart` if no longer used. No other file should contain `Platform.environment`.

### 3.2 Drawer autofocus (`12b` — field)

Replace `autofocus: isWide` with a hardware-keyboard gate:

```dart
// BEFORE
TextField(autofocus: isWide, ...)

// AFTER — only autofocus where a hardware keyboard is likely
autofocus: isWide && !MediaQuery.disableAnimationsOf(context) /* no, wrong signal — use hardware detection */,
```

Use the repo's existing hardware-keyboard signal. The cleanest is already available as `SrsMotion.resolve` for durations, but for keyboard presence the app's convention (see `review_screen.dart:758` shortcuts) is: kbd hints only when hardware keyboard plausible (desktop/web). The equivalent for autofocus is: desktop/web or explicit `HardwareKeyboard` — keep it simple:

```dart
final hardwareKeyboard = !kIsWeb
    ? MediaQuery.maybeOf(context)?.viewInsets.bottom == 0 // no, unreliable
    : true;
```

Instead, follow the existing drawer comment in `03` §6: "Autofocus on devices with a hardware keyboard only (avoid raising the soft keyboard on touch)". The minimal correct fix that matches the spec is:

```dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show HardwareKeyboard;

// ...
autofocus: isWide && (kIsWeb || HardwareKeyboard.instance.physicalKeysPressed.isNotEmpty || defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS),
```

If that is too invasive for a polish fix, the **acceptable minimal fix** is:

```dart
autofocus: isWide && (kIsWeb || Theme.of(context).platform == TargetPlatform.macOS || Theme.of(context).platform == TargetPlatform.windows || Theme.of(context).platform == TargetPlatform.linux),
```

— desktop only. Mobile never autofocuses, so the keyboard never spuriously rises. Document the choice in a one-line comment referencing `03` §6.

Also ensure `hintText: 'Search'` is paired with the drawer semantics the spec intends (the design docs §6 say the accessible name is the longer "Search openings and studies" — but the placeholder stays "Search"; semantics come from the drawer's label, not the hint).

### 3.3 Reduced motion (`12b` — transitions)

Gate the drawer's `transitionDuration` and the arrow draw-in via `SrsMotion.resolve`:

```dart
// review_scope_drawer.dart:41-48, 529-537 — barrier/transition durations
transitionDuration: SrsMotion.resolve(context, const Duration(milliseconds: 180)),
// or: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 180),

// move_arrow.dart — arrow stroke draw-in
final duration = SrsMotion.resolve(context, const Duration(milliseconds: 260));
```

`SrsMotion.resolve` already does exactly `disableAnimationsOf ? zero : d` (`tokens.dart:310-311`) — use it.

### 3.4 What NOT to change

* Do not change `shouldOffloadPgnWork`'s threshold value — POLISH-FIX-10 owns that decision.
* Do not change the drawer's layout, padding, or `SrsSheetDismissible` wiring.
* Do not touch `SPEC.md`, `GATES.md`, protected paths.

## 4. How to make the work verifiable (no guessing)

### 4.1 Worktree setup — required

```bash
git worktree add ../chesssrs-polish-fix-12 -b fix/polish-fix-12-drawer-a11y origin/main
cd ../chesssrs-polish-fix-12
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze
```

Branch name is `fix/polish-fix-12-drawer-a11y`.

### 4.2 Tests

**For 12a:** Grep-only — after the fix:

```bash
rg -n "Platform\.environment|FLUTTER_TEST.*8192|>= 65536" lib/src/review/review_controller.dart lib/src/import/pgn_importer.dart
# helper file is the only hit; controller has none
```

**For 12b:**

* TextField `autofocus` is now `isWide && <hardware-gate>` — grep shows the gate.
* Transitions use `SrsMotion.resolve` or `disableAnimationsOf` — grep shows the gate.

No new widget test required for polish — targeted lints are the proof. If `test/view/review/review_scope_drawer_test.dart` exists, run it:

```bash
fvm flutter test test/view/review/review_scope_drawer_test.dart --plain-name 'search autofocus'
```

### 4.3 Implement the fix — GREEN

Edit only:
* `lib/src/review/review_controller.dart` (if 12a residual literal exists)
* `lib/src/view/review/review_scope_drawer.dart` (autofocus + transitionDuration)
* `lib/src/design/move_arrow.dart` (arrow duration, via SrsMotion.resolve)

### 4.4 Verify

```bash
rg -n "Platform\.environment" lib/ --glob '!*.freezed.dart' --glob '!*.g.dart'
# expect: one file (the helper), not three

rg -n "autofocus: isWide" lib/src/view/review/review_scope_drawer.dart
# must print nothing — now gated

fvm flutter analyze
fvm flutter test test/view/review/review_scope_drawer_test.dart  # if exists
git add lib/src/view/review/review_scope_drawer.dart lib/src/design/move_arrow.dart lib/src/review/review_controller.dart
git commit -m "fix(design): gate drawer autofocus on hardware keyboard and respect reduced motion"

./scripts/gates.sh t1
```

Gates read committed diff — run after committing.

### 4.5 Push & PR

```bash
git push -u origin fix/polish-fix-12-drawer-a11y
gh pr create -R cassandre60/ChessSRS --title "fix(design): gate drawer autofocus on hardware keyboard and respect reduced motion" --body "Closes POLISH-FIX-12. See docs/tasks/POLISH-FIX-12-offload-helper-and-drawer-a11y.md."
```

## 5. Done when

* [ ] No `Platform.environment` literal outside the offload helper file
* [ ] Drawer search does not autofocus on mobile (hardware-keyboard gate)
* [ ] Drawer transition + arrow draw-in respect `disableAnimationsOf` via `SrsMotion.resolve`
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green on committed branch
* [ ] PR open against `cassandre60/ChessSRS`
