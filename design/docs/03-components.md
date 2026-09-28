# 03. Components

Measurements are from `reference/styles.css`. "Narrow" / "wide" = app-area width < / >= 720. All colours are token
roles from `02-tokens.md`. Behaviour details live in `04-screens-and-flows.md`.

---

## 1. App frame

- Background `ground`. No page chrome, no bottom navigation, no floating buttons.
- Structure top to bottom: (platform status bar) → **top bar** → **screen content**. Overlays (scrim, sheets, toast) sit above.
- Respect safe areas (notch, home indicator). The prototype's phone frame shows a 46px status bar and 16px bottom inset
  as stand-ins for these.
- Screen changes crossfade opacity only (160 ms). No slide/scale route transitions anywhere.

## 2. Top bar

Height: narrow 56, wide 60. Padding: narrow L16 R4; wide L50 R20. Items centred vertically, gap 6 (narrow).

Left to right: **Scope button**, **due count**, spacer, **overflow button**.

- **Scope button**: a text button with no border. Text = current scope name (17/600, single line, ellipsis) + a 12px
  chevron-down (stroke 1.8, `ink2`) with gap 8. Padding 7/10, margin-left -10 (so the text aligns with the content edge),
  radius 10, hover fill `hairlineSoft`. Tapping toggles the scope list. `aria-haspopup="dialog"`, expanded state exposed.
  Must shrink (flex 0 1 auto) so the due count and overflow button never get pushed off narrow screens.
- **Due count**: `{n} due`, 14, `ink2`; the numeral is 600 `ink`, tabular. In Practice mode show `Practice` (accent, 600) instead.
- **Overflow button**: 44x44 circular hit area, three dots (20px icon, `ink` fill, dots r=1.7 at x=4,10,16), hover fill `hairlineSoft`.
  Label "Library and settings". Opens the Library sheet.
- Hidden per screen: on *first launch* the scope button and due count are hidden (overflow stays); on *settings* the whole bar is hidden.

## 3. Board

The board is a stack of layers inside a square of size `b`:

1. **Background**: paper + hatched dark squares + frame (see §3.1).
2. **Highlights**: last-move squares (`accentSoft`), selected square (`accentMid`). Drawn above the background, below pieces.
3. **Pieces**: one image per piece filling its square, positioned by translate; animated 170 ms.
4. **Coordinates** (narrow only, inside squares).
5. **Arrow** (correction).
6. **Dragged piece** on top.

Outside the square (wide only): rank labels (left gutter 24) and file labels (bottom gutter 24).

### 3.1 Background geometry

- 8x8 squares, `sq = b / 8`. a1 is a dark square: dark iff `(fileIndex + rowFromTop)` is odd.
- Fill all with `squareLight`; fill dark squares with `squareDark`.
- **Hatch** on dark squares only: 45-degree lines running "/" (bottom-left to top-right), colour `hatch`, line width **1.1 px**,
  perpendicular spacing `gap = clamp(4.6, b/100, 7)` px. The hatch is **one continuous pattern across the whole board**
  clipped to the dark squares (lines continue across diagonally adjacent dark squares); it is not restarted per square.
  Reference: `flutter/hatch.dart`, `flutter/board_background.dart`.
- **Frame**: 1.5px solid `ink`, entirely outside the board (does not shrink the board).
- Background is static: render once, wrap in a repaint boundary, never repaint during drag/animation.

### 3.2 Coordinates

- **Wide, outside:** ranks 8..1 at the left, each row centred vertically, right-aligned with a 10px gap to the board;
  files a..h below, each centred on its column, 8px below the board. 11.5px, `ink3`, tabular.
- **Narrow, inside:** file letters at the bottom-right of the rank-1 squares (padding right 3, bottom 2); rank numbers at the
  top-left of the a-file squares (padding left 3, top 2). 9.5px, weight 500, `ink2`, with a `halo`-coloured 3px text-shadow
  (twice) so they stay legible over the hatch.
- Flip order when the board is oriented for Black.

### 3.3 Pieces

- Assets: `assets/pieces/{light|dark}/png-256|png-512/{w|b}{K|Q|R|B|N|P}.png` (square images, transparent, halo baked in).
  Choose the folder by the *current brightness*. Source SVG viewBox is `5 2 90 90`.
- The image fills its square edge to edge (padding is already inside the image).
- Move animation 170 ms, ease. **No** rotation, shadow, or scale on normal moves.
- **Drag:** pointer must move more than **5px** to become a drag. The dragged piece follows the pointer centred on it, scales
  to **1.08**, has no position transition, and is on top. On release over a different square attempt the move; otherwise
  animate back to its origin (170 ms).
