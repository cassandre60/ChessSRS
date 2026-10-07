# Phone-feedback batch 2 (triaged 2026-09-29, NOT built)

Owner desktop testing follow-up. Each item has file pointers and a proposed
shape. None implemented yet — promote items to build tasks in the stated order.

## 1. Remove `…` > Analysis entirely
- `lib/src/view/review/library_sheet.dart` (Explore group → Analysis row).
- Deleting the row orphans `lib/src/view/analysis/analysis_hub_screen.dart`
  (Library is its sole caller) plus `test/view/analysis/analysis_hub_screen_test.dart`
  and the Explore-study flow from #82.
- Consequence to confirm: standalone Board editor / Opening explorer / Analysis
  board lose every entry point; only per-chapter Explore remains.

## 2. Scope > study actions → single Analyze into the study scene
- `lib/src/view/review/review_scope_drawer.dart:739-782` (`StudyActionsSheet`):
  delete Chapters / Analyze / Practice rows, keep one Analyze (+ Export, Pause,
  Rename, Delete).
- The target "study scene" (`lib/src/view/study/study_screen.dart`,
  `study_controller.dart:39-108`) is server-bound: `StudyOptions` takes a
  lichess `StudyId`, controller opens sockets/chat/likes/gamebook. Our studies
  are local SQLite rows with string ids.
- Options: (a) adapt the controller to a local-study source — LARGE (offline
  tree loading, guard every server feature); (b) keep the analysis-board viewer
  and add chapter navigation to it — MEDIUM, no server coupling. Owner picks.

## 3. Settings regrouping
- `lib/src/view/settings/srs_settings_screen.dart`, one page, 7 sections.
- Split section 1 (review display toggles vs scheduling); move scheduling half
  behind a dedicated SRS screen.
- Merge sections 2+3 into one Appearance group (see #4).
- Sections 4–7 (Sound, Engine, Data, About) stay as-is.

## 4. "Theme & appearance" vs "Board & pieces" duplicates — confirmed
- `srs_settings_screen.dart:283-311` → `ThemeSettingsScreen`, whose body
  (`theme_settings_screen.dart:101-114`) is Board → `BoardChoiceScreen` +
  Piece set → `PieceSetScreen`.
- "Board & pieces" row → `BoardSettingsScreen` (`board_settings_screen.dart:107-120`),
  the same two destinations. Delete one label, redirect; owner picks survivor.

## 5. Theme preview stale (ThemeSettingsScreen, not the theme menu)
- `theme_settings_screen.dart:254-263` (`_BoardPreview`) calls
  `toBoardSettings(Variant.standard)` WITHOUT `srsColors`, so Diagram/System/Brown
  preview as opaque chessground brown while the app draws the SRS hatched scheme.
- Fix direction: read `context.srs` in `_BoardPreview.build` and pass through.
- Piece-set previews are innocent (live thumbnail + real piece art + filters).
