# Design & settings chapter (digest)

Source: full per-test read of test/design (srs_accent, srs_dialog,
srs_notation_line, srs_page_head, srs_sheet_dismissible, srs_switch, srs_toast,
top_bar_colour_squares, one_look) and test/view/settings
(srs_settings_screen, board_thumbnail).

## Grade distribution

about 49 tests walked: 25 grade 3, 22 grade 2, 4 grade 1, 2 grade 0.

## Strongest pattern observed

The strongest tests in the design suite are written against named past
regressions (sheet finger-tracking, deep-link toast context, 8-ply cut, SRS
thumbnails, piece-set override, dialog right-alignment) — they assert the
changed half of the mutation and their pre-claims are double-checked rather
than presumed.

## Weakest pattern observed

The weakest tests are the ones whose title writes a cheque the assert doesn't
cash: `srs_page_head_test.dart:37` ("disables without onBack" — asserted by
nothing: no isEnabled, no tap-inert check), the settings smoke test
"srs_settings_screen_test.dart:40" ("updates preferences" — asserts only
no-exception), and the toast tone loop at `srs_toast_test.dart:138` (never
passes the tone it loops over).

## Name-grade table (verified quotes)

| File | Line | Title | Grade | Reason |
|---|---|---|---|---|
| srs_accent | 33 | a chosen accent is still chosen after restart | 3 | real end-to-end restart through a fresh container |
| srs_accent | 43 | accent stored with the rest of general preferences | 3 | pins the storage shape (`json['accent']`, `'preferences.general'`) |
| srs_accent | 59 | defaults to the default accent | 2 | partly tautological about which accent is default, truthful about initialisation |
| srs_accent | 63 | prefs stored before accents existed still decode | 3 | data-loss guard; fails if decode requires accent |
| srs_accent | 79 | unrecognised accent falls back | 3 | catches decode throw *and* wrong fallback |
| srs_dialog | 44 | caps the card at 400px | 2 | cap is unbinding at the 390-wide harness; still fails left/right alignment |
| srs_dialog | 56 | title at 20px w600 | 2 | catches size mutations; misses colour/family |
| srs_dialog | 64 | body at 15px | 2 | same gap |
| srs_dialog | 70 | pads by 24 | 3 | catches padding mutations |
| srs_dialog | 79 | right-aligns actions | 3 | catches start/center alignment |
| srs_dialog | 100 | prefers content over body | 3 | both halves make exclusion a real assert |
| srs_dialog | 110 | omits body gap when no title | 3 | catches a stray SizedBox |
| srs_notation_line | 28 | narrow line is headline-sized | 2 | token-level; the render never asserts size on screen |
| srs_notation_line | 34 | a line that fits is shown whole | 2 | passes most truncation mutations under threshold |
| srs_notation_line | 41 | eight plies shown whole | 3 | pins the 8-ply spec; named regression |
| srs_notation_line | 53 | longer line cut to eight | 3 | fails wrong cut point + odd-ply mutation |
| srs_page_head | 15 | renders label, fires back, shows trailing | 2 | tap assert real; chevron pixels/a11y unasserted |
| srs_page_head | 37 | hides trailing / disables without onBack | 1 | no assert for either mechanism |
| srs_sheet_dismissible | 42 | fling dismisses | 3 | fails when dismissal unwired or direction wrong |
| srs_sheet_dismissible | 51 | short drag snaps back | 3 | only test holding `dismissThresholds: 0.25` |
| srs_sheet_dismissible | 60 | follows the finger mid-drag | 3 | the owner complaint's exact assert |
| srs_switch | 16 | tap toggles value+semantics | 3 | three-way assert catches flips in any of 3 |
| srs_switch | 44 | null onChanged disables | 3 | crash mutation caught via Tristate.isFalse |
| srs_toast | 44 | ink pill, not Material SnackBar | 3 | strongest widget test; guards the drift explicitly |
| srs_toast | 72 | 24px bottom, centred, width-bounded | 3 | catches all three |
| srs_toast | 96 | fades in 160ms | 3 | catches 80/320; misses duration 0 |
| srs_toast | 116 | gone after 2.4s; second replaces | 3 | three-phase timer assert + replacement |
| srs_toast | 138 | renders every tone identically | 0 | loop iterates SnackBarType.values but never passes `type:` — 3 identical iterations |
| srs_toast | 151 | Navigator context overlay | 3 | pins real production bug |
| top_bar_colour_squares | 52 | both squares offered | 2 | misses invisible/zero-size |
| top_bar_colour_squares | 59 | no text names the scope | 3 | fails the exact scope-printout regression |
| top_bar_colour_squares | 70 | side by side | 3 | catches stacking + reversal |
| top_bar_colour_squares | 80 | 44px minimum target | 3 | tagged a11y assert, both sides |
| top_bar_colour_squares | 90 | tapping reports colour | 3 | label+arg assert each other |
| top_bar_colour_squares | 100 | active colour is the marked one | 3 | symmetric toggle semantics |
| top_bar_colour_squares | 111 | wordmark when no scope | 3 | catches both-shown and neither |
| top_bar_colour_squares | 119 | colours in dark mode | 3 | luminance ordering + absolute bounds |
| top_bar_colour_squares | 143 | colours in light mode | 3 | duplicates by design (theme branches) |
| one_look | 76 | no Cupertino widget on reachable screens | 2 | closed-list scan; waiver hole on one file |
| one_look | 117 | reachable list stays pointing at files | 3 | keeps the prior test honest |
| srs_settings | 40 | Diagram layout + updates preferences | 1 | no provider/persisted/UI-echo assert on any tap |
| srs_settings | 153 | small controls inline, help on demand | 3 | dense but real: disclosure, overflow guard, reflow |
| srs_settings | 230 | selectors inline at 500px | 2 | single pair with the sub-520 case |
| srs_settings | 250 | wide settings keep visible descriptions | 3 | fails both directions of the responsive rule |
| srs_settings | 262 | About links, dead Rate row | 3 | navigation + shipped-dead-feature assert |
| board_thumbnail | 23 | SRS themes share one render decision | 2 | enumeration equality; future-theme hole |
| board_thumbnail | 39 | no stock photo previews | 3 | fails the exact reported bug, for every theme |
| board_thumbnail | 51 | SRS themes show SRS squares | 2 | misses dark square colour, hatch, line92 |
| board_thumbnail | 58 | non-SRS theme previews own squares | 3 | per-theme contains(square colour) |
| board_thumbnail | 74 | folio themes use demo colours | 2 | pure model test though |
| board_thumbnail | 83 | piece sets agree with assets | 3 | loop all PieceSet.values; strongest in file |

## GAPS (things nothing in the suite can fail)

- a11y/pixels: dialog radius 16, scrim/shadow, ink-coloured title, 22px gap above
  actions; toast 11/18 padding, 360 max-width, 10px translate, ellipsis overflow;
  top-bar accent ring (2px), 2px inter-square gap; switch/dialog colours only via
  text style; settings accent dots 44px claimed in comment but asserted nowhere.
- `SrsNotationLine.answerSan`/`showBlank`/`_FillIn` (the answer slot) untouched by tests.
- `SrsSheetDismissible` barrier-tap crossing behaviour (regressed before, no test).
- Top-bar `dueCount`/`onOverflowPressed`/`isPracticeMode`/exit-practice semantics untested.
