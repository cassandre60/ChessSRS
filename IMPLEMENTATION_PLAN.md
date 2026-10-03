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

- [x] **R12: Diagram visual-identity reskin** *(done: 2026-09-28)*
      1. Scope: every surface `design/docs/04-screens-and-flows.md` §1 defines — Review, Nothing due, scope list, Library, first launch/import, Settings — plus Analysis, Explorer and Board Editor behind Library → Explore. That document states "No other top-level screens exist in this design", so the remaining legacy Material is inherited surface with no design behind it and is a cut question, not a reskin one.
      2. Shared primitives: the `Srs*` set in `lib/src/design/` — pill/text/segmented/switch, settings and sheet rows, page head, dialog, search field, input, sheet surface, toast. Material-free in `primitives.dart`; the ones needing Material live in their own files.
      3. Copy: brought to `design/docs/01-identity.md` verbatim — `All repertoires`, `Openings`, `Search`, `{n} positions`/`Paused`, `Show arrows and circles`, the settings rows and their help text. Each mismatch was a separate small PR so a copy fix could not hide behind a visual one.
      4. Toast: `SrsToast` behind the existing `showSnackBar`, so all 53 call sites inherited it at once. Tone is accepted but not rendered — the design specifies one appearance — and that is recorded in the enum rather than papered over with an undescribed tint.
      5. Cuts: `CUT_PROPOSALS.md` UI-A through UI-F, including the app-background setting, which could not have worked on any screen.
      6. Defects the work surfaced, none of them in the reskin itself: `SrsPillButton` painted its label `ink` on its own `ink` background, so the one filled button in the system rendered as an empty black pill; a pill could not be made full width, because `SrsPressable` builds its child in a `Stack` that passes loose constraints down. Both found by looking at captures rather than by any assertion, and both now covered by tests verified to fail on the pre-fix code.
      7. Evidence: `flutter analyze` clean per touched file on every PR; 269 tests passing across the affected areas at the end. The full suite was never run locally — CI is the authority per §4. Runtime validation through `test/view/screenshot_capture_test.dart`, which grew to 30 captures over five widths in both themes, and which found three further defects.
      8. Prerelease: #44\u2013#58.

- [x] **R13: Announce the review verdict to screen readers** *(done: 2026-09-28)*
      1. Gap: `04-screens-and-flows.md` §6 requires position changes announced through a live region, and `01-identity.md` gives the wording — `Correct. {san}.` and `Not this move. The repertoire move is {san}.` The demo implements it via a visually hidden `aria-live` node. The app had no `liveRegion` anywhere, so nothing was announced.
      2. Why it mattered most where it was least visible: a wrong answer already puts the repertoire move on screen in large letters, so a sighted player is told. A *correct* answer renders nothing at all, because the product is deliberately quiet on success. A screen-reader user therefore played a move and heard nothing, and could not tell a right answer from a wrong one.
      3. Fix: a `_VerdictLiveRegion` in the answer slot, built on the demo's strings. Signalled by `lastStepResult` rather than `isAwaitingAdvance`, because a lapse waits to be acknowledged and never sets the latter; the controller clears `lastStepResult` on advancing, acknowledging and skipping alike, which is exactly the graded-and-not-yet-moved-past window.
      4. On a correct answer it announces the move *played*, not the expected one: `expectedMoves` is a list, so a transposition can make an alternative equally correct, in which case the repertoire move is not what the player played.
      5. Test covers both verdicts, the silent state before an answer, and that the announcement does not linger after Continue. Verified to fail on the pre-fix code.

### Future Horizon Tasks & Backlog
- [x] **F-AUTHTOKEN: Cover the startup token check** *(done: 2026-09-28)*
      1. **The task turned out not to be test coverage.** Reading the code first found that two implementations of the same `/api/token/test` call already existed: the one in `preloaded_data.dart`, and `AuthController.checkToken`, which `http.dart` already calls on every 401. The second was fenced on both the controller's generation and the token's identity; the first was not, and it called `authStorage.delete()` directly.
      2. **The bug that made it worth doing:** `AuthStorage` holds one session under one key, so that delete removed whichever session was stored when the response landed. Sign-in is reachable throughout, and the request had a five-second timeout — so an account that signed in while the check was in flight was signed straight back out. That is the exact failure `auth_identity_fencing_test.dart` exists to prevent on the fenced path, and the startup path was the naive version that was never replaced.
      3. **Neither route in the original plan was right.** Mocking the platform plugins would have tested the buggy copy and cemented it; extracting a provider would have made the duplicate testable while keeping it. Owner decision 2026-09-28: delete the duplicate and route startup through the fenced, already-tested `checkToken`.
      4. `startupTokenCheckProvider` in `auth_controller.dart`, read once from `Application.initState`. Not `autoDispose`, because it is a one-shot that must survive having no listener. It swallows network errors — `checkToken` rethrows by design, because `http.dart` depends on that, and a launch that cannot reach Lichess must not look like an invalid session.
      5. Net −22 lines of production code, one implementation instead of two. A second divergence fell out: the old code cleared storage but never the in-memory `authControllerProvider` state, so an invalid session still read as signed in until a 401 round-tripped.
      6. **The harness trap did not apply after all.** `makeContainer` already stubs `preloadedDataProvider` to supply the starting user, which is exactly the input `checkToken` wants — so no binding changes and no plugin mocks were needed. The test asserts all four rules, and the fence test was verified to fail against the restored un-fenced logic (`deleteCalls` 1 where it must be 0).

