# ChessSRS design pass — audit, scene inventory, dependency log

Grounded against `repomix-design-core.xml` (the real `lib/` + `design/` tree), not just the
handoff brief. Root `chesssrs-design-demo.html` is the visual superset; this file is the
paper trail: what's aligned, what changed, what's still open.

## Headline finding: the bottom tab bar is legacy, not a missing scene

`lib/src/tab_navigation.dart`, `tab_scaffold.dart`, and `lib/src/view/more/more_tab_screen.dart`
still implement a two-tab bottom nav (**Review / More**), and `more_tab_screen.dart` is
unmigrated: raw `ListTile`/`Icons.*`, an `AppBarLichessTitle` (lichess.org branding), an
Account section, a **Settings** row, and a **Profile** row.

`design/docs/01-identity.md` already settled this, explicitly:

> Bottom navigation "Review / More" → **None.** A `⋯` button opens the **Library** sheet
> (Import, Explore, Settings, About).
> More tab headed by a `lichess.org` logo and account icon → **Gone. No account, no branding.**

So I did not add a tab bar to the demo — that would contradict the approved identity, not
complete it. `lib/src/view/review/library_sheet.dart` is **already implemented** and already
matches the demo's Library sheet almost verbatim (its own code comment says "replaces
overflow menu and legacy 'More' tab"). The real gap is that the old scaffold hasn't been
torn out yet. Logged as an implementation dependency below, not a design task.

One thing the Library sheet does surface that the old More tab also had: **Account /
Profile**. Nothing in the design docs says what happens to sign-in once the tab bar goes —
that's an open owner question, listed below.

## Scene inventory (updated)

