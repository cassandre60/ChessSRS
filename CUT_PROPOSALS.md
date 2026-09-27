# Lichess Mobile Cut Proposals

Status: **ACTIVE — Phase 1 F5+ staged cuts in progress.**

This document is the authoritative record of what is removed, what is kept,
and why. Update it before executing any cut. Future agents: read this entire
file before touching anything.

The guiding rule:

> Trim the Lichess **product**. Preserve the Lichess **technical foundation**.
> When uncertain: keep it. Delete less, verify more.

---

## Execution status key

- `[ ]` not started
- `[~]` in progress
- `[x]` DONE — verified (analyze 0 + all tests pass + app launches)
- `[K]` KEEP — owner decision: do not remove
- `[G]` GREY — owner undecided; leave untouched until explicit approval
- `[T]` TRIM-LATER — defer to Phase 6 refinement

---

## Owner decisions (recorded 2026-09-14)

These are the authoritative decisions from the owner. Do not override them.

| # | Decision | Rationale |
|---|---|---|
| C1 Firebase | `[G]` GREY | Undecided — leave untouched |
| C2 Notifications | `[G]` GREY | May be needed for SRS review reminders (like Anki) — leave untouched |
| C3 Auth/login | `[K]` KEEP | Login is optional but enables importing Lichess/chess.com studies; app is 100% functional offline without it |
| C4 Online play | `[x]` DONE | Removed 2026-09-15 — lobby, seeks, challenges, view/play, model/lobby, model/challenge |
| C5 Server games | `[x]` DONE | Removed 2026-09-15 — server game lifecycle, correspondence, GameScreen, ongoing games |
| C6 Puzzles tab | `[x]` DONE | Removed 2026-09-15 — tab, model/view dirs, deep links, quick action; shared FeedbackTile/SideToPlayPiece moved to widgets/feedback.dart |
| C7 Watch tab | `[x]` DONE | Removed (commit dd996ee74) — docs marked late in C6 commit |
| C8 Social | `[x]` DONE | Removed 2026-09-15 — removed Community/Players/Friends, Inbox from More tab & account menu, Home friends carousel, and message service poller |
| C9 Learn tab + coord training | `[x]` DONE | Removed 2026-09-14 |
| C10 Blog/recap/announce | `[x]` DONE | Removed 2026-09-15 — models, services, home carousel, test |
| C11 Over-the-board game | `[x]` DONE | Removed 2026-09-14 |
| C11 Chess clock tool | `[x]` DONE | Removed by owner request 2026-09-14 |
| C12 Offline computer play | `[G]` GREY | Owner undecided; leave untouched until explicit approval |
| C13 Engine (Stockfish) | `[G]` GREY | May be useful as optional import advisor — undecided |
| C14 Opening explorer | `[K]` KEEP | Owner decision |
| C15 Analysis screen | `[G]` GREY | Undecided — shares widgets with study; leave untouched |
| C16 Board editor | `[K]` KEEP | Owner decision |
| C17 WebSocket | `[K]` KEEP | Owner decision (2026-09-16) — kept for study sync, cloud Stockfish evaluation, and future sync |
| C18 HTTP repos | `[K]` KEEP | Owner decision (2026-09-16) — base HTTP, auth, study import, opening explorer, and tablebase kept; dead online repos trimmed |
| UI-A Donate / patron links | `[x]` DONE | Removed (commit 1af79eab3) |
| UI-B "About Lichess" in More tab | `[x]` DONE | Removed (commit 1af79eab3) |
| UI-C "Lichess is a free…" message (LichessMessage widget) | `[x]` DONE | Removed (commit 1af79eab3) |
| UI-D "Welcome to the Lichess app" card | `[x]` DONE | Removed (commit 1af79eab3) |
| UI-E "Not all features available" text | `[x]` DONE | Removed (commit 1af79eab3) |
| UI-F App background theming | `[x]` DONE | Removed 2026-09-27 — see the note below |

**C8 Social note**: Friends list, inbox, player search, and relations navigation
entries were removed from the More tab and Account menu; the Home screen friends
carousel was removed; the background message service was silenced; and the relation
repository, following_user model, and follow/block actions were pruned in Step 15.
Base user/account models remain for C3 (auth).


