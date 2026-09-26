# Design V2 gap-closure plan

Source of truth: `ChessSRS_ new visual identityV2.html` (1665 lines) + `design/docs/`.
Work happens on branch `design/v2-remainder` in the `/tmp/opencode/chesssrs-v2` worktree so
the concurrent agent's uncommitted work in the main worktree stays untouched.

The demo was fully reproducible from the HTML: tokens, components, screens, states, motion
and copy are all present in the markup, CSS and inline script. **No further files are needed
from the demo author.**

## Contracts

| # | Contract | Result |
|---|---|---|
| C1 | Design-system test harness + primitive contract tests | `test/design/` (34 tests) |
| C2 | `SrsPillButton` is 46px tall; every control clears 44px | **fixed**: was 15px |
| C2b | No duplicated screen-reader labels on `SrsPressable` controls | **fixed**: was "Continue, Continue" |
| C3 | `SrsToast` + `showSrsToast` | new primitive |
| C4 | Loading: empty ground, then a quiet `Loading…` | **fixed**: was a spinner |
| C5 | Error: title + sentence + Try again + Copy details | **fixed**: was raw exception text |
| C6 | Idle/correction copy aligned and single-sourced | **fixed**: 3 strings had drifted |
| C7 | Polite live region announcing the outcome | new; design required it, build had none |
| C8 | `Enter` continues; `S`/`Space` actually delivered | **fixed**: the focused node was *outside* `CallbackShortcuts`, so **no keyboard shortcut worked at all** |
| C9 | Settings: `Advanced` disclosure, no section headers, design labels | done |
| C10 | `SrsDisclosure` primitive | new primitive |
| C11 | Analysis / Explorer repaint (frame only, all features kept) | done |
| C11b | Board editor repaint | deferred — file dirty in the main worktree |
| C12 | Delete dead tab-navigation code, fix the dead root navigator | done |

## Real bugs found (not cosmetic)

1. **No keyboard shortcut worked.** `CallbackShortcuts` installs its key handler as a
   descendant of whatever wraps it, and the focus manager only dispatches to the primary
   focus and then its *ancestors*. `ReviewScreen` wrapped `CallbackShortcuts` in
   `Focus(autofocus: true)`, so `Space` and `S` were never delivered. The demo advertises
   both on screen.
2. **The pill button was 15px tall** instead of 46px — the design's only filled button, and
   it failed the 44px touch-target minimum.
3. **Every button announced its label twice** ("Continue, Continue").
4. **A spinner on a screen the design says must be quiet**, and the raw exception string
   rendered as body text on the failure screen.

## Verified divergences (not bugs — deliberate)

- **`skip()` semantics.** The prototype reveals the answer; `ReviewController.skip()` advances
  the queue unscored. `design/docs/04` §3 explicitly defers to the domain layer, so the app
  is right and the prototype is not. The test pins *delivery*, not meaning.
- **Settings beyond the design's list** (board, engine, logs, licences) are kept in a
  trailing group. `design/docs/03` §12 says to keep anything outside the prototype in the
  same family and ask the owner. **Open question for the owner.**
- **Error copy.** The demo's error scene covers a *save* failure. This build has no
  save-failure state, so the sentence does not borrow the demo's "nothing was lost"
  reassurance, which would be unverifiable.

## Deferred (the other agent's files are dirty in the main worktree)

- Board editor chrome repaint.
- Library sheet row alignment (extra `Studies & Repertoires` / `Chapters` rows).
- Replacing Lichess `showSnackBar` with `showSrsToast` at the ~30 call sites. C3 ships the
  primitive and the helper; the sweep is mechanical.

## Verification state

- `./gate.sh` green, including `--all`.
- `flutter test` is **not** run locally, by design: it saturates this machine. CI is the
  authority. The one fix proven non-vacuous by a deliberate pre/post run is the keyboard
  shortcut fix (C8).
- **Runtime: the review screen is validated** against the demo, in both themes. See below.
- **Runtime: still unvalidated** — the interactive flow (wrong move → correction → note →
  Continue), the keyboard shortcuts actually firing, the Settings `Advanced` disclosure, the
  Analysis/Explorer sub-heads, and phone/tablet widths. See "Why" below.
- Branch was rebased onto `main` after the work landed; the only conflict was two import
  lines in `test/view/explorer/opening_explorer_screen_test.dart`, resolved by keeping both.
  `main`'s inline-move-list test (584e6d590) and the `index - 1` conversion it pins both
  survive.