- [x] **F-LOGS: In-App Logs & Diagnostics Audit**
      1. Diagnostic Instrumentation: added dedicated runtime loggers (`ReviewEngine`, `ReviewController`, `StudyRepository`, `StudyImporter`, `FsrsScheduler`, `Database`) emitting rich telemetry for session lifecycles, move validations, lapse contagion, FSRS interval computations, orientation resolutions, and DB performance timings. Included all domain loggers in terminal output filters.
      2. HttpLogScreen Modernization: migrated to `PlatformScaffold`/`PlatformAppBar`, added trace export/share action, displayed error messages directly on log tiles, and built an inspection modal dialog with copy URL/copy details actions.
      3. AppLogSettingsScreen Polish: added quick category filter chips (`All`, `Review`, `Repo / DB`, `Import`, `Network`, `Engine`), stylized domain-colored logger badges, copy to clipboard on long-press, and a full detail inspection modal dialog with copy message/error/stack actions.
      4. SRS Diagnostics Integration: added direct "View in-app diagnostic logs" tile in `SrsSettingsScreen` under the Diagnostics section, pre-filtering directly to review and scheduling traces. *(done: 2026-09-19)*

### Closed
- [x] **F-AUTHBODY: confirm #94 against the production server** *(opened: 2026-09-29, closed: 2026-10-02)*
      1. **Verified against production, and it was five defects, not one.** The item was opened against PR #94 (credentials in the POST body) and could not be closed by it. What actually had to change, in order: the default host was `lichess.dev` (#124, so `lichess.org` needs no `--dart-define` any more); the mobile-code endpoints needed a query-parameter fallback (#123); `flutter_appauth` is Android/iOS-only, so desktop sign-in is a loopback PKCE flow over a local `HttpServer` (#125); the session did not survive navigation until `authControllerProvider` stopped being `autoDispose` (#126); and every WebSocket handshake was refused with HTTP 400 because the sri was missing from the query string (#129).
      2. **Closing evidence:** the owner signed in through the browser on Linux desktop, and the app's `http_log` then shows `GET /api/study/Gg4E2sIS.pgn → 200` — a private study imported. Ping tile reads `PING nn ms` rather than `Offline`.
      3. **Do not re-investigate:** `_emailRegExp`, `AuthRepository`, `AuthController` and `UserRepository.usernameExists` are byte-identical to upstream, so none of the above was a defect in them. No Lichess client accepts a password, so "user + password" is not implementable. Full chain with the ruled-out suspects: `docs/open-email-login-handoff.md`.
      4. **Email-code login is now the mobile path only** and remains unverified against production, since no device was attached. Desktop sign-in goes through OAuth and is verified. Reopen this item only if someone runs it on Android or iOS.
- [x] **F-STUDYPERSIST: does a remote study edit reach the local database?** *(opened: 2026-10-02, closed: 2026-10-02)*
      1. **Verified: No remote study edit ever reaches the local database, by design.**
      2. **Code audit:** `StudyController` holds `_root` (`RootNode`) in memory. Its `handleSocketEvent` applies lila's `promote`, `deleteNode`, `anaMove`, `anaDrop` topics to `_root` and calls `_refreshTreeView()` to update UI state. It contains zero references or imports to `srs_study`, `SqliteStudyRepository`, or any database persistence layer.
      3. **Local repertoires vs. online viewer:** When a study is imported into ChessSRS (via PGN or "Fetch & Import from Lichess"), it is stored in SQLite (`srs_study`, `srs_chapter`, etc.) with a newly generated UUID and operates strictly as a local-first offline repertoire. It does not open a study socket. When a local study is opened via "Analyze" in the scope drawer, `study.socketVersion` is null, so `StudyController` does not even open a `/study/.../socket/v6` connection.
      4. **Conclusion:** Remote study socket events are strictly in-memory presentation updates for live viewing of remote Lichess studies. There is no background divergence, no silent overwrite, and no database mutation from WebSocket study events.

