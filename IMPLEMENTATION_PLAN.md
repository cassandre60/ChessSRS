# Implementation Plan & Phase Status

> Reset plan (post Lichess-Mobile foundation decision). The previous task
> graph (T1–T17, standalone implementation) is archived at git tag
> `legacy/pre-reset` and is closed.

## Phase strategy

```text
Phase 0 — Repository archaeology          (documentation/reset — no product code)
Phase 1 — Lichess Mobile foundation        (fork runs, identity, staged cuts)
Phase 2 — Minimal product vertical slice   (study → position → review → answer
                                             → feedback → local persistence)
Phase 3 — Beta                            (owner uses it; cluster feedback)
Phase 4 — Listudy integration             (training/study-tree behavior)
Phase 5 — chessrs integration              (SRS/review queue behavior)
Phase 6 — Refinement                      (polish, perf, remaining cuts)
```

Development is beta-first: the owner is the beta tester. Nothing gold-plates
before the core review loop is in the owner's hands.

---

## Phase 0 — Repository archaeology (done)

- [x] Inspect old repository (docs + lib + tests); classify documentation
- [x] Inspect Lichess Mobile architecture (model/view/network/db, CLAUDE.md,
      study subsystem, chessground/dartchess)
- [x] Inspect Listudy (study.js training loop, tree_utils, chapter/FEN model)
- [x] Inspect chessrs (Move entity, SpacedRepetitionService, practice queue UX)
- [x] Legacy checkpoint: commit WIP, tag `legacy/pre-reset`, branch `legacy`
- [x] `CUT_PROPOSALS.md` (Lichess trim map + owner sign-off list)
- [x] `docs/INTEGRATION_MAP.md` (Listudy/chessrs extraction + license rules)
- [x] Rewrite `ARCHITECTURE.md`, `AGENTS.md`, `IMPLEMENTATION_PLAN.md`
- [x] Handoff report delivered (A–I)

## Phase 1 — Lichess Mobile foundation

- [x] **F1: Hard reset of working tree** — remove old `lib/`, `test/`,
      `pubspec.*`, platform dirs, `start.sh`; copy Lichess Mobile source
      (LICENSE + COPYING.md preserved). No feature removal.
- [x] **F2: Tooling baseline** — FVM pinned to Flutter 3.47.3 (upstream
      requirement), `pub get`, `build_runner build` (197 outputs), `./verify`
      adapted. Gate: verify green.
- [x] **F3: Build & launch** — Linux desktop launch had 11 startup errors
      (Firebase/libsecret/quick_actions/home_widget/sound guards missing on
      desktop targets); fixed fail-soft. Final: **zero startup errors**,
      analyze 0 issues, tests 1570/1570, home tab renders with board +
      navigation. Evidence: `docs/phase1_runtime_evidence.png` (2026-09-14).
- [x] **F4: App identity** — renamed to **ChessSRS**: Dart package
      `chess_srs` (566 files), Linux binary/GTK id `org.chesssrs.chess_srs`,
      Android namespace/applicationId `org.chesssrs.app` (Kotlin moved),
      iOS bundle ids/display name/app groups, user agent, README with GPL
      fork attribution. Gate: analyze 0, tests 1570/1570, Linux launch zero
      startup errors. Evidence: `docs/phase1_f4_identity_evidence.png`.
- [x] **F-github: Repository setup** — GitHub fork of `lichess-org/mobile`
      named `ChessSRS`; `main` grafted onto both the old
      `chess-repertoire-srs` history (first-parent) and lichess upstream
      (merge), so the repo descends from both; old repo pushed fast-forward;
      `legacy` branch + `legacy/pre-reset` tag pushed.
