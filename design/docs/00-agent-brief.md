# 00. Agent brief

## Mission

Replace ChessSRS's inherited Lichess-Mobile look with the new visual identity in this package, so that a first-time
user would not suspect the app began as a Lichess Mobile fork. The redesign must be hyper-responsive (feels instant),
extremely minimal, beautiful, and must **never add friction to recall**: the primary goal is chess-knowledge retention.

Implement **exactly** what `reference/index.html` shows. Do not "improve" the design. If something is ambiguous or
impossible, stop and ask (see "When to stop and ask").

## Non-goals (do not do these)

- No scheduling / FSRS / persistence / import changes. This is a presentation-layer change.
- No gamification: no streaks, XP, confetti, mascots, badges, celebratory animation.
- No timers, countdowns, urgency pulses in recall (product decision D015: thinking time is not graded).
- No new red/green "correct/incorrect" colouring. The design deliberately avoids it.
- No glassmorphism, backdrop blur, large soft shadows, or gradients (performance and minimalism).
- No new dependencies unless listed in `docs/05` as allowed (`flutter_svg` is the only expected one).

## Authority order

1. The repo's own hard constraints in `AGENTS.md` (verification rules, coding style, tests) still apply.
2. `docs/06-repo-doc-amendments.md` changes the repo's design documents. Apply it first; after that, this package
   supersedes `PRODUCT.md` §5 ("Lichess Professional Polish"), `design.md` visual sections, and the "styles/ and widgets/
   are NOT cut" line in `CUT_PROPOSALS.md`.
3. `reference/` prototype > `docs/03` component spec > `docs/02` tokens > `flutter/` reference code.
   (If the prototype and a number in `tokens.json` differ, the CSS in `reference/styles.css` is the truth.)

## What the author could NOT see (verify by reading the repo before coding)

The author had a trimmed repository dump plus the GitHub landing page, not the full source. Inspect these yourself and
record findings at the top of your first PR description:

1. `lib/src/styles/` (Styles, LichessColors, text styles) and `lib/src/widgets/` (GameLayout, ListSection,
   PlatformScaffold/AppBar, feedback widgets, SideToPlayPiece, buttons).
2. How `ThemeData` / the app theme is built (`app.dart` or similar) and where `dynamic_system_colors` is used.
3. The tab scaffold / bottom navigation (the app currently has a two-tab shell: Review, More) and the "More" screen
   (currently shows a `lichess.org` logo and account icon).
4. Board/piece/sound preferences (`board_preferences.dart` etc.) and where chessground is configured.
5. The exact types in the installed `chessground` (`^10.1.1`) API: `ChessboardSettings`, `ChessboardColorScheme`,
   `ChessboardBackground`, piece asset types (`PieceAssets`), `StaticChessboard`, `ChessgroundImages`. Read the package
   source in the pub cache; do not rely on this package's assumptions about them.
6. The Analysis, Opening explorer and Board editor screens. (Reskinned in R12; since 2026-09-28 they are reached through
   `AnalysisHubScreen` — see open decision 1 below.)
7. Native shell: app name, bundle ids, splash (`flutter_native_splash` uses `logo-black/white.webp`), app icon, the iOS
   widget extension named `LichessWidgets`, `home_widget`, Firebase usage.

## Working protocol

- Work in the phases in `docs/05-flutter-implementation.md` §9. One phase = one PR. Do not start phase N+1 until the
  owner has approved phase N's screenshots.
- **Screenshots are required evidence** (this matches the repo's rule that passing tests is not proof of visual
  correctness). For every UI PR attach: each affected screen at *phone (390x844)*, *tablet portrait (~820x1180)* and
  *desktop (1280x800)*, in *light* and *dark*, ultramarine accent, next to the matching prototype screenshot.
  Capture the prototype the same way (open `reference/index.html`, use the toolbar).
- Prefer deleting Lichess-derived UI over restyling it, where the owner has agreed (see open decisions below).
- Keep diffs reviewable: tokens and primitives first, then screens, then removals.
- Add or update golden tests for the board background, memory bar, notation line and primitives (`docs/07`).
- Never leave two design systems side by side longer than one phase. Each phase ends with the touched screens fully
  migrated (no half-styled screens).

## Open decisions (ask the owner; do not assume)

1. ~~**Analysis board / Opening explorer / Board editor.** Keep (re-skin), fold into an "Explore" area, or cut?~~
   **Resolved 2026-09-28: fold into one screen, called `Analysis`.** `AnalysisHubScreen` lists the three tools plus a
   `Chapters of a study` entry, reached from a single `Analysis` row in the Library sheet. It replaced the three flat
   Explore rows, which left the sheet doing two unrelated jobs. The study list stays owned by the scope drawer, so the
   chapters entry opens a picker rather than inlining a second study list. The brief's premise — that these screens are
   "still Lichess-styled" and unreachable from the Library sheet — was stale by then: R12 had already reskinned all three,
   and they had been reachable since the Home-tab removal in #51.