### What the runtime pass established

Built `flutter build linux --debug` and ran it against an isolated copy of the database
(`XDG_DATA_HOME` pointed at a copy, so the owner's beta data was never written to — verified
by mtime: the real `chess_srs.db` main file stayed at 21:50 while only the copy changed).

- Launches with **zero errors** in the log, in both themes.
- Loads real data: 8 studies, queue truncated to the 100/day quota.
- The review screen **matches the demo's review scene**, element for element: `.topbar` with
  the scope button + `<b>dueN</b> due` + the `moreBtn` dots; `#boardHost` beside `.side`;
  `.meta` with `#ctx` and the `#turnDot`/`#turnTxt` turn line; the `h2.line` move heading;
  and `Skip` with the `S` kbd hint. The large move text is the design's `#line` heading, not
  a leftover — it reads like a bug until you open the demo.
- SRS and the lapse path work end to end at runtime (`FsrsScheduler` scheduling, `Lapse on
  decision …`, regueue after a lapse).

Evidence: `docs/design_v2_review_dark.png`, `docs/design_v2_review_light.png`.

### Why the rest is unvalidated

This is a Wayland session and the Flutter window is a Wayland client, so `xdotool`,
`wmctrl` and `xwininfo` cannot see or target it. Input can only be injected blindly into
whatever holds focus — and at the time of this pass **a second agent was driving the same
desktop, with its own ChessSRS instance open on its own data**. Typing blind would have sent
keystrokes into that agent's session, or into the owner's browser and terminals, to satisfy
a checklist. Not a trade worth making, so the interactive checks were left undone rather than
faked.

Faking the input layer was rejected too. Patching the isolated copy's
`shared_preferences.json` is how the light-mode capture was produced; the same trick cannot
synthesise a keypress.

To close this out, one of: pause the other agent and validate on an exclusive desktop; or
drive the remaining flows through `integration_test`, which owns its own widget tree and
needs no shared display at all.

## Sound: C-S1..C-S3

`design/docs/02-tokens.md` §6 specifies three sounds — a soft knock as a piece lands, two
lower knocks on a rejected move, two gentle notes on reaching "Nothing due". The `.wav` files
ship in `assets/sounds/diagram/` and are declared in `pubspec.yaml`, but nothing loaded or
played them.

| # | Contract | Result |
|---|---|---|
| C-S1 | `move` on a piece landing | **completed**: the opponent's auto-reply already sounded; the user's own landing was silent and is now wired in `_handleCorrectAdvancement` |
| C-S2 | `wrong` on a rejected move | **added** — the branch was silent; `Sound.error` is declared with no call site anywhere. Both the first attempt and a failed reguess |
| C-S3 | `done` on reaching "Nothing due" | **added** — the branch was silent |

`ReviewSound` is deliberately kept out of the `SoundTheme` enum. The Lichess themes resolve by
name with a fallback to `standard/` and ship as `.mp3`/`.aifc`; these are `.wav` under a fixed
path. Folding them into `Sound` would make every theme switch try to resolve `wrong` and
`done`, which exist in no theme, and hand the plugin a path that is not there. `SoundPool` and
`AVAudioPlayer` both read `.wav` natively, so there is nothing to transcode.

`done` hangs off `listenSelf` rather than a field. `ReviewScreenState.isComplete` is a derived
getter and a session can end three ways — queue drained, daily quota, study deactivated — with
no single assignment site. The rising edge is the point: the state is re-emitted constantly once
a session is finished, and `done` must sound on arrival, not on every rebuild.

**Open question for the owner.** `design/docs/07` §1 wants *all* move/capture/UI sounds replaced
by this set, with `standard/futuristic/lisp/nes/piano/sfx` cut. That is a cut, so per `AGENTS.md`
§9 it is not done unilaterally. A landing therefore still uses the user's chosen theme
(`Sound.move`), matching the call sites that were already there; only the two previously-silent
moments speak, and they speak the design's own set. The same section says **default off**, while
`GeneralPrefs.defaults.isSoundEnabled` is `true` — also left alone.

### Verification

`fvm flutter test test/review/review_controller_test.dart` — **34/34 pass**. Every new assertion
was checked non-vacuous by removing the hook and watching it fail with `Expected: <1>
Actual: <0>`.

Two of these were vacuous on the first attempt and are recorded because that is the failure mode
worth remembering, not the fix:

- `an empty app does not play the done sound on startup` passes either way by design. It guards
  `isComplete`'s `hasStudies` conjunct against a future regression; it is not evidence of
  anything new.
