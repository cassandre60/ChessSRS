# 02. Tokens

Machine-readable: `tokens/tokens.json`. CSS: `tokens/tokens.css` (verbatim from the prototype). Dart: `flutter/chesssrs_tokens.dart`.
Units are logical pixels (Flutter dp / CSS px). Colour values are sRGB.

## 1. Colour

### Neutral roles

| Role | Light | Dark | Used for |
|---|---|---|---|
| `page` | `#E2E6E9` | `#050608` | Only the prototype's page background. Not part of the app. |
| `ground` | `#F1F3F4` | `#0D0F13` | App background |
| `surface` | `#FAFBFB` | `#151920` | Sheets/popovers, switch knob (off) |
| `ink` | `#101318` | `#ECEEF1` | Primary text, board frame, solid controls, retained bar |
| `ink2` | `#4B5361` | `#9BA2AE` | Secondary text, unselected controls |
| `ink3` | `#676E7A` | `#8B929D` | Quiet text, coordinates (outside), dashed blank, new-state outline |
| `hairline` | `rgba(16,19,24,.13)` | `rgba(236,238,241,.14)` | 1px separators, control outlines, switch track (off) |
| `hairlineSoft` | `rgba(16,19,24,.055)` | `rgba(236,238,241,.06)` | Hover fill, segmented track, pressed states |
| `scrim` | `rgba(16,19,24,.22)` | `rgba(0,0,0,.5)` | Behind sheets |

### Board roles

| Role | Light | Dark |
|---|---|---|
| `squareLight` (paper) | `#F8F9FA` | `#11141A` |
| `squareDark` (under hatch) | `#E7EAED` | `#161A22` |
| `hatch` (line colour) | `rgba(16,19,24,.30)` | `rgba(236,238,241,.22)` |
| `halo` (around pieces) | `#F8F9FA` | `#11141A` |
| White piece fill / outline / detail | `#FFFFFF` / `#101318` / `#101318` | `#ECEEF1` / `#0D0F13` / `#0D0F13` |
| Black piece fill / outline / detail | `#101318` / `#101318` / `#F1F3F4` | `#0D0F13` / `#ECEEF1` / `#ECEEF1` |

(In dark theme, white pieces are solid light shapes; black pieces are dark shapes with a light outline. The piece PNGs
already have these colours and the halo baked in.)

### Accents (user-selectable, one at a time; default Ultramarine)

| Id | Name | Light | Dark | Contrast on ground (light / dark) |
|---|---|---|---|---|
| `ultramarine` | Ultramarine | `#2A3FD9` | `#8A9BFF` | 6.7 / 7.5 |
| `violet` | Violet | `#6B3FD4` | `#B7A0FF` | 5.7 / 8.7 |
| `verdigris` | Verdigris | `#0B7A83` | `#5FCBD3` | 4.6 / 10.0 |
| `ochre` | Ochre | `#9A5500` | `#F2B04D` | 5.1 / 10.1 |

Derived from the active accent: `accentSoft` = accent at **11%** alpha (light) / **15%** (dark) (last-move squares,
current scope row background); `accentMid` = **24%** (light) / **30%** (dark) (selected square, note rule).

Accent is used ONLY for: the answer move text, the correction arrow, the last-move/selected square fills, the note's
left rule, the current scope row (fill + 3px left bar), "Practice" label, keyboard focus ring, filled-in answer in the
notation line, the selected accent dot's swatch. Never for buttons (buttons are ink), links, or state colours.

## 2. Typography

Fonts (bundle locally, OFL): **Instrument Sans** (400/500/600) for UI + notation; **Newsreader** (400) for study notes only.
Fallbacks: system sans / Georgia. Use tabular figures wherever numbers change.

| Style | Size / weight / tracking / line-height | Notes |
|---|---|---|
| Scope name | 17 / 600 / -0.015em / 1.2 | Ellipsis on overflow, single line |
| Due count | 14 / 400 (numeral 600) | tabular |
| Meta | 13.5 / 400 | ink2 |
| Notation line, narrow | 21 / 400 (moves 600) / -0.012em / 1.36 | numbers ink3, moves ink |
| Notation line, wide | `clamp(23, 2.4% of app width, 31)` / same / 1.3 | |
| Answer move | narrow 38, wide 52 / 600 / -0.03em / 1.1 | accent |
| Answer help | narrow 15, wide 16 / 400 | ink2, max 38ch |
| Note (Newsreader) | narrow 16.5 / 1.55, wide 19 / 1.6 | max ~46 characters wide |
| Note attribution | 13 / 400 | ink3 |
| Button (pill) | 15 / 600 | |
| Text button | 15 / 500 | |
| Kbd hint | 11 / 500 | |
| Group title | 12.5 / 500 | ink3 |
| Row name | 15.5 / 500 / -0.005em | |
| Row sub | 12.5 / 400 | ink3, tabular |
| Row due numeral | 17 / 600, "due" 12.5 ink3 | tabular |
| Segmented | 13.5 / 500 | |
| Setting label / help | 16 / 500, 14 / 400 ink2 | help max 40ch |
| Library row | 16 / 500, sub 13 / 400 ink3 | |
| Idle title | `clamp(46, 9% of app width, 76)` / 400 / -0.045em / 0.98 | |
| First-launch title | `clamp(40, 10%, 60)` / 400 / -0.04em / 1 | |
| Settings title | `clamp(38, 8%, 56)` / 400 / -0.04em / 1 | |
| Idle "next" line | 18 / 400 (bold numerals 600) | ink2 |
| Legend | 14 / 400, numerals 600 ink | |
| Toast | 14 / 500 | |
| Coordinates outside / inside | 11.5 ink3 / 9.5 (500) ink2 with halo | |

