# Weak rows — w2-design/perf/platform (verbatim digest; grade 3 rows counted per file in coverage.md)

Walker scope: the design suite files not already covered in wave 1, view/settings leftovers, the three perf files, and the platform files. srs_settings_screen_test (wave 1) and explorer_view (another walker) excluded per instruction. A folio_tokens row was standardized to grade 2 (header said 3, body said 2).

## Grade 1 verbatim

- test/design/one_look_test.dart:117 — "the reachable list still points at files that exist" — existence-only; cannot catch its own admitted failure mode (a shipped screen missing from the manual reachable list).
- test/design/srs_page_head_test.dart:37 — "hides trailing when absent and disables without onBack" — body asserts only label/type presence; the trailing-hidden and back-disabled claims are unasserted (verified by the author previously; in this walk too).
- test/view/settings/legacy_settings_screen_test.dart:23 — "the legacy Material settings screen stays deleted" — pure file-existence pin; a resurrected copy at another path passes (right mechanism for a deletion guard, still thin).
- test/perf/driver_overhead_test.dart:55 — "separate SQL execution from FFI driver overhead" — `<2000ms` vs ~16–36 ms measured; skips without CHESS_SRS_PERF_DB; the printed table is the deliverable.
- test/perf/due_summary_attribution_test.dart:53 — "attribute the due-summary cost to SQL versus row mapping" — `<2000ms` vs ~28 ms; print-only, no regression assertion a plausible refactor could trip.
- test/perf/real_library_session_cost_test.dart:67 — "session start against a real library" — `<2000ms` vs ~37–39 ms; print-only, skips everywhere CI runs.

## Grade 2, one line each (file:line — title — the mutation it would miss)

- design/design_primitives_test.dart:195 — a leading widget sits left of the label — any other row-layout mutation (row padding, trailing slot, overflow).
- design/folio_tokens_test.dart:40 — it is actually a second palette, not Diagram renamed — drift in any field beyond ground/squareDark (ink, ink2, surface2...).
- folio_tokens:54 — accents are shared with Diagram — the same wrong accent edited into BOTH palettes at once (no absolute value asserted).
- one_look:76 — a reachable screen renders no Cupertino widget — a Cupertino look on any shipped screen absent from the manually maintained reachable list.
- practice_exit:69 — the due count is hidden while practising — practice-only content other than 'due' text, or a count format no longer matching textContaining('due').
- practice_exit:88 — the taller target does not overflow the top bar row — silent squash/row shift that does not throw an overflow exception.
- review_line_reserve:59 — history on and off share the same reserve geometry — geometry drift outside the min-height number (gap size, slot placement).
- srs_accent:59 — defaults to the default accent — barely exercises storage mechanics; only a literally wrong default value trips it.
- srs_dialog:56 — sets the title at 20px weight 600 — title colour/weight/placement, and any non-typographic title mutation.
- srs_dialog:64 — sets the body at 15px — body colour/weight and vertical placement (pinned elsewhere, not here).
- srs_notation_line:28 — the narrow line is headline-sized — lineSize(wide: true) drift; only the narrow value is pinned.
- srs_page_head:15 — renders destination label, fires back, shows trailing — back affordance visual identity and trailing placement (findsWidgets CustomPaint is filler).
- theme_bridge:17 — filled button is ink on ground (light) — hover/pressed/disabled states and real widget render; style-resolution pin only.
- theme_bridge:17 — filled button is ink on ground (dark) — same for dark.
- theme_bridge:27 — selected segmented item is ink on ground (light) — unselected/other states uncovered.
- theme_bridge:27 — selected segmented item is ink on ground (dark) — same for dark.
- theme_bridge:33 — selected switch track is ink (light) — thumb default states and non-selected tracks uncovered.
- theme_bridge:33 — selected switch track is ink (dark) — same for dark.
- top_bar_colour_squares:52 — both squares are offered — square colour/decoration and behaviour when activeSide is null.
- top_bar_narrow:70 — the bar fits the narrowest permitted window without clipping — silent clipping/squash without a thrown exception.
- top_bar_narrow:76 — the bar still fits when the due count is widest — same takeException-only weakness at 4 digits.
- legacy_settings:34 — nothing references the deleted screen — non-bare references (aliased/new-name survivors) and any non-.dart mention; regex can't see them.
- platform/ios_share_extension_test.dart:40 — the app exports a PGN type — correctness of the type's conformance/other metadata; presence-only.
- platform/oauth_callback_identity_test.dart:50 — the redirect the app asks for is the app-owned scheme — host correctness beyond mere non-emptiness; cushions real bugs behind tests 59/69.
- view/engine/engine_button_test.dart:52 — Engine button is not displayed if computer analysis is not allowed — what replaces the button and gating for other disable paths.
- engine_button:99 — Long pressing the engine button opens the engine popup — popup content (one loose textContaining('Stockfish'); wrong rows/labels pass).

## PERF NOTES

The three ceilings never bind, by construction: all assert `<2000ms` against costs the same files document at ~16–36 ms, ~28 ms and ~37–39 ms, and all three `markTestSkipped` without `CHESS_SRS_PERF_DB`, so CI sees skips only. Legitimate measurement harnesses; zero regression-guard value; no screenshot comparisons anywhere in the three files (pure timing prints).

## Cross-walker disagreement, resolved

- srs_toast_test.dart — this walker's digest recorded the file 6/6 grade 3, but the tone loop at :138 was verified grade 0 by the author (read in wave 1 and re-sed'd for this chapter, lines 137–150): it iterates `SnackBarType.values` yet never passes `type:` to the widget, so the title's observable ("every tone renders identically") is unreachable — a mutant that renders error/success/info differently still passes. The wave-1 chapter's row governs; the walker's histogram is treated as wrong on that row. The rest of the file's tests (timeout, non-stacking, Navigator-context insert) are strong as recorded.

## Strengthened / confirmed by the full walk (for the chapter cross-reference)
- Absent names checked and confirmed not to exist: srs_screen, adaptive_reflow, typography, srs_button, srs_input_fields, srs_card, srs_backdrop, srs_top_bar, mission, legacy, density (design); board_theme_picker, board_preview, sounds_settings_screen, design_screen, server_settings, board_grouping (view/settings); android_widget, push_notifications (platform); engine_popup, engine_screen (view/engine).