- The first version of `a correct move by the user plays the move sound` genuinely passed with
  the hook removed. It used a `1. d4 d5` line and asserted `count >= 1`, and the opponent's
  reply also plays `Sound.move`, so the assertion could not tell the two apart. It now uses a
  line with no reply, so exactly one move sound can only be the user's own landing.

## What the screenshots found

`test/view/screenshot_capture_test.dart` renders the real screens through the real provider
scope and writes PNGs — 30 of them, at 390/834/1440 in light and dark, in about 16 seconds,
with no display involved:

```bash
SRS_CAPTURE_SCREENSHOTS=1 fvm flutter test --update-goldens test/view/screenshot_capture_test.dart
```

It is skipped unless that variable is set, so CI neither writes nor compares, and it writes
rather than asserts because pixel comparison across font stacks is too brittle to be a gate.
The output is reproducible: a second run without `--update-goldens` passes.

Two things it needed that the suite did not have. The real typefaces — `flutter test` ships no
fonts, so every glyph was a filled box, fine for layout assertions and useless for judging a
type scale. And a dark palette at all: `makeTestProviderScopeApp` hardcoded
`SrsColors.forBrightness(Brightness.light)`, so no test in the repository had ever rendered the
dark theme.

It also caught its own failure mode. The first version wrote pure-white PNGs, because the review
controller's database futures never complete under the fake-async test zone and every screen sat
on its deliberately-empty loading state. There is now a guard that refuses to write a blank
frame, because a white file sitting in a directory of design evidence reads as "checked, fine".

### Three real findings

1. **The Theme row reported Light on a dark system.** `isDark` in `srs_settings_screen.dart` was
   `themeMode == dark || themeMode == amoled`, which is false for `BackgroundThemeMode.system` —
   the default. Fixed and covered for all three modes. *This branch.*
2. **The notation line is off by default, and the design calls it the headline.**
   `design/docs/03-components.md` §111: "the line is the headline", with a `3. ____` placeholder
   that fills in `accent` on answer; `01-identity.md` §7 says typography "treats the line of
   moves as the headline". But `showMoveHistory` defaults to `false`, both in the field and in
   its `@JsonKey`, so a first-run user sees no headline at all. Both defaults were set in the
   same bulk redesign commit (`a1c8452c9`), which reads as incidental rather than considered.
   **Not changed here:** `study_preferences.dart` is one of the concurrent agent's dirty files
   and this is a product default, not a rendering fix. The capture turns it on so the evidence
   shows the designed state, and the committed screenshot is what it looks like with the line
   present — meta, notation line, note, Continue, in the demo's order.
3. **Keyboard hints are absent from every capture.** The design specifies `Skip <kbd>S</kbd>` and
   `Continue <kbd>Space</kbd>`; the running app shows them, the captures do not, because the
   design system gates them on platform and the capture does not pin a `TargetPlatformVariant`.
   So the hint *placement* is still unverified by screenshot. Cosmetic to fix, but it means a
   capture cannot be used to check the one thing the demo is most specific about here.

Also worth a look, not a bug: at 390 the review side panel collapses to a single row and leaves
a large void above `Skip`.

### Known limits of the captures

- Icon glyphs still render as filled boxes, including the analysis bottom bar and the share
  action. The icon faces are loaded, so this is a `fontPackage`/codepoint mapping problem rather
  than a missing font. Icon choice and the engine panel's typography are therefore unchecked.
- The Opening Explorer is not captured: it needs the opening-explorer HTTP fixtures that live in
  its own test file. Its sub-head is the same `SrsSubHead` the analysis capture does show.

## Known pre-existing failure (not ours, and not ours to fix)

`test/app_test.dart: App will delete a stored authUser on startup if one request return 401` —
android and iOS. **This branch no longer touches that file.** An earlier attempt here pointed
the 401 stub at `/api/account/preferences`; it was wrong, and the concurrent agent landed two
commits on the same failure, one of them a diagnostic. Two agents in one file is the collision
worth avoiding, so that change was reverted in `revert(test): drop my app_test change`.

What reading it established, offered to whoever picks it up: both halves of the test's premise
have to be set up before the assertion can hold, and neither currently is.

- The startup token check at `preloaded_data.dart:51` only fires when `authStorage.read()` yields
  a token, and `makeTestProviderScope(authUser: …)` injects the auth **controller** state rather
  than seeding secure **storage**. So there is no startup request.