- [x] **F5+: Staged cuts** — executed `CUT_PROPOSALS.md` execution order
      (one subsystem per commit; verify + launch after each). Owner has
      reviewed and approved/rejected each cut — see `CUT_PROPOSALS.md`
      §Owner decisions for the full record. Final ordered status:
      1. `[x]` C9  — Learn tab + coordinate training  *(done: f74627873)*
      2. `[x]` UI  — Lichess branding (donate, about, LichessMessage, welcome card) *(done: 1af79eab3 & 72c85e67f)*
      3. `[x]` C11 — Over-the-board game and standalone clock tool *(done: 4d1c4b211 & 1b7e18a03)*
      4. `[x]` C7  — Watch tab (TV / tournaments / broadcasts) *(done: dd996ee74)*
      5. `[x]` C6  — Puzzles tab *(done: fb4847be2)*
      6. `[x]` C10 — Blog / recap / announce (home carousels + model) *(done: 156d760fa)*
      7. `[x]` C4  — Online play: lobby / seek / challenges *(done: c2094c070)*
      8. `[x]` C5  — Server game lifecycle + correspondence *(done: bc7b4dcc4)*
      9. `[x]` C8  — Social cleanup: More tab entries, Home friends carousel, and message service poller *(done)*
      10. `[K]` C17 — WebSocket *(KEPT by owner decision for study sync & cloud eval)*
      11. `[K]` C18 — HTTP network & core repositories *(KEPT for auth, study import, explorer, tablebase)*
      12. `[x]` Tab reduction → Clean 2-tab shell: Review (primary) + More/Settings *(done)*
      Grey/undecided (untouched): C1, C2, C12, C13, C15.
      Kept by owner decision: C3, C14, C16, C17, C18.
- [x] **F-end: Foundation stable** — a clean, coherent, Lichess-derived
      application shell with Home and More tabs. 0 analyzer warnings,
      1,084 passing tests, desktop runtime verified. Ready for Phase 2.

## Phase 2 — Minimal product vertical slice

- [x] **V1: Domain module** — pure-Dart domain (Study, Chapter, repertoire
      tree, RepertoireDecision, ReviewState, Scheduler + SimpleScheduler,
      Clock) with unit tests. Contract-first; no UI. *(done: 9f879c5e0)*
- [x] **V2: Import pipeline** — PGN file → dartchess `PgnParser` →
      normalized Study/Chapter/tree (RAVs preserved, FEN headers honored);
      structured error reporting. Tests: legacy contract references
      translated (variation preservation, multi-chapter). *(done: f65aa3184)*
- [x] **V3: Local persistence** — sqflite store for studies/decisions/review
      states; incremental writes. Tests: durability across restart. *(done: 2c44df649)*
- [x] **V4: Review session engine** — due selection, move validation against
      repertoire, auto-traversal of non-due material, opponent auto-reply,
      feedback state machine. Deterministic Clock tests. *(done: 1aeb1bbf2)*
- [x] **V5: Review scene UI** — board-dominant Review screen on chessground,
      oriented to repertoire side, quiet correct/incorrect feedback,
      due-count indicator, scope drawer (all/one study). First launch with
      no studies → import action. *(done: b940ffbf8)*
- [x] **V6: Vertical slice gate** — full loop proven at runtime on device:
      import real PGN → review → correct/incorrect → state persisted across
      restart. Runtime validation (Linux desktop build & launch) + automated
      end-to-end vertical slice gate test. **Beta-ready.** *(done: 00160c1c5)*

## Phase 3 — Beta & Owner Feedback Refinements

- [x] Deliver initial vertical slice build to owner for daily use. *(done: 2026-09-16)*
- [x] Clustered beta feedback audit 1: move pacing, unblocking reguess on error, quiet positive feedback, study explore mode, Home tab removal. *(done: b313f61ce & 29c3db19e)*
- [x] **B1: Immediate Import Transition & Move Comment Spoiler Prevention**
      1. Immediate scope transition: upon successful PGN import, automatically switch active `ReviewScope` to the newly imported study.
      2. Move comments strictly hidden during active recall prompt to prevent move spoilers.
      3. Move comments revealed post-guess (on success or lapse) with multiline wrapped text. *(done: 763a50181)*