- **Tap-to-move:** tapping your own piece selects it (square gets `accentMid`); tapping another square attempts the move
  *immediately on pointer down* (do not wait for release; this is part of the "instant" feel). Tapping another of your own
  pieces switches the selection. Tapping the selected square again keeps it selected.
- Valid-move dots: **off**. (The prototype shows none. They add noise; they do not leak the repertoire answer, so the owner
  may enable them later.)
- Only the user's side can be picked up. Opponent replies are animated by the app.

### 3.4 Highlights

- Last move: both squares filled with `accentSoft`. Selection: `accentMid`. Each is a plain square fill; no borders, no dots.

### 3.5 Correction arrow

- Curve from the centre of the source square to the centre of the destination square: quadratic Bézier whose control point
  is the midpoint offset perpendicular by **13% of the distance** (bow).
- Board space is 80 units wide (square = 10 units). Stroke **1.2 units** (1.5% of the board), round cap, colour `accent` at **88%** opacity.
- Head: filled triangle, tip inset **0.9 units** before the destination centre, length **3.3**, half-width **1.8**, oriented along the
  curve's end tangent. The stroke ends at the head's base.
- Animation: stroke draws from 0 to full over **260 ms** (ease); head fades in from **170 ms** over **120 ms**.
- It sits above pieces, below the dragged piece, ignores pointer input, and never blocks moving pieces.
- Knight moves use the same curved arrow (do not draw L-shaped arrows; that is the Lichess convention).
- Reference: `flutter/move_arrow.dart`.

## 4. Review side column

