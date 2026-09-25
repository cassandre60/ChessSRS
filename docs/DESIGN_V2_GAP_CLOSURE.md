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

- `./gate.sh` (analyze + format) green, including `--all`.
- `flutter test` is **not** run locally, by design: it saturates this machine. CI is the
  authority. The one fix proven non-vacuous by a deliberate pre/post run is the keyboard
  shortcut fix (C8).
- **Runtime validation is still owed.** No commit on this branch has been launched. Every
  visual claim rests on reading the demo HTML and `design/docs/`, never on running pixels.
  Per `AGENTS.md` §4 this must happen before the branch is called done.
- Branch was rebased onto `main` after the work landed; the only conflict was two import
  lines in `test/view/explorer/opening_explorer_screen_test.dart`, resolved by keeping both.
  `main`'s inline-move-list test (584e6d590) and the `index - 1` conversion it pins both
  survive.

## Known pre-existing failure (not ours)

`test/app_test.dart: App will delete a stored authUser on startup if one request return 401`
fails on the base commit too — reproduced with the work stacked away, and it is one of the
11 failures on `main`. It is an auth-path assertion (`Expected: <1> Actual: <0>`), unrelated
to anything on this branch.