- [x] **B2: Active Review Pool Toggle (Deck Muting / Study Suspension)**
      1. Persistence update: `isActive` boolean (default `true`) on `Study` / `srs_study`.
      2. `ReviewScope.all()` and total due count query only active studies.
      3. Quick toggle switch next to each study in `ReviewScopeDrawer`.
      4. Inactive studies remain fully accessible for individual study review, explore mode, and cram mode. *(done: 4ee5a030f)*
- [x] **B3: Pre-Match Rehearsal / Cram Mode (Custom Review)**
      1. `ReviewMode` parameter on session (`srs` vs `practice`).
      2. In `practice` mode, tests moves on the board without updating `ReviewState` or logging `ReviewEvent` (zero SRS writes/interval corruption).
      3. Entry points: "Rehearse Moves" on "All Caught Up" screen and in study drawer options. *(done: 4d9bd9762)*
- [x] **B4: Automatic Opening Classification & Cross-Study Opening Hubs**
      1. Automatic opening name & ECO tag derivation from PGN headers or position FEN.
      2. `ReviewScope.opening(String name)` virtual scope aggregating decisions across studies.
      3. Opening Hub section in `ReviewScopeDrawer`. *(done: eebb20632)*
- [x] **B5: Smooth Study Management & Native Study Analysis (Option A)**
      1. Eliminate full-screen refresh and UI wipeout on study suspension and rename via optimistic in-memory updates.
      2. Batched due-count computation (`getDueSummary` and `getChapterOpenings`) preventing recursive JSON tree parsing loops during count queries.
      3. Native study analysis: single-chapter studies route directly to `AnalysisScreen`, multi-chapter studies open `StudyChaptersScreen`.
      4. `AnalysisScreen` displays study name and chapter name from PGN headers. *(done: 2026-09-17)*
- [x] **B6: Opponent Pre-Move Animation on Line Transitions & Settings Toggle**
      1. Domain: `parentFen` and `incomingMove` tracked on `ReviewPrompt` via parent node indexing in `ReviewSession`.
      2. Preferences: `animateOpponentPreMove` toggle in `StudyPrefs` and `SettingsScreen`.
      3. UX: When transitioning to a new variation, at session start, or on skip, the board loads the parent position and smoothly animates the opponent's incoming move with sound and square highlights before prompting the user's recall. *(done: 2026-09-17)*

## Phase 4 — Listudy integration (isolated modules)

- [x] **L1: Due-Aware & Weighted-Random Opponent Reply Selection (Listudy Semantics)**
      1. Repertoire branching: opponent variation selection inspects subtrees for due decisions.
      2. Branches containing due cards are prioritized so drills dynamically guide the player to due material rather than always playing `.first`.
      3. Multiple due branches are selected using weighted randomness proportional to due move density, preventing repetition across sessions.
      4. Fallback in Practice Mode weights by subtree size so all variations get proportionate practice.
      5. Full deterministic replay in tests via injectable `Random`. Documented in `docs/review.md`. *(done: 2026-09-17)*
- [x] **L2: PGN Visual Shapes (`[%cal ...]` & `[%csl ...]`) Post-Guess & Settings Toggle**
      1. Zero-spoiler invariant: commentary shapes (arrows and circle highlights) are strictly hidden during active recall.
      2. Post-guess reveal: on correct answer or lapse, PGN shapes from study comments are rendered directly onto the Chessground board.
      3. Clean text: `PgnComment.fromPgn` strips raw `[%cal ...]` and `[%csl ...]` tags from displayed text descriptions.
      4. Distraction-free toggle: "Show board arrows & shapes" switch added in `SettingsScreen` backed by `StudyPrefs.showAnnotations`. *(done: 2026-09-17)*
