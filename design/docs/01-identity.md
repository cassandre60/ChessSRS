# 01. Identity: "Diagram"

## The idea

The board is drawn like a diagram in a printed chess book: paper squares, ink-hatched squares, a thin ink frame,
coordinates outside the board on wide screens. Around it the interface is quiet: cool neutral surfaces, blue-black ink,
one accent colour, and typography that treats **the line of moves as the headline**. Nothing decorates; everything that
is on screen is either the position, the line, or the one action you can take.

Why it looks different from Lichess (and from Chess.com, and from the app's previous cream/brown Material look):
- **Board and pieces:** hatched print-diagram board with an original piece set, not brown/green boards with stock sets.
- **Palette:** cool neutrals + one accent, not a warm tonal Material palette.
- **Structure:** no bottom navigation, no drawer, no app-bar controls, no chips. One title, one button.
- **Typography:** an interface sans with tabular numerals, notation with figurines drawn from our own set, a reading
  serif only for study commentary.
- **Sound and motion:** a bespoke soft sound set and a short list of motion rules.

## Principles (each one is testable)

1. **Chrome budget.** On the Review screen, non-board persistent elements are: the scope title (which opens the scope
   list), the due count, and one overflow button. Nothing else. Skip/Continue live in the feedback region and appear
   only when relevant.
2. **Fixed regions.** The board rectangle never changes size or position between prompt, correction, note and idle-to-
   review. The feedback region has a fixed height; content scrolls inside it (fade at the bottom on narrow layouts).
3. **No urgency.** No timers, countdowns, pulsing, progress rings in recall. Thinking time is not graded.
4. **Encode by shape, not colour.** Memory states use solid / hatch / outline. Correct vs incorrect is never
   green/red. The accent marks "the move you should play" and "selected", nothing else.
5. **One accent at a time.** Four accents ship; the user picks one; all pass WCAG AA on both themes.
6. **Motion explains board state.** Piece moves 170 ms, arrow draws 260 ms, text fades 200 ms. Nothing blocks input.
   Reduced-motion collapses everything to instant.
7. **Plain words.** Sentence case, no exclamation marks, one vocabulary (see §4).
8. **Instant.** No spinners for local data; optimistic UI; no layout shift; 120 Hz friendly (no blur, no big shadows).
9. **One look, every platform.** Platform *behaviours* are kept — back gestures, scroll physics, haptics, the platform
   date picker. Platform-specific *looks* are not: the same control is the same control everywhere, so a menu, dialog,
   choice list or list row does not change appearance with the device. Enforced by `test/design/one_look_test.dart`,
   which fails on any Cupertino widget in a reachable screen.

## What replaced what (from the previous build)

| Previous build | New design |
|---|---|
| Drawer: search, "All Studies", "Opening Hubs", per-study rows with tonal chips, pause toggle, three-dot menu | One **scope list**: popover on wide layouts, bottom sheet on narrow. Due count is a plain numeral. |
| Bottom navigation "Review / More" | **None.** A `⋯` button opens the **Library** sheet (Import, Explore, Settings, About). |
| More tab headed by a `lichess.org` logo and account icon | Gone. No account, no branding. |
| Brown board, heavy-outline stock pieces | Print-diagram board (hatched dark squares, ink frame) + original piece set. |
| Orange/peach Material tones on every control | One accent, used only for the answer move, the arrow, selection, the note rule. |
| App bar: menu, title + chip, eye toggle, tune, exit-practice | Scope title + due count + `⋯`. Preferences moved into Settings. |
| Header row (side piece icon + chapter title) + "Your move (White)" | Small context line + "White to play" + the **notation line** as the headline. |
| Tonal feedback card with icon, title, Continue button, comment truncated after ~6 lines | **Note**: full text in a reading face, 2px accent rule at left, one Continue pill. |
| Red lapse card with a sentence | **Correction**: pen-stroke arrow on the board + the move set large in accent. No red. |
| "All Caught Up!", 80px icon, progress bar, "% mastered" | "Nothing due." + a 3-state **memory bar** (retained / learning / new). |
| `CircularProgressIndicator` while loading | Nothing (local data is instant). |
| Material dialogs, sheets, list tiles, switches, chips | Own primitives (`flutter/primitives.dart`). |

## Copy: voice rules

- Sentence case everywhere. No exclamation marks. No emoji. No "Oops".
- Say what happened or what to do, in the fewest words. Never scold, never congratulate.
- Numbers: tabular figures; write durations in words ("3 hours 20 minutes") in body copy, short forms ("3 h") only if space demands.
- One noun for the content unit. **Decision needed from owner: "Repertoire" or "Study".** The prototype uses
  "repertoire" for the user's imported collections and "Study" only in "From your study" (source attribution).
  Apply one choice consistently; if the app's data model says Study, map UI text to the owner's choice.
- Do not say "mastered". Use **retained / learning / new** (see `04` §7 for the mapping from FSRS data; thresholds are
  a product decision).

## Copy: string table (English source strings)

Hard-coded English first (repo convention), then localise later. `{}` = dynamic.

| Where | String |
|---|---|
| Top bar due | `{n} due` (numeral in ink 600, "due" in ink2) |
| Top bar practice | `Practice` (accent, 600) |
| Meta line | Study/chapter title as provided (prototype placeholder: `White vs Scandinavian, opening`) |
| Side to move | `White to play` / `Black to play` |
| Correction help | `Play this move to continue. The position will come back soon.` |
| Feedback actions | `Skip`, `Continue` |
| Note attribution | `From your study` |
| Idle title | `Nothing due.` |
| Idle next | `Next review in {3 hours 20 minutes}.` |
| Idle legend | `{n} retained`, `{n} learning`, `{n} new` |
| Idle actions | `Practice`, `Choose a repertoire` |
| Idle footnote | `Practice never changes your schedule.` |
| Scope search | placeholder `Search` |
| Scope groups | `Everywhere`, `Openings`, `Repertoires` |
| Scope first row | `All repertoires` |
| Scope row sub | `{n} positions` or `Paused` |
| Scope row due | `{n}` + `due` |
| Scope empty | `Nothing matches “{query}”.` |
| Library rows | `Import PGN` (sub: `From a file, pasted text or a Lichess study`), group `Explore`: `Analysis` (sub: `Analysis board, explorer, editor, chapters`); `Settings`; `About and licences` |
| First launch | wordmark `ChessSRS`; `Bring your repertoire.`; `Import a PGN or a Lichess study. Everything stays on this device, and reviews work offline.`; drop area `Drop a PGN file here`; button `Choose file`; links `Paste PGN text`, `Import a Lichess study`; `Train as` `Auto` `White` `Black` |
| Import success toast | `Imported {n} positions from {file}.` |
| Settings | title `Settings`; back `Review`; `Daily limit` (`Positions reviewed per day.`); `Target retention` (`Higher means more reviews. 88% suits most players; 95% is for tournament preparation.`); `Show notes after a move` (`Comments from your study appear once you have answered.`); `Show arrows and circles` (`Drawn from your study, only after you answer.`); `Accent` (`Used for the move you should play and for selection.`); `Theme` `Light`/`Dark` (add `System`); `Sound` (`Soft move and correction sounds.`); `Advanced`: `Scheduling algorithm` (`FSRS adapts to how well you remember each position.`), `Diagnostics` (`Show memory metrics during review.`) |
| Screen-reader live | `Correct. {san}.` / `Not this move. The repertoire move is {san}.` |

Strings that exist only in the prototype (do **not** ship): `... is shown as a placeholder in this prototype.`

## Anti-patterns (reject in review)

Streaks, XP, badges, confetti, mascots; red/green feedback; gradients; glass/blur; drop shadows other than the sheet
shadow; coloured chips; filled icon buttons; centered giant empty-state icons; "!" in copy; spinners for local data;
multiple filled buttons on one screen; more than one accent visible at once; hard-coded `Colors.*` in UI code.
