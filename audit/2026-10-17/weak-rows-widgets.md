# Weak rows — w2-widgets/view (verbatim digest; grade 3 rows counted per file in coverage.md)

Grade 0: none. Grade 1 verbatim:

- widgets/adaptive_action_sheet_test.dart:66 — "the sheet surface is the same on Android" — bare SrsSheetSurface findsOneWidget, nothing else.
- widgets/rich_link_text_test.dart:111 — "detects multiple URLs" — hasLength(2) only; neither URL's content checked.
- rich_link_text:117 — "detects URL at end of text" — any(isA UrlElement) pure existence.
- rich_link_text:122 — "detects URL at start" — type-only assert on the first element.
- rich_link_text:169 — "returns TextSpan with children" — children>1 only; near-unfailable.
- rich_link_text:229 — "renders multiple elements" — link rendered as plain text still passes.
- rich_link_text:290 — "applies custom style and linkStyle" — `style isNotNull` satisfied by the default style; custom style inert undetected.
- view/offline_computer/offline_computer_game_screen:390 — "Menu button opens action sheet" — one 'New game' findsWidgets, nothing else.
- offline_computer_game_screen:457 — "Stockfish player info displays correctly" — Image findsWidgets + textContaining only.
- offline_computer_game_screen:913 — "Hint button shows its label" — pure widgetWithText existence.
- offline_computer_game_screen:920 — "Hint button disabled while loading" — body inside if(isLoadingHint): vacuous pass.
- offline_computer_game_screen:2044 — "switch is shown in new game dialog" — two label existence asserts only.
- view/study/study_screen:897 — "Does not display server analysis tab" — single negative findsNothing; fails only if 'Summary' re-added.
- view/user/user_screen:21 — "should see activity and recent games" — 'John Doe'+'ACTIVITY' on a fixture with ~10 games and 7 activity entries.

Grade 2, one line each (file:line — title — the mutation it would miss):