## 3. Layout

- **Breakpoint:** wide if the *app area* width >= **720**. Measure the app area (LayoutBuilder), not the window.
- **Narrow:** top bar 56; review padding L12 R12 B6; side column padding T12 H6; notation line min-height 2 lines.
  Board = `min(W - 24, H_content - 222)` where `H_content` = height below the top bar and inside safe areas.
  (Prototype phone frame: 390x800 with a 46px status bar + 16px bottom inset; real devices use safe-area insets.)
- **Wide:** top bar 60 (padding L50 R20 so the scope title aligns with the board's left edge); review padding L28 R34 B28;
  column gap 44; coordinate gutter 24 (left) and 24 (bottom); board = `min(H_content - 64, W - 480)`;
  side column max width 560, height exactly = board size; side padding-top 2.
- Settings column max 660 (centered, padding 24); idle column max 560; first-launch column max 500, gap 64 to the board.
- Minimum touch target 44 x 44.

## 4. Shape and size

| Thing | Value |
|---|---|
| Radii | pill 999; wide sheet 16; narrow sheet 22; drop area 14; button (text) 10; kbd 5; memory bar 1 (list) / 2 (big) |
| Board frame | 1.5 solid `ink`, drawn outside the board |
| Hairline | 1 |
| Focus ring | 2 solid accent, offset 2 |
| Icon button | 44 |
| Pill button | height 46, padding H22, gap 12 |
| Switch | 44 x 26, knob 20, inset 3, travel 18 |
| Accent dot | 24, ring 1.5 ink at -3.5 outset, container padding 5, gap 8 |
| Segmented | container padding 3; item padding 8/13, min width 38 |
| Row (scope) | padding 9/18; name + sub gap 6; sub items gap 10; current row: accentSoft fill + 3px accent bar (top/bottom inset 9, radius 0 2 2 0) |
| Library row | padding 14/20 |
| Search field | padding 14/18, bottom hairline |
| Sheet shadow | light `0 0 0 1px rgba(16,19,24,.08), 0 22px 48px -14px rgba(16,19,24,.30)`; dark `0 0 0 1px rgba(236,238,241,.08), 0 22px 48px -14px rgba(0,0,0,.7)` |

The sheet shadow is the only shadow in the app (used only while a sheet is open; it is static, not animated).

## 5. Motion

Easing: `cubic-bezier(0.2, 0.7, 0.2, 1)` (Flutter `Cubic(0.2, 0.7, 0.2, 1)`) for everything.

| What | Duration |
|---|---|
| Piece move (user and opponent) | 170 ms |
| View change fade (opacity only) | 160 ms |
| Note / answer appear (opacity + 3px rise) | 200 ms |
| Answer filling the notation blank | 240 ms |
| Correction arrow draw-in | 260 ms (head fades in from 170 ms over 120 ms) |
| Sheet open (opacity 150 ms, translate 180 ms from 18px below / 6px above) | 150-180 ms |
| Scrim | 140 ms |
| Pill press scale 0.97 | 100 ms |
| Switch | 160 ms |
| Toast | 160 ms in, visible 2400 ms |
| Drag lift | piece scales to 1.08 while dragged, no transition on position |
| Quiet auto-advance (correct answer with no note) | 560 ms after the piece lands |

Rules: never block input during any transition; no bounce/overshoot/spring; no shimmer; nothing counts down. Reduced motion
(`MediaQuery.disableAnimationsOf`): durations become 0 and the arrow appears fully drawn.

## 6. Sound and haptics

Three placeholder sounds in `assets/sounds/`: `move.wav` (~120 ms soft knock), `wrong.wav` (~300 ms, two lower knocks),
`done.wav` (~950 ms, two gentle sine notes). **Default off** (setting: Sound). Play `move` for both the user's and the
opponent's piece landing; `wrong` on a rejected move; `done` when reaching "Nothing due". Preload at startup
(`sound_effect` is already a dependency). Haptics (optional, off by default, per platform): light tick on piece landing,
double tick on correction. Both must respect the system's silent/haptics settings.

## 7. Layers (z-order inside the board)

background (0) < pieces < coordinates-inside (3) < arrow (4) < dragged piece (6). Sheets: scrim 10, sheet 20, toast 40.