- [x] **L3: Castling Normalization, Move Pacing, Board Annotations & Chapter Scoping**
      1. Castling normalization: `RepertoireMove.matches` and `ReviewSession` equivalence between standard UCI (`e1g1`, `e1c1`, `e8g8`, `e8c8`) and king-takes-rook (`e1h1`, `e1a1`, `e8h8`, `e8a8`). Playing O-O on the board is accepted cleanly.
      2. Move pacing: added 400ms pause when completing the final move of a line so user sees their piece land and highlight on the board before the line transitions.
      3. Board annotations & shapes: extracted shapes from both prompt position comments and revealed move comments post-guess, displaying author circles and arrows with proper colors.
      4. Chapter scoping: support chapter-level review scope (`ReviewScope.chapter`) from `StudyChaptersScreen` and the drawer's Chapters action sheet, letting users isolate and train individual chapters without mixing other lines. *(done: 2026-09-17)*
- [x] **L4: Move Explanation Pause & Quick Annotations Toggle**
      1. Explanation pause: when move comments or board annotations exist, auto-advancement pauses post-guess so the user can study arrows and read explanations without rushing.
      2. Advance controls: tactile advancement via a prominent "Continue" button or tapping anywhere on the board overlay.
      3. Quick toggle: instant visibility toggle in the `ReviewScreen` AppBar allowing immediate hiding/showing of annotations on the fly. *(done: 2026-09-18)*
- [x] **L5: Chapter & Study Training Progress Metrics (`tree_progress`)**
      1. Domain entity: `RepertoireProgress` pure value type tracking total scheduled decisions, learned decisions (repetition count > 0), due count, and mastery percentage calculations.
      2. Batched zero-overhead computation: single-pass in-memory aggregation inside `ReviewService.getDueSummary` and `ReviewController` without N+1 queries.
      3. UI visibility:
         - `ReviewScopeDrawer`: displays learned/total counts and percentage per study and for All Studies.
         - `StudyChaptersScreen`: displays chapter learned/total moves, percentage, and due status.
         - `ReviewScreen`: All Caught Up state displays mastered positions count and linear progress bar. *(done: 2026-09-18)*
- [x] **L6: PGN Hash Fingerprinting & Duplicate Import Detection (`tree_hash`)**
      1. Canonical hashing: SHA-256 fingerprinting utility `computePgnHash` attached to `Study.pgnHash` on import.
      2. Persistence migration (v9): added `pgnHash TEXT` column and index on `srs_study` table with SQLite schema migration and `getStudyByPgnHash` lookup.
      3. Import flow & UI: `ReviewController.importPgnText` checks for duplicate PGN hashes, avoiding duplicate studies/decisions, switching directly to the existing study, and displaying informational feedback in `RepertoireImportDialog`. *(done: 2026-09-18)*

Per `docs/INTEGRATION_MAP.md`: remaining training-loop semantics (sibling reset on
error, weighted-random opponent replies), chapter/FEN behaviors, tree caching
by PGN hash. Optional where flagged (hints, arrows, comments) — only with
beta-feedback justification.

## Phase 5 — chessrs integration (isolated modules)

- [x] **S1: Parametric Ease/Scaling Scheduler (`EaseScalingScheduler`)**
      1. Domain contract: `EaseScalingScheduler` implementing `Scheduler`, adapted from chessrs `SpacedRepetitionService` (`ease × scaling^n`).
      2. Configurable factors: initial interval (1d), ease multiplier (default 2.5x), and geometric growth rate scaling (default 1.5x) with lapse recovery and maximum interval clamping.
      3. User preferences & settings: `SchedulerType` picker in `SettingsScreen` backed by `StudyPrefs`, exposing ease and scaling factor controls when parametric scheduler is active.
      4. Dynamic engine binding: `ReviewService.schedulerProvider` automatically provisions the selected scheduling algorithm. *(done: 2026-09-18)*
- [x] **S2: Targeted Scope Loading & Queue Prefetch Buffer (`queue_prefetch`)**
      1. Targeted persistence queries: `ReviewService.startSession` queries only the chapters, decisions, and review states needed for the active scope, eliminating full-database JSON tree deserialization loops on session start.
      2. Chunked review state lookup: `StudyRepository.getReviewStatesByDecisions` retrieves states exclusively for active decisions with 400-item SQLite chunking.
      3. Queue prefetch buffer: `ReviewSession` buffers due items in bounded batches (`prefetchBatchSize: 25`) and refills automatically when remaining items reach threshold (`prefetchRefillThreshold: 3`), ensuring instant startup and low memory usage on massive repertoires (chessrs `PracticeMainPanel.tsx` semantics). *(done: 2026-09-18)*

