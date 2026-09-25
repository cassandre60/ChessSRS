# Design V2 gap-closure plan

Source of truth: `ChessSRS_ new visual identityV2.html` (1665 lines) + `design/docs/`.
Work happens on branch `design/v2-remainder` in the `/tmp/opencode/chesssrs-v2` worktree so the
concurrent agent's uncommitted work in the main worktree stays untouched.

The demo was fully reproducible from the HTML: tokens, components, screens, states, motion and
copy are all present in the markup, CSS and inline script. No further files are needed from the
demo author.

## Contracts

Each contract is: one behaviour, one test, `./verify`-clean, committed on its own.

| # | Contract | Files | State |
|---|---|---|---|
| C1 | Design-system test harness + primitive contract tests | `test/design/*` | done |
| C2 | `SrsPillButton` is 46px tall (demo `.pill{height:46px}`) and every control clears 44px | `lib/src/design/primitives.dart` | done |
| C3 | `SrsToast` primitive + `showSrsToast` (demo `.toast`, spec 03 §12) | `lib/src/design/toast.dart` | done |
| C4 | Loading state shows nothing, then a quiet `Loading…` (no spinner) | `review_screen.dart` | done |
| C5 | Error screen: `Something went wrong.` + detail + Try again + Copy details | `review_error_view.dart`, `review_screen.dart` | done |
| C6 | Idle/answer copy aligned with the demo | `review_screen.dart` | done |
| C7 | Screen-reader live region announces correct / not-this-move | `review_screen.dart` | done |
| C8 | `Enter` continues, `Esc` closes sheets | `review_screen.dart`, sheets | done |
| C9 | Settings: `Advanced` disclosure, no uppercase section headers, demo labels | `srs_settings_screen.dart` | done |
| C10 | `SrsSubHead` + Analysis screen repaint (frame only, features kept) | `design/sub_head.dart`, `analysis_screen.dart` | done |
| C11 | Explorer screen repaint | `opening_explorer_screen.dart` | done |
| C12 | Delete dead tab-navigation code (`MainTabScaffold`, `MoreTabScreen`, …) | `tab_navigation.dart`, `tab_scaffold.dart`, `view/more/` | done |

## Deferred to the concurrent agent (their files are dirty in the main worktree)

- Board editor chrome repaint (`board_editor_screen.dart`).
- Library sheet row alignment (extra `Studies & Repertoires` / `Chapters` rows).
- Replacing Lichess `showSnackBar` with `SrsToast` at the ~30 existing call sites. C3 ships the
  primitive and the helper; the sweep is mechanical.