**UI-F App background note**: The setting was removed because it could not work, not
because it was judged unimportant. Two independent facts, each verified in the code:

1. **Its only consumer was unreachable.** `makeAppTheme` in `lib/src/theme.dart` was
   defined and never called — `app.dart` builds the Diagram theme through
   `srsThemeData(srsColors)`. The background fed `_makeBackgroundImageTheme`, a
   translucent-surface theme whose whole purpose was letting a background show through,
   and that in turn was reachable only from `makeAppTheme`. The preference was stored
   and read by nothing that ran. Separately, `scaffoldBackgroundColor: c.ground` is
   opaque in `theme_bridge.dart`, so even the dead path could not have shown through.
2. **The Diagram palette is specified against a fixed `ground`.**
   `design/docs/02-tokens.md` tabulates "Contrast on ground (light / dark)" and
   `tokens.dart` states "Every value passes 4.5:1 against ground and surface in its own
   theme". `ground` is `#F1F3F4` / `#0D0F13`, defined as "App background". A
   user-chosen image behind `ink` text invalidates the one guarantee the token system
   rests on, and nothing tests it against an arbitrary background.

Making the feature work was therefore not a small fix: it meant either dropping that
contrast guarantee or building image-luminance sampling to pick light or dark per
picture, which is feature creep the feature policy forbids by default. Leaving a picker
that visibly selects a background and changes nothing was the worst of the three
options, so it went.

Reversal, if the owner disagrees: do not set `scaffoldBackgroundColor` in
`theme_bridge.dart` and restore `FullScreenBackground` in `buildScreenRoute`. The
deleted code is in this branch's parent commits.

Removed with it: `lib/src/widgets/background.dart`,
`lib/src/view/settings/background_theme_choice_screen.dart`, the `BackgroundColor`
enum, the `BackgroundImage` sealed class and its JSON converter, `setBackground`, the
`isForcedDarkMode` forced-dark escape hatch in `app.dart`, and the
`usingCustomBackground` branch in `game_summary_table.dart`. `lib/src/theme.dart`
survives at 50 lines holding only `CustomTheme`, which two explorer views read through
`context.lichessTheme`.

---

## Safe execution order

Each step is ONE logical change, ONE commit. Gate: `fvm flutter analyze` (0
issues) + `fvm flutter test` (all pass) + `fvm flutter run -d linux` (app
launches, manual spot-check) before proceeding to the next step.

**NEVER batch multiple steps into one commit.**

```
Step 1  [x]  C9  — Learn tab + coordinate training                  DONE
Step 2  [x]  UI  — Lichess branding strings from home + more screens DONE
Step 3  [x]  C7  — Watch tab (TV / tournaments / broadcasts)  DONE (dd996ee74)
Step 4  [x]  C6  — Puzzles tab                                DONE
Step 5  [x]  C11 — Over-the-board game & Clock tool             DONE
Step 6  [x]  C10 — Blog / recap / announce (home carousels + model) DONE
Step 7  [x]  C4  — Online play: lobby / seek / challenges           DONE
Step 8  [x]  C5  — Server game lifecycle + correspondence       DONE
Step 9  [x]  C8  — Social navigation & Home carousel & Message poller DONE
Step 10 [K]  C17 — WebSocket (KEPT by owner decision for study sync / cloud eval)
Step 11 [K]  C18 — HTTP network & core repositories (KEPT for auth / study / explorer)
Step 12 [x]  Tab reduction: clean 2-tab shell (Review + More) — Home tab removed DONE
Step 13 [x]  C8  — Dead social views & message models (b8664182d)      DONE
Step 14 [x]  User— Dead leaderboard & online bot screens/providers (b0ad26284) DONE
Step 15 [x]  C8  — Dead relation repository, following_user & follow/block actions DONE
Step 16 [x]  C4  — Dead playban dialog, notification model & account service monitoring DONE
Step 17 [x]  UI/Widgets — Dead orphaned widgets, views & assets (UserContextMenu, ServerOutageDisplay, ExpandedSection, SideIndicator, TextBadge, BrightnessNotifier) DONE
Step 18 [x]  C5/C6 — Dead Android system gestures exclusion utility & method channel handler DONE
```

Steps beyond 12 (C12 offline computer, C13 engine) are blocked on owner
GREY decisions and are not started until explicit approval.