| Scene | Status | Notes |
|---|---|---|
| `review.idle.daily_limit` | **Built** | Demo copy ("Daily limit reached.") intentionally does **not** match the current Flutter string ("Daily Goal Reached!" with an exclamation mark) — see Findings. |
| `review.loading.cold` / `.refresh` | **Built** | Overlay + inline status line, review chrome stays mounted. |
| `review.error.cold` / `.refresh` | **Built** | Cold reuses the import-error page pattern; refresh is an inline status line. |
| `review.correction.multi` (2–4 / 5+) | **Built** | Static scenes with destination rings + a "Prepared moves" list. |
| `review.black.*` | **Built** | Board orientation is now a real per-board flip (`setOrientation`), not a CSS trick; hit-testing and coordinate labels flip with it. |
| `review.notation_hidden.*` | **Built** | Board geometry unaffected; feedback/actions stay. |
| `review.annotations` (mixed / overflow) | **Built** | Neutral `ink2` shapes beneath pieces, "+n study annotations / Show all" disclosure. |
| `review.diagnostics` | **Built, revised this pass** | Brought closer to the real HUD in `review_screen.dart` (`node` id, `Expected`, `D/10`, a "Last: passed · next due in Nd" line) but restyled calm/sentence-case — the **real** HUD is `SRS DIAGNOSTICS` (all-caps) with `Lapse!` (exclamation); that's the same "old tone" issue as the daily-limit string. |
| `import.chooser` | **Rebuilt this pass** | Previously conflated with the first-launch drop-zone screen. The real chooser is `repertoire_import_dialog.dart`: title **"Import repertoire"**, rows **PGN file / Paste PGN text / Lichess study** (each with the real subtitle), plus **Train as**. Now a separate scene from `first`, and Library's "Import PGN" row opens it. |
| `first` (true empty state) | **Aligned** | Reverted the button label back to **"Choose file"** (real copy) — my previous pass had incorrectly renamed it to "Choose a PGN file" to match the brief's prose instead of the shipped string. |
| `export.pgn` | **Revised this pass** | Actions now **Cancel / Copy / Share / Save file** (I'd dropped Share). Toast copy matched to source (`PGN copied to clipboard`, `Shared successfully`, `Saved {name}.pgn`). Still ahead of the real dialog: the generating→ready split and the empty state are proposed, not yet shipped — `export_pgn_dialog.dart` doesn't have a "generating" string today. |
| `acts` (study actions) | **Revised this pass** | Added the real subtitles for Export PGN and Pause/Resume. Sheet title still says the repertoire name in the demo; real code's literal string is `'Actions'` — left as-is (unconfirmed which is intended), logged below. |
| `rename` / `delete` | **Revised this pass** | Field label now "Repertoire name"; delete dialog title now "Delete repertoire?" (matches source). |
| `settings.*` | **Rebuilt this pass** | Replaced the invented 6-page hierarchy with the **real** structure: `srs_settings_screen.dart` is one scrollable page (Review & SRS inline, then Appearance/Board/Sound/Engine/Data groups with drill-in rows only where the real app drills in). Exact copy matched: "Show board annotations" (not "arrows and circles"), Initial ease factor / Interval scaling (shown only for Simple/Ease, mirroring how target retention is FSRS-only), a Local database size row, HTTP/App log rows. The six drill-in subpages (Theme & appearance, Board & pieces, Sound & audio, Chess engine, HTTP logs, App logs) are light placeholders — those inner screens are deep/kept features, not redesigned. |
| Deep Analysis/Explorer/Board Editor internals (`retro_screen`, `server_analysis`, `pgn_games_list_screen`, `engine_gauge`/`engine_lines`, `tablebase_view`, `opening_explorer_settings`, `board_editor_positions/filters`, …) | **Out of scope, confirmed** | All still Material/legacy per the source scan, and all fall under the brief's explicit "do not cut or redesign the engine, Analysis, Opening Explorer, Board Editor… kept features" boundary. Not touched. |

## Findings — old style still live in the real app (for the implementation backlog, not fixed by this demo)

1. **`more_tab_screen.dart` + `tab_scaffold.dart`/`tab_navigation.dart`** — legacy bottom-nav
   shell (Lichess branding, raw Material rows). Superseded by the Library sheet, which is
   already built. Needs removal, not redesign.
2. **`more/import_pgn_screen.dart` vs `review/import_pages.dart`** — two separate import
   entry points exist. The old More tab's "Import PGN" row still opens the legacy
   `import_pgn_screen.dart`; the new Library sheet opens `RepertoireImportDialog` (which
   itself opens the redesigned `import_pages.dart` paste/Lichess flows). Once the More tab
   is removed this resolves itself, but flagging in case anything else still links to the
   old screen.
3. **`review_screen.dart`'s daily-limit copy**: `"Daily Goal Reached!"` — exclamation mark,
   gamified tone, violates the identity doc's own principle 7 ("no exclamation marks"). The
   demo's `"Daily limit reached."` is the intended replacement, not a copy of current prod.
   Same file's `"Adjust Limit"` button (Title Case) should become sentence case.
4. **The live diagnostics HUD** in `review_screen.dart` is `SRS DIAGNOSTICS` (all-caps
   header) and uses `"Last: Lapse!"` on a miss. Same tone issue as #3. The demo's
   `diag`/`diagHTML()` is the calmer target; content (node id, expected move, R/S/D,
   reps/lapses, last result) is preserved, formatting is not.
5. **Export dialog empty-state mismatch**: today, `study_actions_sheet.dart` blocks the
   Export action *before* opening the dialog with a toast (`'No moves to export in this
   study'`) when a repertoire has 0 positions. The design contract asks for an in-dialog
   empty state instead. Pick one pattern — logged as an owner decision below.

## Owner decisions still open (unchanged from the brief, plus one new one)

- Account / Profile: with the More tab gone, where does sign-in/profile live? Not addressed
  by any design doc so far.
- Export empty state: toast-before-open (current) vs. in-dialog empty state (brief's ask) —
  pick one; the demo currently shows the in-dialog version at `export.pgn` → *no moves*.
- Study-actions sheet header: repertoire name (demo) vs. literal `"Actions"` (current
  Flutter string) — which is the real intent?
- Everything listed as open in the original handoff (daily-limit real-due-behind-cap,
  black-orientation semantics, settings Account/Language scope, tablet composition,
  annotation color/shape, empty-state copy) still stands; nothing here resolves those.

## Not done this pass (explicitly deferred, not silently dropped)

- Real screenshot capture at the responsive matrix (390×844 / 820×1180 / 1280×800, both
  themes, 130%/150% text, reduced motion). I have no headless-browser tool in this
  environment — the demo has toolbar controls for every one of those axes (Tablet device,
  Motion, Text size) so a Playwright/Puppeteer pass against the published file can generate
  the matrix mechanically; happy to write that script if useful.
- Deep redesign of Theme & appearance / Board & pieces / Sound & audio / Chess engine / logs
  sub-screens — placeholders only, consistent with the "kept feature" boundary.
- Token-delta document — no tokens were changed this pass (only new components: `.diag`,
  `.prep`, `.ring`, `.shp-*`, `.quota`, `.load-wrap`, tablet overrides), so there's nothing
  to diff yet.