Regions, top to bottom (all fixed; only the slot's *content* changes):

| Region | Narrow | Wide |
|---|---|---|
| **Meta** | one row: context label left, side-to-move right; 13.5 `ink2` | two stacked lines: context label, then side-to-move; gap 8; padding-top 2 |
| **Notation line** | margin-top 8; 21px; min-height = 2 lines | margin-top 22; `clamp(23, 2.4% width, 31)`; line-height 1.3; min-height = 2 lines |
| **Slot** | flex 1, scrolls; padding 10/0/22; bottom fade over the last 22px | flex 1, scrolls; padding-top 26; no fade |
| **Actions** | min-height 56; padding 6/0/4; Skip left, Continue right | same |

The wide column's height equals the board's height and its bottom edge aligns with the board's bottom edge.

- **Side-to-move indicator:** an 11px circle (outline 1.5px `ink`; filled `ink` for Black) + `White to play` / `Black to play`.
- **Context label:** the study's chapter title (one line). Do not invent text.
- **Notation line:** "the line is the headline." Move pairs `1. e4 d5  2. exd5 ♛xd5  3. ____`. Numbers `ink3` 400; moves `ink` 600;
  spacing: number-to-move .22em, between moves .42em. Each **pair is unbreakable** (a move number never wraps away from its
  move). Piece letters K Q R B N are replaced by **figurines** (`assets/figurines/*.svg`, single colour = text colour,
  width .82em, height .96em, .12em below the baseline). The current decision shows a **dashed blank** (2.3em wide, 1.05em tall,
  2px dashed `ink3` underline). When answered the blank is replaced by the move in `accent` 600, fading in over 240 ms with a 3px rise.
  Long lines: show at least the last 8 plies; if truncated, start with `…`. (Not in the prototype; extrapolation.)
- **Slot content (exactly one of):**
  - *Nothing* (prompt).
  - **Answer** (correction): the correct move in `accent`, 38 (narrow) / 52 (wide), 600, figurine included; below it the help
    line (`ink2`, 15/16). Appears with the 200 ms fade+rise.
  - **Note** (after a correct move, if the position has a comment and notes are enabled): a `blockquote` with a **2px `accentMid` left rule**,
    padding-left 16, no background, text in Newsreader (16.5 / 19), max ~46 characters wide, then `From your study` (13, `ink3`, margin-top 10).
    **Never truncate**; scroll instead.
- **Actions:** `Skip` (text button, left; hidden while a note is showing or during the quiet auto-advance) and `Continue`
  (pill, right; only while a note is showing). Keyboard hints `S` / `Space` appear only where a hardware keyboard is likely.

## 5. Buttons and small controls

- **Pill button** (`SrsPillButton`): height 46, padding H22, radius 999, background `ink`, label `ground` 15/600, optional kbd hint (gap 12).
  Pressed: scale 0.97 over 100 ms. **The only filled button; at most one per screen.**
- **Text button**: no background, `ink2` 15/500, padding 10/12, radius 10; hover: text `ink`, fill `hairlineSoft`; min height 44.
- **Link** (inline, e.g. "Choose a repertoire"): `ink` 15/500, underline 1.5px, offset 4px, underline colour `ink3` → `ink` on hover.
- **Kbd hint**: 11/500, padding 3/6, radius 5, `ink2` on `hairlineSoft` with a 1px `hairline` outline; on a pill: text `ground`, background `ground` at 16%.
- **Segmented control**: pill track (`hairlineSoft` + 1px `hairline`), padding 3; items 13.5/500, padding 8/13, min width 38, radius 999;
  selected item: `ink` background, `ground` text; unselected `ink2` (hover `ink`). Wraps if it must.
- **Switch**: 44x26; off = track `hairline`, knob `surface` with a 1px `hairline` ring; on = track `ink`, knob `ground`; travel 18; 160 ms.
- **Accent dots**: see `02` §4. Two places: Settings row and (prototype only) the toolbar.
- All interactive: 2px accent focus ring at offset 2, keyboard activation with Enter/Space, `Semantics` button/toggled.

## 6. Scope list (replaces the drawer)

Presentation: **wide** → popover anchored under the top bar, left 26, top = top bar height (56), width `min(470, W - 52)`, max-height `H - 80`,
radius 16. **Narrow** → bottom sheet, left/right/bottom inset 8, radius 22, max-height `min(82% of H, 720)`, with a 36x4 grabber (`hairline`, top margin 8).
Background `surface`, sheet shadow (`02` §4). Scrim behind (`scrim`, 140 ms). Dismiss: scrim tap, Esc, selecting a row.

Contents:
1. **Search field** (fixed): padding 14/18, magnifier icon 18px stroke `ink3`, input 16, placeholder `Search` (`ink3`), bottom hairline. Autofocus on
   devices with a hardware keyboard only (avoid raising the soft keyboard on touch). Filters rows by case-insensitive substring; empty result: `Nothing matches “{q}”.` (`ink2` 15, padding 28/18).
2. **Scrollable list** with group titles `Everywhere`, `Openings`, `Repertoires` (12.5/500 `ink3`, padding 14/18/4).
3. **Row** (full width button, padding 9/18, gap 14): left column = **name** (15.5/500, one line, ellipsis) and, 6px below, a **sub line**: a 96x5 memory
   mini-bar (see §8) + text `{n} positions` (12.5 `ink3`) or `Paused`; right = due numeral (17/600, tabular) + `due` (12.5 `ink3`) baseline-aligned.
   - Hover: `hairlineSoft` fill. **Current** scope: `accentSoft` fill + 3px accent bar at the left.
   - Zero due: numeral `ink3`, weight 500. Paused: name and numeral `ink3`.
4. Row actions (pause, rename, delete, chapters, export) are NOT in the list row. Reveal them via long-press / secondary click / an
   `…` affordance that appears on hover (desktop), opening the existing study actions in the new sheet style. (Extrapolation, see §12.)

Data order: Everywhere (All repertoires) → Openings (hubs) → Repertoires (studies). Same data as the old drawer.

## 7. Library sheet (replaces the "More" tab)

Presentation like the scope list but **anchored top-right** on wide (right 20, top 56, width 310). Rows (16/500, padding 14/20, hairline between groups):
group 1 `Import PGN` (sub 13 `ink3`: `From a file, pasted text or a Lichess study`); group 2 titled `Explore` (12.5 `ink3`, padding-left 20): a single
`Analysis` row (sub 13 `ink3`: `Analysis board, explorer, editor, chapters`); group 3 `Settings`, `About and licences`. Each row ends with a 14px chevron-right (`ink3`).
No icons on rows, no account entry, no wordmark.

**Resolved 2026-09-28 (open decision 1 in `00`):** the three Explore destinations were rows here and are now one screen,
`AnalysisHubScreen`, which this row opens. The sheet was doing two unrelated jobs — choosing a repertoire to review, and listing
tools. The hub lists `Analysis board`, `Opening explorer`, `Board editor` under a `REPERTOIRES` group with `Chapters of a study`,
which opens a study picker and then the existing chapters screen. The picker is a sheet rather than a list on the hub on purpose:
the scope drawer already owns the study list, and a second one beside it would be a competing home rather than a choice.

## 8. Memory bar (retained / learning / new)

Shape-coded: **retained** = solid `ink`; **learning** = 45° "/" hatch in `ink`, line 1.2px, spacing 3.2px; **new** = transparent with 1px `ink3` outline.
Segments are flex-proportional to counts with a gap between them. Two sizes:

| | height | gap | radius | width |
|---|---|---|---|---|
| list (scope rows) | 5 | 2 | 1 | 96 |
| large ("Nothing due") | 10 | 3 | 2 | fill column |

Exposes one semantic label: `{n} retained, {n} learning, {n} new`. Legend on the large bar: 12x12 swatches with the same fills
(learning swatch also has a 1px `ink3` outline), 14px text, numerals 600 `ink`, gaps 8 (swatch-text) and 22 (items).
Definition of the three states from scheduler data: `04` §7.

## 9. "Nothing due" screen

Centered column max 560, left-aligned text, vertical centre. Padding H24, bottom 40.
Order: title (`Nothing due.`) → `Next review in {duration}.` (margin-top 18, 18px `ink2`, bold numerals) → large memory bar (margin-top 40, bottom 14)
→ legend → actions (margin-top 36): **Practice** pill (kbd `P`) + link `Choose a repertoire` (gap 18) → footnote `Practice never changes your schedule.` (13.5 `ink3`, margin-top 18).
No icon, no illustration, no confetti.

## 10. First-launch / import screen

Column max 500, left-aligned. Wide layout: column + a static, non-interactive **diagram board** of the starting position on the right (gap 64,
board = `min(H - 170, W - 690)`, with outside coordinates). Narrow: column only.
Order: wordmark (the 22px mark + `ChessSRS` 16/600) with 36px below → title `Bring your repertoire.` → lede (17 `ink2`, max 38ch, margin-top 16) →
**drop area** (margin-top 32, padding 26/22, radius 14, **1.5px dashed `ink3`**, contains `Drop a PGN file here` and a **Choose file** pill) →
two links (`Paste PGN text`, `Import a Lichess study`; margin-top 16, gap 22) → `Train as` + segmented `Auto / White / Black` (margin-top 26).
Also used as the body of the *Import* sheet/dialog after first launch (`Import PGN` in Library).

## 11. Settings screen

Full screen (top bar hidden). Header: back text button `‹ Review` (top-left, padding 8/12). Column max 660 centered, padding 6/24/56.
Title `Settings` (see type table) with margin 6/0/24. Rows separated by 1px `hairlineSoft`; the group has a 1px `hairline` top border.
Row = label (16/500) + help (14 `ink2`, margin-top 3, max 40ch) left, control right; padding 18/0; gap 24; **stacks vertically when the app area is narrower than 520**.
Order: Daily limit (segmented 25/50/100/150/200/None) → Target retention (80/85/88/90/95%) → Show notes after a move (switch) → Show arrows and circles (switch)
→ **Accent** (accent dots) → Theme (segmented Light/Dark; add System) → Sound (switch) → **Advanced** disclosure (chevron rotates 180°): Scheduling algorithm (FSRS/Simple/Ease), Diagnostics (switch).

## 12. Screens/states NOT designed in the prototype (extrapolation rules)

Apply the system; keep them obviously the same family; **send screenshots to the owner for sign-off**.

- **Loading:** show nothing but `ground`. No spinner. If a load truly exceeds ~250 ms, fade in a single line `Loading…` in `ink2` at the idle screen's position. Prefer fixing the latency.
- **Error:** idle-style column: title 32/400 (`Something went wrong.`), one `ink2` sentence saying what happened, a **pill** `Try again`, a text button `Copy details`.
- **Dialogs (rename, delete, export options):** centered card on `surface`, radius 16, padding 24, max width 400, sheet shadow, scrim; title 20/600; body 15 `ink2`; actions right-aligned:
  text button (cancel) then pill (confirm). **No red.** Destructive copy must name the item: `Delete “{name}” and its {n} positions? This cannot be undone.`, confirm label `Delete`.
  Text inputs: 16px, 1px `hairline` bottom border (2px `ink` when focused), no filled/outlined boxes.
- **Study chapters screen:** same layout as Settings (back button, big title = study name) with rows like scope rows (name, memory mini-bar, positions, due numeral).
- **Study actions** (Chapters, Analyze, Practice, Export, Rename, Delete): a Library-style sheet of text rows (16/500, no icons), anchored to the row that opened it on wide layouts.
- **Toast:** ink pill (`ink` bg, `ground` text 14/500), bottom 24, centered, padding 11/18, fades in 160 ms (translate 10px), visible 2.4 s. One line, no actions.
- **Analysis / Explorer / Board editor:** reuse `SrsBoardBackground`, tokens and primitives; drop Lichess widgets and icons. Reached from the Library sheet's single `Analysis` row, which opens `AnalysisHubScreen` (open decision 1, resolved 2026-09-28).
- **Practice mode banner:** none. The top bar shows `Practice` in the due-count slot (see `00` open decision 3).
- **About and licences:** Settings-style page: wordmark, version, `Based on Lichess Mobile (GPL-3.0)` with links, then the standard licence list.