---

## Detailed cut plans

---

### Step 2 — Lichess branding strings (UI-A through UI-E)

**Why**: These are Lichess product strings that appear in the ChessSRS UI.
They confuse users and misrepresent the product.

**What to remove** (surgical edits, no file deletions):

- `lib/src/view/home/home_tab_screen.dart`
  - Remove `_WelcomeMessageCard` widget render (the "Welcome to the Lichess
    app / not all features available" card shown on first launch).
    The `_WelcomeMessageCard` class and its state can be deleted.
  - Remove the donate (`https://lichess.org/patron`) `FilledButton.tonal`
    block in the welcome screen branch.
  - Remove the "About Lichess" (`https://lichess.org/about`) `FilledButton.tonal`
    block in the welcome screen branch.
  - Remove `_LichessMessageBanner` (the unread Lichess server message banner)
    — this is a Lichess inbox feature that will be removed with C8 anyway;
    safe to remove from the home screen display now.
  - Remove `LichessMessage` widget usage from the welcome branch.
  - Keep `unreadMessagesProvider` watch for now (C8 will clean it up).

- `lib/src/view/more/more_tab_screen.dart`
  - Remove the Android-only `ListSection` containing patron/donate tile and
    "About" tile (lines 184–205).
  - Remove `LichessMessage` widget at the bottom of the More tab list.
  - Keep `AboutScreen` import removal if the tile is the only caller — check
    before deleting.

**Shared dependencies that must remain**: `LichessMessage` widget class in
`widgets/misc.dart` — other callers may exist; remove references not the
widget itself. `AboutScreen` — check if any other caller exists before
deciding whether to delete the screen.

**Risk**: LOW — pure UI text/widget removal, no state or routing changes.

**Tests to update**: `test/app_test.dart` — if it asserts the welcome message
text, update accordingly.

---

### Step 3 — C7: Watch tab

**Why**: TV, tournaments, broadcasts, and streamers are Lichess server content
with no relevance to repertoire training.

**Files — FEATURE-SPECIFIC (delete)**:
- `lib/src/view/watch/` (entire directory)
- `lib/src/model/tv/` (entire directory)
- `lib/src/model/tournament/` (entire directory)
- `lib/src/model/broadcast/` (entire directory)
- `test/view/watch/` (if exists)
- `test/model/tv/`, `test/model/tournament/`, `test/model/broadcast/` (if exist)

**Files — SHARED (edit only)**:
- `lib/src/tab_scaffold.dart` — remove Watch case, reindex More tab
- `lib/src/tab_navigation.dart` — remove `BottomTab.watch` + its globals
- `lib/src/view/home/home_tab_screen.dart` — remove
  `FeaturedTournamentsWidget`, `featuredTournamentsProvider` usage,
  `tournament_list_screen` import, `tournament_providers` import
- `test/app_test.dart` — remove 'Watch' bottom-nav assertion

**Shared dependencies to check before deleting**:
- `model/broadcast/broadcast_preferences.dart` — referenced in `app.dart`
  `_screenSizeBasedInitialization`; remove that call too.
- `model/broadcast/broadcast_service.dart` — started in `app.dart`; remove.
- Tournament model types used in home screen — remove those usages first.

**Risk**: MEDIUM — home screen references tournament widgets; must clean those
before deleting model files.

---

### Step 4 — C6: Puzzles tab

**Why**: Tactics training is an explicit non-goal of ChessSRS.

**Files — FEATURE-SPECIFIC (delete)**:
- `lib/src/view/puzzle/` (entire directory)
- `lib/src/model/puzzle/` (entire directory)
- `test/view/puzzle/` (if exists)
- `test/model/puzzle/` (if exists)

**Files — SHARED (edit only)**:
- `lib/src/tab_scaffold.dart` — remove Puzzles case, reindex remaining tabs
- `lib/src/tab_navigation.dart` — remove `BottomTab.puzzles` + its globals
- `lib/src/view/home/home_tab_screen.dart` — remove any puzzle references
  (home_widgets puzzle entry if present)
- `lib/src/view/more/more_tab_screen.dart` — remove puzzle entry if present
- `lib/src/app_links_service.dart` — remove puzzle deep-link handling
- `test/app_test.dart` — remove 'Puzzles' bottom-nav assertion
- `pubspec.yaml` — check if any puzzle-only packages can be removed

**Risk**: MEDIUM — puzzle tab is a whole tab; check home screen home_widgets
enum for puzzle references.

---

### Step 5 — C11: Over-the-board game & Clock tool — COMPLETED

**Why**: Pass-and-play local two-player chess and standalone physical clock simulator are not relevant to local-first SRS.

**Status**: Completed. Removed `view/over_the_board`, `model/over_the_board`, `over_the_board_game.dart`, `OverTheBoardGameResultDialog`, OTB navigation entries in `play_menu.dart`, `board_editor_screen.dart`, and `analysis_actions.dart`. Removed standalone clock tool `view/clock`, `model/clock/clock_tool_*`, `clock_tool_controller_test.dart`, and More tab entry. All quality gates (`./verify`) passed with 0 warnings.

**Files — FEATURE-SPECIFIC (deleted)**:
- `lib/src/view/over_the_board/` (entire directory)
- `lib/src/model/over_the_board/` (entire directory)
- `lib/src/model/game/over_the_board_game.dart` + generated files
- `lib/src/view/clock/` (entire directory)
- `lib/src/model/clock/clock_tool_*`
- `test/view/over_the_board/`
- `test/model/clock/clock_tool_controller_test.dart`

**Files — SHARED (edited)**:
- `lib/src/view/play/play_menu.dart` — removed OTB entry + import
- `lib/src/view/analysis/analysis_actions.dart` — removed `OverTheBoardScreen.buildRoute()` call + import
- `lib/src/view/board_editor/board_editor_screen.dart` — removed OTB "play from position" action + import
- `lib/src/view/game/game_result_dialog.dart` — removed unused `OverTheBoardGameResultDialog`
- `lib/src/view/more/more_tab_screen.dart` — removed Clock tool entry + import
- `lib/src/model/settings/preferences_storage.dart` — removed `PrefCategory.clockTool`
- `test/model/game/game_test.dart`, `test/view/board_editor/board_editor_screen_test.dart`, `test/view/analysis/analysis_screen_test.dart` — updated tests

**Game clock stays** (`lib/src/model/clock/chess_clock.dart` & `test/model/clock/chess_clock_test.dart` — kept; used by in-game countdown clocks).

---

### Step 6 — C10: Blog / recap / announce

**Why**: Server-pushed content feeds with no relevance to local-first SRS.

**Files — FEATURE-SPECIFIC (delete)**:
- `lib/src/model/blog/` (entire directory — 3 files)
- `lib/src/model/recap/recap_service.dart`
- `lib/src/model/announce/announce_service.dart`
- `lib/src/view/home/blog_carousel.dart`

**Files — SHARED (edit only)**:
- `lib/src/app.dart` — remove `recapServiceProvider.start()` and
  `announceServiceProvider.start()` from `initState`; remove their imports
- `lib/src/view/home/home_tab_screen.dart` — remove `blogCarouselProvider`
  watch, `_BlogCarouselWidget` usage, `HomeEditableWidget.blogCarousel`
  usage, `blog_carousel.dart` import, `blog.dart` + `blog_repository.dart`
  imports
- `lib/src/model/account/home_widgets.dart` — remove `blogCarousel` from
  `HomeEditableWidget` enum and its references

**Risk**: MEDIUM — home_tab_screen has multiple blog reference sites; methodical
line-by-line removal required.

---

### Steps 7–9 — C4 / C5 / C8: Online play, server games, social entries

These are larger cuts with more cross-cutting references. Detailed plans will
be written immediately before execution. Key constraint: **C3 (auth) stays**,
so the auth model and HTTP client infrastructure is preserved.

High-level scope:
- C4: Remove `view/play/` lobby/seek UI; `model/challenge/`; `model/lobby/`
- C5: Remove online game lifecycle from `view/game/` and `model/game/`;
  remove `model/correspondence/`; preserve game-frame board widgets
- C8: Remove navigation entry points to friends/inbox/players from More tab;
  model/social code stays for now

---

### Steps 10–11 — C17 / C18: WebSocket + HTTP repositories

Execute only after C4–C9 are done and confirmed to have no remaining socket
or HTTP consumers outside auth and study-import paths.

---

## What is explicitly NOT cut

- `dartchess` + `chessground` + piece/board assets
- `model/common/` (chess.dart, node.dart, eval, id, uci, perf, etc.)
- `styles/`, `widgets/` reusable set, `db/` sqflite, `model/settings/`

> **Amended by D016:** "not cut" here means these directories are not deleted wholesale; it does not mean
> their *visual* contents (Lichess colours, Material-styled components, Lichess-specific widgets) are frozen.
> The visual identity in `design/docs/` supersedes the Lichess-styled parts of `styles/` and `widgets/`.
> Structural/non-visual code in these directories (layout math, platform adapters unrelated to look) may still
> be kept and reused where it doesn't conflict with the new design.
- l10n pipeline
- `model/auth/` (C3 kept — optional login for study import)
- `view/study/`, `model/study/` (D1 — closest to our review scene)
- `view/analysis/`, `model/analysis/` (C15 grey — shared with study)
- `view/board_editor/`, `model/board_editor/` (C16 kept)
- `model/explorer/`, `view/explorer/` (C14 kept)
- `view/clock/`, `model/clock/` (clock tool kept)
- `network/http.dart` base infra (needed for auth + study import)
- GPL-3.0 LICENSE, COPYING.md, copyright notices — preserved forever

---

## Completed cuts

| Step | Feature | Commit | Date | Tests before → after |
|---|---|---|---|---|
| 1 / C9 | Learn tab + coordinate training | `f74627873` | 2026-09-14 | 1570 → 1564 |
| 2 / UI | Lichess branding (donate, about, LichessMessage, welcome card) | `1af79eab3` | 2026-09-14 | 1564 → 1564 |
| 3 / C7 | Watch tab (TV / tournaments / broadcasts) | `dd996ee74` | 2026-09-15 | — |
| 4 / C6 | Puzzles tab (model/view, nav, deep links, quick action) | `fb4847be2` | 2026-09-15 | 1242 passing, analyze 0, linux build ok |
| 5 / C11 | Over-the-board game & Clock tool | `4d1c4b211` & `1b7e18a03` | 2026-09-14 | — |
| 6 / C10 | Blog / recap / announce (models, services, home carousel) | `156d760fa` | 2026-09-15 | 1242 → 1235 passing, analyze 0, linux build ok |
| 7 / C4 | Online play: lobby / seek / challenges | `c2094c070` | 2026-09-15 | 1235 → 1182 passing, analyze 0, linux build ok |
| 8 / C5 | Server game lifecycle + correspondence | `bc7b4dcc4` | 2026-09-15 | 1182 → 1084 passing, analyze 0, linux build ok |
| 9 / C8 | Social navigation entries from More tab | `790bb99c2` | 2026-09-15 | 1182 passing, analyze 0, linux build ok |
| 12 / Home | Home tab + home widgets/prefs (clean 2-tab shell: Review + More) | `29c3db19e` | 2026-09-16 | 1188 → 1158 passing, analyze 0, linux build ok |
| 13 / C8-Views | Dead social views & models (messages, conversations, friend/player screens) | `b8664182d` | 2026-09-18 | 1267 → 1252 passing, analyze 0, linux build ok |
| 14 / User-Views | Dead leaderboard & online bot screens, models, and providers | `b0ad26284` | 2026-09-18 | 1252 → 1248 passing, analyze 0, linux build ok |
| 15 / C8-Relation | Dead relation repository, following_user model, and follow/block actions | `db6409c31` | 2026-09-24 | 1248 → 1246 passing, analyze 0, linux build ok |
| 16 / C4-Playban | Dead playban dialog, notification model & account service monitoring | `c3e91b183` | 2026-09-24 | 1246 passing, analyze 0, linux build ok |
| 17 / UI-Residue | Dead orphaned widgets, views & assets (UserContextMenu, ServerOutageDisplay, ExpandedSection, SideIndicator, TextBadge, BrightnessNotifier) | `8f0e8f7d3` | 2026-09-24 | 1246 passing, analyze 0, linux build ok |
| 18 / Gestures | Dead Android system gestures exclusion utility & method channel handler | `bd4fa6c97` | 2026-09-24 | 1246 passing, analyze 0, linux build ok |