- Nothing on the review screen issues a main-host request in this scenario either, so there is no
  401 to intercept. `accountPreferencesProvider` is read only by the four derived providers
  (`showRatingsPrefProvider`, `clockSoundProvider`, `pieceNotationProvider`,
  `clockTenthsProvider` — all game-related) and by the two settings screens, none of which is
  mounted over an empty database.

That accounts for `expect(tokenTestRequests, 1)` seeing `0`.

## Recovery points

`safety/pre-rebase-fbbf35bc1` and `safety/pre-rebase2-2e6223bf2` hold the pre-rebase heads, so
the force-push is reversible in one command:
`git push --force-with-lease origin safety/pre-rebase-fbbf35bc1:design/v2-remainder`.

## Open bug: the review screen's keyboard shortcuts do not work

**Status: open, not fixed. Not a regression — these never worked.** Severity: low. The
equivalent actions are all reachable with the mouse.

`S` (skip), `Space` and `Enter` (continue) do nothing on the review screen. Confirmed by the
owner on the live Linux desktop build, repeatedly, with the window focused.

### What is established

- **The action works.** Tapping `Skip` with the mouse skips. So `onSkip`, the session advance and
  the handler itself are all fine — this is key *delivery*, not the binding.
- **`P` works on the "Nothing due" screen**, so key events do reach the app, and something in
  the tree does receive them.
- **`Space`/`Enter` doing nothing at a prompt is correct** and not part of this bug. They are
  bound to `continueIfShown`, which only acts while `state.isAwaitingAdvance` — i.e. while a
  note is showing. `design/docs/04` §4 says "Space or Enter: Continue, when a note is showing."
  At a prompt, before answering, silence is the designed behaviour.
- Both `S` and `Space` remain dead *after a move, with a note showing*, which is the part that
  is a real defect.

### Ruled out

- **chessground** (the board) registers no `Focus` nodes and no key handling at all, so it is
  neither holding focus nor consuming keys.
- **`_focusNode` lifecycle** is fine: a State field, disposed in `dispose()`, not recreated per
  build.
- **Nothing above the screen eats keys.** `app.dart`'s root is a plain `MaterialApp` with no
  root `Shortcuts`, `Actions`, `Listener` or key handler.
- **Nothing steals focus.** Only two `Focus` widgets exist in the whole app, mutually exclusive
  (idle view and review view); the design layer and `board.dart` contain none.
- **It is not the one-shot `autofocus` race.** Two fixes were built on that theory, both tested
  on the live app by the owner, and **both failed**: (1) re-asserting focus in a post-frame
  callback, (2) deleting the long-lived `_focusNode` so the review view's focus setup became
  byte-identical to the idle view's, which is the one configuration known to work. Both were
  reverted. Do not retry either.

### Where to start next

Not from reading the source again — that has now produced two confident wrong answers. Add a
runtime diagnostic and let the live app answer:

1. Log every `KeyEvent` the review screen receives (`Focus.onKeyEvent` on a node wrapping the
   `CallbackShortcuts`, or a `HardwareKeyboard` listener), with `event.logicalKey` and whether
   the handler ran. If no event arrives, the problem is platform/window level — the window is
   not receiving keys — not Flutter's focus tree, and the whole focus line of enquiry is wrong.
2. If events do arrive, log `FocusManager.instance.primaryFocus` and its widget ancestry at the
   moment `S` is pressed. That says directly whether the `CallbackShortcuts` node is an ancestor
   of the primary focus, which is the only condition under which `Shortcuts` can fire.
3. If it *is* an ancestor and the handler still does not run, the problem is the activator
   matching. `SingleActivator(LogicalKeyboardKey.keyS)` matches the logical key regardless of
   shift, so a modifier or keyboard-layout difference is worth logging
   (`HardwareKeyboard.instance.logicalKeysPressed`).

### Why no test caught it

`makeTestProviderScopeApp` builds `_FakeApp`, a bare `MaterialApp`, and the widget-test binding
**always grants focus**. So `tester.sendKeyEvent` exercises a focus configuration the real app
never has, and any test written that way passes against a completely broken build. The tests
that briefly covered this have since disappeared from the tree, which is how the bug survived
untested for so long. **A shortcut test in this harness cannot be trusted**; it needs a test that
asserts the focus precondition, or a real device.

Recorded by the owner's live testing, 2026-09-26. Two failed fixes reverted: `77a3e0efd` and
`af209c955` (the latter reverted by `00883b067`).