2. **Quick annotation toggle.** The current app bar has an eye toggle. The design removes it from the top bar; the
   preference lives in Settings ("Show notes after a move", "Show arrows and circles"). If the owner wants a quick
   toggle, add it as a switch row at the top of the Library sheet, not back in the top bar.
3. **Exiting Practice mode.** The prototype shows "Practice" in the top bar where the due count normally is. Implement it
   as a tappable label with semantics "Exit practice" (44dp target). A trailing small close glyph is allowed. Confirm.
4. ~~**Platform behaviour.** The design uses one visual language on all platforms.~~ **Resolved 2026-09-28: one
   look everywhere, one deliberate exception.** The app branched on `TargetPlatform` in four reachable places, all
   of them menus or dialogs: `showChoicePicker`, `showMultipleChoicesPicker`, `showAdaptiveActionSheet` and
   `showConfirmDialog` — plus the account menu's own duplicate of the last, and the analysis board's `⋯`
   (`ContextMenuIconButton`, an iOS long-press preview). The account menu's list rows also drew a
   `CupertinoListTileChevron` on iOS and nothing elsewhere, so the same settings list pointed one way on a phone
   and another everywhere else. All of it now renders from `lib/src/design/`.
   **The exception:** the analysis share screen's date picker, a `CupertinoDatePicker` wheel on iOS against a
   Material calendar elsewhere. That is the same control reached two different ways — spin-and-stop against
   tap-a-day — which is a platform *behaviour* as much as an appearance, and this decision's own rule keeps
   behaviours. Whether iOS should get a calendar instead is still open and is not settled here.
   `test/design/one_look_test.dart` guards the rest and names this one exception in the code, so it cannot be
   forgotten or quietly widened.
5. ~~**Bespoke art.** Piece set, wordmark, icon and sounds here are placeholders. Ask before spending effort refining them.~~
   **Partially resolved 2026-09-28; sounds remain open.** Checking each item showed the sentence was half stale:
   the piece set is already bespoke (`lib/src/design/piece_set.dart`, wired as the default in
   `board_preferences.dart`) and the wordmark is already the geometric square mark (`SrsLogoMark`,
   matching `assets/brand/mark.svg`, used on first launch and About). Owner decision: wire the brand
   icon now, leave sounds. The Android adaptive-icon foreground was still the inherited Lichess knight
   vector and is now the brand mark redrawn as explicit strokes (VectorDrawable has no pattern fill);
   the iOS marketing icon and the Play-store png were the same inherited art and are now
   `assets/brand/icon-1024.png`. Sounds stay Lichess: `assets/sounds/diagram/` holds only 3 wavs
   against the 10 sounds the service loads, `SoundTheme` has no diagram entry, and the service falls
   back to `standard` — wiring it is a sound-design task, not a file move, and was explicitly deferred.
6. ~~**Fonts.** Instrument Sans + Newsreader are the design's fonts. If the owner prefers others, only `SrsText` changes.~~
   **Resolved 2026-09-28: confirmed as-is, no change.** Both families are declared in `pubspec.yaml`,
   bundled under `assets/fonts/`, and `SrsText` (`lib/src/design/tokens.dart`) is the single funnel —
   zero hardcoded font families outside `lib/src/design/`. The brief's conditional holds: preferring
   others would touch only `SrsText`.

## When to stop and ask

Stop, write down exactly what you found, and ask the owner if:
- chessground cannot render a transparent-square board under our own background (see `docs/05` §4 Plan B/C).
- A requirement here conflicts with a hard constraint in `AGENTS.md` or with the product's scheduling behaviour.
- You need a new dependency, or you want to change anything in `lib/src/domain`, `persistence`, `import` or `review`
  logic (other than the presentation-facing state you must expose).
- A screen or state is not covered here or in the prototype and the extrapolation rules in `docs/03` §12 do not settle it.

## Definition of done (whole project)

- [ ] `docs/06` amendments merged.
- [ ] Every screen reachable in normal use uses `Srs*` tokens and primitives; no `Colors.*`, `LichessColors.*`,
      `Theme.of(context).colorScheme.*` or Material widgets remain in migrated screens.
- [ ] No Lichess board, pieces, sounds, icons fonts, logos or wordmarks are bundled or reachable (`docs/07` §1).
- [ ] The Review screen matches the prototype at all three sizes, both themes, all four accents (`docs/07` §2).
- [ ] Feedback region never changes height; the board never moves or resizes between prompt / correction / note.
- [ ] Reduced-motion, screen-reader and keyboard paths work (`docs/04` §6).
- [ ] Performance budget met on a mid-range Android device and an older iPhone (`docs/07` §5).
- [ ] Licence audit done and an About/Licences screen exists (`docs/07` §6).
- [ ] The five-second recognition test has been run by the owner (`docs/07` §3).