Per `docs/INTEGRATION_MAP.md`: remaining chessrs behaviors integrated. FSRS
remains a later option — never a redesign.

## Phase 6 — Refinement (current)

- [x] **R1: Beta Fixes — Desktop Choice Picker, Scheduler Reactivity & Move-Tree Canonical Hashing**
      1. Desktop choice picker: fixed `showChoicePicker` crashing on Linux desktop (`Unexpected platform TargetPlatform.linux`) by using Material dialog fallback for non-iOS platforms.
      2. Scheduler reactivity & observability: connected `ReviewController` to `schedulerProvider` changes to reload active sessions in real time when settings change, added interval progression preview in `SettingsScreen`, and displayed scheduled next review interval post-guess in `ReviewScreen`.
      3. Move-tree canonical hashing: `computePgnHash` now hashes starting positions and move variation trees rather than volatile PGN metadata headers (`Event`, `Date`, etc.), preventing study renaming from breaking duplicate detection. Added auto-backfill of `pgnHash` for pre-v9 studies in SQLite. *(done: 2026-09-18)*
- [x] **R2: Canonical Position Knowledge State & Transposition Mapping (DSR Architecture Step 1)**
      1. Domain entity & key: `PositionKnowledgeState` and `canonicalKey(fenKey, expectedMoveUci)` (`sha1(fen4 + uci)`) representing single canonical source of truth for recall memory across transpositions.
      2. Decision pointers: added `canonicalStateId` to `RepertoireDecision` derived automatically during PGN import.
      3. SQLite schema v10: added `canonicalStateId` to `srs_decision` and created `position_knowledge_state` table with schema migration.
      4. Transposition memory sharing: reviewing a transposed move in Study A automatically upgrades the shared canonical state in Study B; deduplicated in all-study review queues. *(done: 2026-09-18)*
- [x] **R3: Pure Binary ChessFSRS Core Kernel (DSR Architecture Step 2 — Decision D015)**
      1. Domain decision D015: completely dropped latency grading from the scheduler. Thinking time reflects tactical verification and calculation, not weak memory. Ratings strictly collapse to binary Pass/Fail (`Rating.good` vs `Rating.again`).
      2. Domain kernel: `ChessFsrsScheduler` implementing continuous Difficulty-Stability-Retrievability (DSR) power-law forgetting curves ($R = (1 + F \cdot t/S)^C$) with explicit target retention interval solving ($R_{\text{target}}$).
      3. UI & Settings: added `ChessFSRS` to `SchedulerType` with user-tunable `Target recall retention` picker in `SettingsScreen` (80% to 95% tournament prep).
      4. Engine binding: `ReviewService.schedulerProvider` dynamically provisions `ChessFsrsScheduler`. *(done: 2026-09-18)*