- adaptive_action_sheet:56 — iOS gets a Diagram sheet, not a Cupertino one — misses wrong/missing action rows under the surface-type swap.
- adaptive_action_sheet:112 — a rich label is rendered, not flattened — swatch WidgetSpan dropped while text kept passes.
- adaptive_action_sheet:154 — the title renders above the rows — ordering never asserted; title below row list passes.
- adaptive_choice_picker:140 — opens an SrsDialog, not a Material AlertDialog — dialog content/labels unasserted.
- adaptive_choice_picker:147 — marks exactly the selected choice — count-only; wrong row marked passes.
- adaptive_choice_picker:157 — renders a rich label with its swatch intact — swatch WidgetSpan loss passes.
- adaptive_choice_picker:214 — iOS gets the Diagram dialog, not a Cupertino sheet — type-presence only.
- adaptive_choice_picker:293 — iOS gets an SrsDialog, not an adaptive Material dialog — type-presence only.
- adaptive_choice_picker:301 — marks every selected choice, not only the first — count-only initial marker; wrong row passes.
- widgets/feedback:11 — shows loading indicator when lagRating is 0 — spinner color/size/label unchecked.
- feedback:20 — does not show loading when inactive — type-level only.
- feedback:48 — respects the size parameter — first-SizedBox plumbing; indicator content unchecked.
- feedback:62 — uses default size of 20.0 — same plumbing-only shape.
- feedback:70 — throws assertion for lagRating below 0 — bound-only.
- feedback:74 — throws assertion for lagRating above 4 — bound-only.
- move_times_chart:75 — has its own tab for a game played with a clock — chart painted content unasserted.
- move_times_chart:89 — no tab for a game without clocks — negative-only; blank screen passes.
- rich_link_text:8 — empty list for empty string — only that branch.
- rich_link_text:45 — removes trailing period from URL — isNot(endsWith '.') never pins the URL.
- rich_link_text:127 — no links returns single TextElement — no text assert.
- rich_link_text:133 — custom linkifiers only — type presence/absence only.
- rich_link_text:162 — LinkifyElement originText defaults to text — single-field default.
- rich_link_text:211 — no recognizer on plain elements — non-TextSpan children bypass the loop.
- rich_link_text:224 — renders plain text — find.text existence only.
- rich_link_text:240 — onOpen wired into TextSpan recognizer — recognizer present but never fired; wrong link params pass.
- widgets/user:9 — displays fallback name when user is null — only the null branch; user-set branch untested.
- widgets/user:21 — displays Anonymous when neither available — single-branch shape.
- game_layout:313 — Crazyhouse pockets and drop moves — black-drop's expected non-recording never asserted.
- view/board_editor/board_editor_screen:153 — Side to play and castling rights — controller-driven; unwired castling chip passes.
- board_editor_screen:205 — Castling rights ignored when rook missing — controller-level loadFen; UI wiring unchecked.
- board_editor_screen:224 — support chess960 castling rights — setVariant in code, not through UI.
- board_editor_screen:247 — Castling rights ignored when king off backrank — controller-level row.
- board_editor_screen:336 — en passant options — controller state only; how options render untested.
- board_editor_screen:693 — Continue against computer — preselection asserted by label only; wrong underlying value passes.
- board_editor_screen:833 — segmented swaps openings/endgames lists — list-difference + selected!=null; wrong list with different label passes.
- board_editor_palette_layout:145 — every tool is reachable — tap's effect unasserted; visible-but-dead tool passes.
- board_editor_palette_layout:226 (×3) — the surface really is WxH — harness sanity; beyond fill-surface no widget mutation caught.
- offline_computer_game_screen:78 — New game dialog shown with all options — labels only, tile wiring untested.
- offline_computer_game_screen:109 — Can start with default settings — existence; '4' findsWidgets loose.
- offline_computer_game_screen:279 — Engine responds after player move — spinner-absence + count only.
- offline_computer_game_screen:319 — Resign shows confirmation dialog — dialog labels; wiring left to :342.
- offline_computer_game_screen:373 — New game option opens bottom sheet — sheet labels only.
- offline_computer_game_screen:550 — Can start with a different level — old-label count only; reached level unasserted.
- offline_computer_game_screen:632 — Casual switch shown — label + switch counts only.
- offline_computer_game_screen:963 — Hint shows circle when pressed — conditional-if guard; vacuous when hints empty.
- offline_computer_game_screen:1012 — cycles through hints — conditional-if guard.
- offline_computer_game_screen:1128 — Hints cleared on move — conditional-if guard.
- offline_computer_game_screen:1179 — Hint button highlighted — no highlight asserted at all despite the name; guarded.
- offline_computer_game_screen:1256 — untimed unless a clock asked — negative-only existence.
- offline_computer_game_screen:1406 — mini board with initialFen — preview existence; its position never checked.
- offline_computer_game_screen:1431 — no mini board without initialFen — negative-only.
- offline_computer_game_screen:1672 — Side defaults to Next to play — label existence only.
- offline_computer_game_screen:1761 — Next to play absent without initialFen — negatives only.
- offline_computer_game_screen:1820 — goodMove shows check_circle icon — icon-type branch only.
- offline_computer_game_screen:1825 — notBest shows info icon — icon-type branch only.
- offline_computer_game_screen:1830 — inaccuracy shows help icon — icon-type branch only.
- offline_computer_game_screen:1835 — mistake shows error icon — icon-type branch only.
- offline_computer_game_screen:1840 — blunder shows cancel icon — icon-type branch only.
- offline_computer_game_screen:1845 — book move shows menu_book icon — icon-type branch only.
- offline_computer_game_screen:1852 — goodMove label — exact label per branch only.
- offline_computer_game_screen:1857 — notBest label — exact label per branch only.
- offline_computer_game_screen:1862 — Inaccuracy label — exact label only.
- offline_computer_game_screen:1867 — Mistake label — exact label only.
- offline_computer_game_screen:1872 — Blunder label — exact label only.
- offline_computer_game_screen:1877 — book move label — exact label only.
- offline_computer_game_screen:1927 — bestMove shown for non-best — 'Best was'+'e5' substring; nearby e5 could satisfy.
- offline_computer_game_screen:1939 — alternativeGoodMove shown — 'Another was'+'d4' substring.
- offline_computer_game_screen:1951 — no suggestion for plain goodMove — negatives only.
- offline_computer_game_screen:1973 — evalAfter displayed — '+0.3' existence only.
- offline_computer_game_screen:2005 — player's turn shows no verdict icon — negatives only.
- offline_computer_game_screen:2065 — practice title shown — title branch only.
- view/explorer/explorer_view:48 — shows opening explorer (initial) — routing type-presence; rows unasserted.
- explorer_view:76 — shows opening explorer (>8 pieces) — same routing shape.
- explorer_view:193 — tablebase for 8-piece endgame — type-routing only.
- explorer_view:290 — tablebase when signed out — type-routing only.
- explorer_view:379 (×2) — TablebaseView letter/symbol notation — letter branch expects null fontFamily; stray figurine passes.
- study_screen:930 — menu opens a sheet of share rows — no row tapped; unwired share/export callbacks pass.
- study_opening:90 — opening set on mainline nav — asserts controller state, not the on-screen opening header.
- study_opening:120 — ancestor opening used — same state-only shape.
- create_study_chapter_bottom_sheet:100 — Create chapter from FEN — payload asserts moves.isEmpty only; dropped FEN header passes.
- user_screen:47 — Challenge hidden when canChallenge null — no companion test that Challenge shows when allowed.
- app_log_settings_screen:24 — renders empty state — labels only; chip wiring deferred.
- http_log_screen:22 — renders empty state — three labels only.
- import_pgn_screen:69 — valid single-game PGN navigates — only source-screen-gone; wrong-game navigation passes.

TOP5 (walker): user_screen:21 (2 strings guard a rich profile), offline:920 (conditional-if vacuous pass; same class at 963/1012/1128/1179), rich_link_text:290 (custom style inert), study_screen:897 (negative-only), offline:457 (loose existence rows).

MERGE CANDIDATES (walker): offline_computer_game_screen:1820–1923 (12 icon/label + 5 exact-color tests → one verdict→(icon,label,color) table; 17 bodies → ~6 rows), board_editor_screen:535–661 FEN dialog sextet + 153–262 castling quartet (two load→assert scaffold tables), explorer_view:47–105 + 193–318 (six routing tests → table), import_pgn_screen:99–159/218–257 + 161–190/194–216 (clipboard-vs-file × single-vs-multi matrix), create_study_chapter_bottom_sheet:26–180 + adaptive_choice_picker:16–105 (content-source tables).