### Closed — gate defects fixed 2026-10-03 (each landed as its own gate-change PR)
- [x] **G-BASEINV: G05 judged a PR's test citations against the base ref, so no PR could add a SPEC invariant** — fixed by #135 (phase 1: `--base-spec` flag on `spec_trace_check.py` + local `gates.sh` parity) and this PR (phase 2: CI step activation). Proven locally (old logic reproduces the #130 failure, new logic passes both-at-once while still rejecting typos and spec-deletion dodges) and by this PR's own green T1, which runs the new flag in CI.
- [x] **G-LABELEVENT: adding `gate-approved` never re-ran the gate** — fixed by #133 (`types: [opened, synchronize, reopened, labeled]`). Proven live: the label on #133 fired a fresh T1 run that went green.
- [x] **G-CIREPORT: required checks that never run block merges permanently, even for admins** — fixed by #136 (widened `test.yml` paths to the referee set). Proven live: #136, #133, and #135 phase 1 all got both reports and merged; pure `docs/**` stays lane-less by decision and must ride along.

### Open — gate defects
(none — G-BASEINV, G-LABELEVENT, and G-CIREPORT are closed above.)

### Open — awaiting verification (not blocking the MVP)
- [x] **F-CLOUDEVAL: exercise cloud Stockfish evaluation with a live socket** *(opened: 2026-10-02, verified: 2026-10-03)*
      1. Live round-trip from the dev machine: `wss://socket.lichess.org/analysis/socket/v5?sri=<rand>` handshake accepted (no 400 — the #129 fix holds against production), `evalGet` answered with `evalHit` depth 65.
      2. HTTP fallback `/api/cloud-eval` answered the same position identically.
      3. New oracle: analysis-route `sri` assertion in `test/network/socket_test.dart` (INV-064 per route, not just default). Full file 46/46, analyze clean.
      4. Remainder is owner-beta territory: open any study → Analyze and watch cloud depth arrive in-app.
- [ ] **F-MOBILELOGIN: email-code sign-in on a real device** *(opened: 2026-10-02)*
      1. Desktop sign-in goes through loopback OAuth (#125) and is verified; the mobile-code path is not, because no device was attached.
      2. This is the only path that exercises #123's query-parameter fallback on `/auth/mobile-code/email` and `/bearer`. Needs an Android or iOS device against `lichess.org`, now the default host — no `--dart-define`.

### Open — product backlog (deferred, unscheduled; owner-reported 2026-10-03)
- [ ] **P-COLLAPSE: collapsible scope-drawer groups** — the `Everywhere` / `Openings` / `Repertoires` groups in `ReviewScopeDrawer` are flat headers; with many studies and hubs the list gets long. Each group should collapse/expand (persisted per group).
- [ ] **P-RESTUDY: rename "repertoires" to "studies"** — user-facing copy (`All repertoires`, `Repertoires` group, review-screen scope label) should say studies. Note: `design/docs/01-identity.md` currently prescribes `All repertoires`, so the design doc changes with the copy; domain entity names (`Study`, `Chapter`) already match.
- [ ] **P-OPENNAME: spurious opening hubs from Event-header fallback** — `extractOpeningFamily` (`lib/src/import/pgn_importer.dart`) accepts `Event` headers containing a keyword (`french`, `game`, …), so non-opening event names (e.g. `White vs French`-style titles) become bogus opening hubs. Tighten `_isLikelyOpeningName` or require ECO corroboration; never invent a hub when uncertain (leave `opening` null).
- [ ] **P-TRANSPOSE (optional): transposition support in review mode** — R2 already shares SRS memory across transposed positions; this asks for review-time behavior (move-order tolerance / transposed lines resolving to the same drill). Explicitly optional; needs a spec first, never a scheduler redesign.

Workflow polish, information architecture, performance, onboarding/import
improvements, remaining Lichess code removal (per CUT_PROPOSALS §2), and only
then differentiation features justified by specs or beta feedback.

---

## Recording rule

Every completed task records: what shipped, verification evidence (verify +
runtime), and date. Boundary changes update ARCHITECTURE.md/QUALITY.md in the
same commit.