- [x] **R4: Graph-Aware Review Coordinator (DSR Architecture Step 3)**
      1. Domain coordinator: `GraphAwareReviewCoordinator` implementing chess-specific graph propagation wrapping `ChessFsrsScheduler` or any `Scheduler`.
      2. Upstream lapse contagion (§B.1): soft exponential stability reduction ($S_{\text{child}}' = S_{\text{child}} \times (1 - \lambda_0 \cdot e^{-\text{depth}/\tau})$) for learned descendants along the line, preventing catastrophic full-subtree resets.
      3. Auto-traversal exposure credit (§B.2): bounded micro-stability bump ($\varepsilon = 0.08$) for non-due moves passed over during review traversal, throttled to 1/calendar day and refused for already-due items.
      4. Confusable sibling coupling (§B.4): dynamically couples sibling difficulty ($\Delta D = 0.35$) when an incorrect move matches an alternative repertoire continuation.
      5. Incremental side-effect persistence: `ReviewSession` reports `sideEffectStates` in `ReviewStepResult`, incrementally persisted to `position_knowledge_state` in SQLite by `ReviewService`. *(done: 2026-09-18)*
- [x] **R5: Opt-In SRS Debug Diagnostics Mode (Vanilla Clean, Debug for Beta-Testing)**
      1. Zero-friction vanilla mode: default application remains 100% clean, minimal, and calm with zero metrics clutter or cognitive load.
      2. Settings toggle: added `srsDiagnostics` boolean in `StudyPrefs` under `Review & SRS` ("Developer / SRS diagnostics").
      3. Live FSRS progression preview: `SettingsScreen` renders dynamic interval preview (`fsrsIntervalProgressionPreview`) adapting in real time to the selected target retention (e.g. 90% vs 95% tournament prep).
      4. Review HUD overlay: when enabled, displays a discreet diagnostics card below the board showing position Retrievability ($R$), Stability in days ($S$), Difficulty ($D$), Reps/Lapses, transposition badges, and step outcomes (e.g. interval growth, auto-traversal exposure, or lapse contagion). *(done: 2026-09-18)*
- [x] **R6: Unified Spaced Repetition (SRS) Settings Screen**
      1. Consolidation: unified all SRS and review-related settings (algorithm selector, FSRS target retention, parametric scaling controls, interval progression previews, board feedback/animation switches, and SRS diagnostics) into a dedicated `SrsSettingsScreen`.
      2. Clean Information Architecture: replaced 10 loose controls in the root `SettingsScreen` list with a single `Spaced repetition (SRS)` row reflecting current algorithm state, mirroring Sound, Background, and Board settings.
      3. In-Session Quick Access: added a direct SRS settings shortcut action to `ReviewScreen`'s AppBar for tuning parameters during active practice. *(done: 2026-09-18)*
- [x] **R7: Lichess Study URL & ID Direct Import Pipeline**
      1. Parsing & Extraction: added `extractLichessStudyId` and `extractStudyTitleFromPgn` to parse full URLs (`https://lichess.org/study/...`), chapter links, and raw 8-character study IDs.
      2. HTTP Import API: connected `ReviewController.importLichessStudy` to `StudyRepository.getStudyPgn` (`/api/study/$id.pgn`) to download entire multi-chapter studies across public, unlisted, and private (authenticated) studies with error translation (friendly 404 and network guards).
      3. Import Dialog UX: updated `RepertoireImportDialog` with segmented import source selection (`Lichess Study` vs `PGN Text / File`), quick clipboard paste button, auto-detection if a Lichess link is pasted into the PGN text area, and title derivation from PGN headers. *(done: 2026-09-18)*
- [x] **R8: Per-Chapter Board Orientation & Auto-Detection Heuristic**
      1. Domain Model: added `orientation: Side` property to `Chapter` entity, persisted in SQLite schema v11 (`srs_chapter.orientation`).
      2. Orientation Heuristic (`resolveChapterOrientation`): automatic derivation respecting explicit PGN `[Orientation "white"|"black"]` headers, title/event keyword tags ("for Black", "[Black]", "as Black", etc.), and player tags with placeholder opponents (`?` or `*`).
      3. Import Dialog & Pipeline: `RepertoireImportDialog` defaults side selection to "Auto" so multi-chapter studies containing both White and Black lines automatically derive decisions and board orientations per chapter without user manual intervention.
      4. Study Explorer & Review Consistency: `StudyChaptersScreen` passes chapter orientation into `AnalysisScreen`, ensuring chapters for Black open from Black's perspective; `ReviewController` falls back gracefully to chapter/study orientation when cards are all caught up. *(done: 2026-09-18)*
- [x] **R9: Scope Drawer Repertoire & Opening Hub Search Filter**
      1. Live Filtering: added search `TextField` to `ReviewScopeDrawer` filtering both repertoires (by title) and opening hubs (by opening family name) in real time.
      2. Clear & Empty States: added instant clear button (`X`) when query is present, and informative empty state feedback when no repertoires match query.
      3. UI Polish & Test Coverage: added comprehensive widget tests for search filtering and clear behavior; all 220 review/domain/persistence tests pass. *(done: 2026-09-18)*
- [x] **R10: Configurable Global Daily Position Review Limit**
      1. Setting & Persistence: added `maxDailyReviews` setting in `StudyPrefs` (default 100 positions/day, tunable to 25, 50, 100, 150, 200, or Unlimited) in `SrsSettingsScreen`.
      2. Unique Position Tracking: added `getTodayReviewedPositionsCount` to `StudyRepository` and SQLite schema v12 with index on `srs_review_event(whenTimestamp)` counting distinct positions reviewed today (not raw guesses; mistakes and reguesses count as 1 position).
      3. Session & Queue Quota: `ReviewEngine` and `ReviewSession` enforce `remainingDailyQuota` so review stops once the daily limit is hit, while allowing in-flight lapse reguesses to conclude gracefully.
      4. UI Feedback: updated `_AllCaughtUpView` on `ReviewScreen` to display "Daily Goal Reached!" with progress metrics and an "Adjust Limit" action, while leaving Free Practice mode unrestricted. *(done: 2026-09-18)*
- [x] **R11: Repertoire & Chapter PGN Export & Sharing Pipeline**
      1. Serialization API: added `ReviewController.exportStudyPgn` and `ReviewController.exportChapterPgn` compiling multi-chapter studies and individual chapters back to standard PGN notation with variations, move comments, and orientation tags.
      2. Export Dialog UX: built `ExportPgnDialog` featuring clean monospace scrollable PGN text preview, one-tap "Copy to Clipboard", native "Save File" (.pgn file dialog via `FilePicker.saveFile`), and resilient "Share" with desktop clipboard fallback in `launchShareDialog`.
      3. Entry Points: integrated "Export PGN" action in `ReviewScopeDrawer` study options sheet, global study export in `StudyChaptersScreen`'s AppBar, and per-chapter export icon buttons on chapter list tiles. *(done: 2026-09-19)*
- [~] **R16: Design V2 Gap Closure (frame repaint + real defect fixes)**
      1. Reconciled the build against `ChessSRS_ new visual identityV2.html` scene by scene. The demo proved fully reproducible from its own HTML/CSS/JS — no extra source files were needed from its author. Full contract table, deliberate divergences and open questions: `docs/DESIGN_V2_GAP_CLOSURE.md`.
      2. **Defect, not cosmetics — no keyboard shortcut worked at all.** `CallbackShortcuts` installs its key handler as a descendant of whatever wraps it, and the focus manager only dispatches to the primary focus and then its *ancestors*. `ReviewScreen` wrapped `CallbackShortcuts` in `Focus(autofocus: true)`, so the focused node was the ancestor and `Space` and `S` were never delivered — both of which the demo advertises on screen. Fixed by moving the focused node inside the shortcuts, and added the `Enter` binding the design specifies. Proven non-vacuous: the test was run against the pre-fix code and failed there.
      3. **Defects in the design system itself.** `SrsPillButton` was 15px tall (design says 46px; failed the 44px touch minimum), every `SrsPressable` announced its label twice, the review screen showed a spinner on a screen the design requires to be quiet, and a raw exception string rendered as body text on the failure screen. Four of these survived because `lib/src/design/` had zero tests; `test/design/` now exists.
      4. New primitives: `SrsToast` + `showSrsToast`, `SrsDisclosure`, `SrsLiveRegion`, `SrsSubHead`. Review copy single-sourced into `review_copy.dart` and settings copy into `srs_settings_copy.dart`, so drift shows up in a test rather than only in a screenshot.
      5. Deleted dead code and fixed a dead root navigator: `tab_navigation.dart` → `navigation.dart`, and `tab_scaffold.dart` + `more_tab_screen.dart` removed. There is no bottom navigation bar in the running app — `app.dart` has `home: const ReviewScreen()` and `MainTabScaffold` was unreachable.
      6. Analysis and Opening Explorer repainted onto the design's sub-head. Frame only: the engine, evaluation, move tree, share and archive widgets all stay, and both analysis menus are kept because they are different menus. The explorer's inline move list moved from `AppBar.bottom` to the first row of the body, since `SrsSubHead` has a fixed 60px height and no bottom slot.
      7. Verification: `./gate.sh` green including `--all`. `flutter test` is **not** run locally by design — it saturates this machine; CI is the authority. **Runtime validation is still owed: no commit here has been launched**, and every visual claim so far rests on reading the demo, not on running pixels (`AGENTS.md` §4). Branch is rebased onto `main`; the single conflict was two import lines in the explorer test. The 2 CI failures are pre-existing (`test/app_test.dart` auth-401, one of the 11 on `main`) and this branch introduces none. *(in progress: runtime validation outstanding)*

### Future Horizon Tasks & Backlog
- [ ] **F-AUTHTOKEN: Cover the startup token check**
      1. Why: when Lichess reports a stored token is no longer valid, the app deletes it (`preloaded_data.dart`, the `if (token != null)` branch). It is live — sign-in is reachable from the account menu, `LichessClient` attaches the bearer token automatically, and study import uses it — and it has no test. Deferred by owner decision 2026-09-26, to be done with the study-import work rather than ahead of it.
      2. Why it was not straightforward: `makeTestProviderScope` stubs `preloadedDataProvider`, the only code that issues `/api/token/test`, so no app-level test can observe it. A test asserting the request was quarantined as a CI-only failure for days and turned out to be unsatisfiable everywhere; it was removed in #16 rather than re-skipped.
      3. Two ways forward, both real work: mock `package_info_plus`, `device_info_plus` and `path_provider` in the shared binding and give the helper a way to *not* stub the provider; or lift the token check into a provider of its own depending only on `authStorageProvider` and `httpClientFactoryProvider`. The second reshapes inherited upstream code for testability, so it needs an explicit decision.
      4. Worth asserting at minimum: an invalid token is deleted, a valid one is kept, and a **network error keeps the token** — that last one is the safety rule in the `catchError`, and the one most worth pinning.
      5. Full account, including the wrong turns: `docs/audit-disposition.md`.

- [x] **F-LOGS: In-App Logs & Diagnostics Audit**
      1. Diagnostic Instrumentation: added dedicated runtime loggers (`ReviewEngine`, `ReviewController`, `StudyRepository`, `StudyImporter`, `FsrsScheduler`, `Database`) emitting rich telemetry for session lifecycles, move validations, lapse contagion, FSRS interval computations, orientation resolutions, and DB performance timings. Included all domain loggers in terminal output filters.
      2. HttpLogScreen Modernization: migrated to `PlatformScaffold`/`PlatformAppBar`, added trace export/share action, displayed error messages directly on log tiles, and built an inspection modal dialog with copy URL/copy details actions.
      3. AppLogSettingsScreen Polish: added quick category filter chips (`All`, `Review`, `Repo / DB`, `Import`, `Network`, `Engine`), stylized domain-colored logger badges, copy to clipboard on long-press, and a full detail inspection modal dialog with copy message/error/stack actions.
      4. SRS Diagnostics Integration: added direct "View in-app diagnostic logs" tile in `SrsSettingsScreen` under the Diagnostics section, pre-filtering directly to review and scheduling traces. *(done: 2026-09-19)*

Workflow polish, information architecture, performance, onboarding/import
improvements, remaining Lichess code removal (per CUT_PROPOSALS §2), and only
then differentiation features justified by specs or beta feedback.

---

## Recording rule

Every completed task records: what shipped, verification evidence (verify +
runtime), and date. Boundary changes update ARCHITECTURE.md/QUALITY.md in the
same commit.
