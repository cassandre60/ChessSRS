# Implementation Plan & Phase Status

Authority: delivery/evidence ledger, not a second requirements manual.
See docs/documentation-map.md for the normative home of each rule.

## Current status and entry points

The vertical slice shipped to the owner on 2026-09-16; work is in **Phase 6
refinement**. Phases 0–5 below are historical delivery records. Their test counts,
UI names, schema versions and measurements describe recorded snapshots, not
today's inventory or a fresh runtime pass.

- Current included/deferred scope: MVP.md.
- Ready briefs and claims: docs/tasks/README.md; autonomous campaigns:
  docs/AUTONOMOUS_WORK_LEDGER.md.
- Owner decisions: docs/open-questions.md; device evidence: docs/manual-test-log.md.
- Performance findings: docs/performance-handoff.md and its measurement brief;
  older noisy medians below are not optimization proof.

### Reconciled dispositions (2026-10-21)

- Firebase/FCM were removed; C1/C2 are no longer grey/kept. CUT_PROPOSALS owns cuts.
- R3 shipped ChessFSRS; "FSRS remains later" in the old Phase 5 summary is obsolete.
- R2's single-move identity was superseded by the complete-answer-set, trained-side
  key and rekeys (ARCHITECTURE §5; INV-016/017/030/069).
- A11Y-FIX-27, POLISH-FIX-11 and startup/performance work formerly listed in flight
  have landed; use docs/tasks/README.md rather than that historical queue.
- Q5 shared-account approval limitation was accepted; Q6 docs CI triggers were
  fixed. The old gate findings below are historical, not open work.
- getDueReviewStates was removed on owner authorization (Q4); the old queue's
  "excluded pending signature" instruction no longer applies.
- P-SYNC remains deferred, but not because Firebase is currently pointed at
  Lichess: Firebase was removed. Backend/auth/format choices remain undecided.
- Local full-suite/verify recipes below are historical: TEST_STRATEGY §2 now
  governs verification with no local wide-suite exception.
- Documentation reconciliation: docs/documentation-reconciliation.md;
  no product code or INV clauses changed; owner approved publication and this
  documentation-only diff on 2026-10-21; remote CI pending. Q7–Q10 remain open.

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

- [x] **R14: Bulk import of owned Lichess studies** *(done: 2026-10-14, owner request)*
      1. `ReviewController.importAllMyStudies`: pages `StudyCategory.mine` (signed-in client, so private studies included), fetches each PGN, imports via the normal pipeline with `repertoireSide: null` so every chapter trains from its own side (INV-013). Duplicates skipped by hash (INV-003); failures recorded per study, batch continues (INV-011). Scope reloaded once at the end, never jumped per study.
      2. `importPgnText` gained `switchScope` (default true, single-import behavior unchanged).
      3. UI: "Import all my studies" action in the import dialog's Lichess tab, signed-in only, with determinate progress and an imported/already-here/failed summary.
      4. Tests cite INV-003/INV-011/INV-013; no SPEC change needed.

- [x] **R15: Bulk import refusal says why + desktop OAuth asks study:read** *(done: 2026-10-14, owner-reported failure)*
      1. Production failure: desktop sign-in granted no OAuth scope, so `/study/mine/...` answered 401 and the dialog said only "bulk import failed". Verified live: anonymous listing gets 401, public listing parses to the assumed shape.
      2. `buildDesktopOAuthUri` now sends `scope=study:read`. Existing desktop grants stay scopeless until sign-out + sign-in.
      3. Listing failures throw `BulkImportListException` carrying the reason (401 names the missing permission + the fix); the dialog shows it inline and in the snackbar, never a bare failure.
      4. Progress moved inside the button (spinner + `Importing n of N…` / `Listing your studies…`).
      5. Regression tests: 401/500 listing errors, widget test that the reason reaches the screen, desktop scope URI test.

- [x] **R16: 403 on the study list gets the permission message too** *(done: 2026-10-14, owner-reported)*
      1. Second sighting of the same scopeless-grant failure, now as 403 instead of 401 — and the generic branch answered with a bare status number. 401 and 403 now share the permission message, extended with the revoke fallback (`lichess.org/account/oauth/token`) for grants Lichess silently reuses.
      2. Regression test pins the 403 wording (status, sign-out, revoke link).

- [x] **R17: Enumerate bulk import through the Studies API, not the website list** *(done: 2026-10-14, owner log)*
      1. Decisive evidence: a fresh sign-in *with* `study:read` still got 403 on `/study/mine/updated`. That page rejects third-party OAuth tokens outright — no scope fixes it. Meanwhile `GET /api/study/by/:username` is a real API route (NDJSON, verified live anonymously: same ids/names as the site).
      2. `StudyRepository.getStudiesByUsername` streams that endpoint; the controller lists by the signed-in account name and refuses while signed out without a call. Website-list error handling stays for the message paths.
      3. Tests re-mocked to NDJSON + a seeded `tester` account, plus a signed-out no-call test. The mock shapes now match a live server response each.

- [x] **R18: Taps in the pre-move animation window no longer die + duplicate names in bulk summary** *(done: 2026-10-14, owner-reported)*
      1. Frozen board: after a line transition the board shows the incoming move's parent position for 350ms while the prompt already expects the reply — own pieces undraggable, taps silent. Bulk's end-of-batch reload re-armed exactly that state. Fix: `cancelPreMoveAnimation` snaps a lagging board to the live prompt; called on every submitted move and on every board tap-down (no-op in sync, pending animation lands identically).
      2. The same window crashed the controller (`PlayException`) when a move reached grading against the lagged board — proven by the new mid-session test failing pre-fix, passing post-fix (INV-020).
      3. Bulk summary now names skipped duplicates (`N already here (a, b, …)`) so "left out" studies are identified instead of counted.

- [x] **R19: Bulk re-import skips unchanged studies + awaiting-advance deadlock heals** *(done: 2026-10-14, owner-reported)*
      1. Slow re-import: every run re-downloaded and re-hashed all 60 studies. Linkage now lives in a side table (`srs_study_remote`: study id, remote id, remote timestamp; schema v17 via idempotent `CREATE TABLE IF NOT EXISTS`, cascade on study delete) — deliberately not on the Study entity, so the domain stays untouched and no ALTER can fail an open. Unchanged remotes skip the fetch; duplicates backfill the linkage for pre-linkage imports.
      2. Permanent freeze suspect: `continueAdvancement` with the awaiting flag set and no pending step returns silently, so every later tap no-ops forever (scope change is the only exit). No reachable path sets that combination, but no path recovers it either — so it now releases the board with a warning log.
      3. Freeze root cause found separately (R20) via the owner's log paste.

- [x] **R20: Drop ghost FKs blocking every graded answer (the freeze)** *(done: 2026-10-14, owner log)*
      1. Chain, all verified: V3 created `srs_review_state/event.decisionId → srs_decision(id)` FKs; later schemas dropped the clauses without removing them from old tables; R4's canonical-mirror writes position keys (never decision rows) into review_state; #88 switched FK enforcement on. Since then every graded answer crashes on persist (UI never updates; skip writes nothing so it works). Fresh installs never had the clauses — which is why no test caught it.
      2. Schema v18 rebuilds both tables without the undeclared clauses, preserving rows and indexes; only existing tables are rebuilt. Existing-data upgrade, idempotent create, and the exact production write (canonical mirror with no decision row) are pinned by tests citing INV-001/INV-005 — verified to fail pre-fix.
      3. Owner note: failed writes rolled back, so SRS memory is intact; answers given since enforcement began need re-reviewing.

- [x] **R21: Drawer scopes carry the drawer colour (no more mid-session side flips)** *(done: 2026-10-15, owner-reported on device)*
      1. The scope model documents that every drawer-produced scope names its side — but the study/opening/chapter constructors hardcoded `side: null` and the drawer never passed its colour. Sessions therefore mixed White and Black chapters: finishing a White French line could serve a Black prompt (the owner's French study holds Black-to-move middlegame excerpts auto-oriented Black), flipping the board unprompted; the squares then disagreed about which colour was live, so only one behaved.
      2. Constructors take an optional `side` (default null: all existing callers and sideless behavior unchanged); the drawer passes its colour for study, opening, and practice scopes; the service narrows study/opening/chapter loads to that side (trees and states together, per the INV-030 note on the side branch). Selection highlight requires the side to match, falling back to study-only for sideless scopes.
      3. No import, heuristic, migration, or re-import involved: orientations stay as stored; training from a colour drawer stays that colour. Tests cite INV-030.

- [x] **R22: Colour squares open the drawer instantly** *(done: 2026-10-15, owner-reported on device)*
      1. Tapping a square awaited the full scope reload (whole-library session rebuild, seconds at 61 studies) before the drawer opened. The drawer now opens first and the reload lands behind it; its highlight and counts refresh via the provider watch, and a scope picked inside supersedes the in-flight load by generation.
      2. No new test: timing-dependent and the drawer suites cover the flow; verified by analyze + owner runtime check.

- [x] **R23: Colour squares work inside the scope drawer** *(done: 2026-10-15, owner request)*
      1. Switching colour cost dismiss plus retap. The drawer's search header now carries the same square pair (extracted as shared `SrsColourSwitch`, top bar unchanged visually); tapping the other square switches the drawer's content in place and follows with the scope switch behind it.
      2. Same-side taps no-op; search text survives the switch. Test pins the one-tap switch with scope following (INV-030).

- [x] **R24: Review path scale jump and performance optimizations** *(done: 2026-10-16)*
      1. Scale Jump: with bulk import growing the owner's database to 61 studies, 309 chapters, and 31,182 decisions, review session startup and due tallies were measured on the real 35 MiB database (`PERF-FIX-24`).
      2. Tally & Date Optimization: added `getTallyDecisions` to omit decoding JSON expected moves for 31k decisions (#142); adaptive query chunking (#143); `parseUtcIso` for allocation-free date parsing (#144); SQLite native page mmap (#146); differential tallying (#151); board repaint boundary isolation (#147); and sub-sensory move prewarming (#150).
      3. Startup Queries: replaced 61 serial chapter queries in `_loadActiveStudiesAndChapters` with `getChaptersByStudyIds` batch query (#158); added fast-path string decoding for single expected moves, dropping `getAllDecisions` time from 195 ms to 142 ms; single-pass queue partitioning in `ReviewSession` (#158).
      4. Targeted Scope Decisions: added `getDecisionsByChapters` and SQL-level `orientation` filtering on chapters (#172), eliminating parsing of 142 opposite-side chapters and dropping whole-library White session start from 1,086 ms to 569 ms.
      5. Lazy Chapter Deserialization: added `rootResolver` to `Chapter` and on-demand session indexing in `ReviewSession` (#175), deferring `treeJson` parsing of inactive chapters.
      6. Cold-Start Pre-warming: prewarm SQLite study repository and `reviewControllerProvider` in `AppInitializationScreen` during splash; await repository future in `ReviewController.build()` to eliminate cold-start empty state flash (#181).

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
- [x] **P-ORDER: present the same due set in line order** *(done: 2026-10-03, extended 2026-10-04)* — new `ReviewOrder` setting (Due date | By line | Random, default By line): same urgency-selected set and quota cut, consecutive prompts follow study/chapter/tree order (SPEC INV-066). Researched against Listudy line-walking and chessrs due queues first.
- [x] **P-COLLAPSE: collapsible scope-drawer groups** *(done: 2026-10-03)* — Everywhere/Openings/Studies headers toggle their groups (44px targets, screen-reader expanded/collapsed announcements); state persists per group in `StudyPrefs.collapsedScopeGroups` across closes and restarts. Search overrides collapse (every match shows). Drawer capture eyeballed: headers render with chevrons, no overflow (icons are tofu in the capture env, as are all icons there — verified against the symbols package instead).
- [x] **P-RESTUDY: rename "repertoires" to "studies"** *(done: 2026-10-03)* — all user-visible copy says studies (`All studies`, `Studies` groups, `Rename/Delete study`, `Study "x" is already imported`, `The study move is …`, `Choose/Bring your study`, `Import a study first`, `study.pgn`, `Untitled Study` fallback). Design doc decision recorded. Deliberately untouched: domain identifiers, PGN `[White "Repertoire"]` interchange placeholders (importer-tested back-compat), the `Chess Repertoire SRS` app/store name (needs its own decision), non-English locale values (pipeline). Goldens intentionally not regenerated (pre-existing machine drift: untouched screens mismatch identically).
- [x] **P-OPENNAME: spurious opening hubs from Event-header fallback** *(done: 2026-10-03)* — `extractOpeningFamily` accepted `Event` headers merely containing a keyword (`White vs French`, `My Custom French Repertoire`, `Good Game` became hubs). `_isLikelyOpeningName` now requires the family to lead the name (word boundary, hyphens normalized) or close it with a category noun; bare category words match nothing. Real families preserved (`French Defence - Winawer`, `French Defense for Black`, `Queen's Gambit Declined`, `Petrov Defense`, ECO fallback untouched). Direct `Opening` headers stay trusted (authoritative metadata).
- [x] **P-TRANSPOSE: transposition support in review mode** *(done: 2026-10-03, extended 2026-10-04)* — a legal move matching no expected continuation is graded correct when its position exists in the active scope's tree (SPEC INV-065); review jumps to the transposed line. Out-of-scope/illegal stays incorrect. R2's shared memory already covered scheduling; this covers grading. Follow-up: `Transposed moves` setting (Off | Within study | In scope, default In scope) with legacy on/off migration; end-of-line continuation deliberately not built (on hold).

- [x] **P-CONTINUITY: line-continuity setting (Due only | Full line)** *(done: 2026-10-16, extended: whole lines start to end)* — owner-reported review jumps: (1) scattered position-to-position jumps at branches (due-aware + weighted-random opponent choice), (2) A → C skips over an unasked B when B is learned-but-not-due (auto-traversal by design, INV-022). New `ReviewContinuity` setting (default Due only = current behavior, unchanged). Full line plays every line whole from its first move to its last: a queued mid-line card opens at its line start, branches always follow PGN tree order and are never steered toward queued dues (an early guided-steering design did exactly that hijack and was removed on the owner's Rb2 report), a sideline missed by the first walk gets a dedicated walk down its own ancestry instead of a mid-line drop, and lapse-acknowledge continues down the same line (failed card requeued). Graded normally (counts toward the daily limit); quota still caps prompted work. Owner-verified in-app from engine logs (`due=false` cards prompted under Full line).
- [ ] **P-EXPORT-ALL: full backup export (all studies + all SRS data)** *(opened: 2026-10-09, owner idea)* — R11 covers one study / one chapter to PGN only. Full export bundles every study (PGN with variations/comments/orientation per INV-014) plus SRS state (`srs_review_state`, `position_knowledge_state`, `srs_review_event`) with a restore path. Post-MVP; needs a format decision (PGN bundle + JSON/SQLite dump) and stays local file/share only, no cloud.
- [ ] **P-SYNC: optional cross-device sync of studies + SRS data** *(opened: 2026-10-09, owner idea)* — PRODUCT Future Horizons + D009 already scope sync to both content and review state. MVP explicitly excludes cloud sync/accounts (MVP §3). Blocked on a backend we own: Firebase still points at lichessv2 (D017), Lichess OAuth covers study import only. Auth options (Lichess OAuth vs Google OAuth) undecided; local-first critical path stays offline per QUALITY §1.
- [x] **B-THEME-ORPHAN: board/piece picker vs render mismatch** *(done: 2026-10-09)* — `toBoardSettings` piece assets now faithfully render the selected `pieceSet.assets` (including Colin M.L. Burnett), eliminating the visual mismatch between the settings preview and in-app boards; overflow (`...`) button opens settings directly; Rate this app is disabled pending store release; Data & Diagnostics is confirmed debug-only (`kDebugMode`).
- [x] **B-TOPBAR-NARROW: review top bar overflowed below ~216px of window** *(done: 2026-10-09, #34)* — `RenderFlex overflowed by 1.2 pixels on the right` from a 215px window: the bar's non-flex children total ~196.2px against 195px available. Two causes, not one. (a) `Transform.translate(-10, 0)` on the colour squares was a leftover from the scope button it replaced — that button carried a matching `padding: 7px 10px` so the nudge cancelled out, but the squares have no such inset, so it only pulled them outside the bar's own `L16` padding while layout kept reserving the full 98px. It is paint-only and recovered no layout width, contrary to first reading. (b) `gtk_window_set_default_size` seeds geometry but sets no floor, so the window could be dragged below anything the layout supports. Fixed by dropping the transform and adding `gtk_widget_set_size_request(window, 320, 480)`. Regression test cites INV-062, whose "survive narrow viewports" claim was previously untested — the narrowest surface any test pumped was 360px. Deliberately **not** done: a `Flexible`/ellipsis on the due count — `reference/styles.css` sets `.due{white-space:nowrap}`, and below ~160px the two 48px targets plus the overflow button leave nothing to shrink into, so it would silently drop `" due"` at widths nobody should reach. **Not runtime-validated**; `linux/**` is in no workflow's `paths` filter, so the GTK line has no automated coverage. Follow-ups not taken: `SrsTopBar.wide` and `showScopeAndDue` are dead parameters (never read, never passed), and `03-components.md` §2 should name the 320px floor so it is specified rather than only enforced in C++.
- [x] **B-QUOTA-LOG: "Daily review quota (94) reached" said something false** *(done: 2026-10-09, #35)* — observed live as `Daily review quota (94) reached, truncating queue...` immediately above `quota=6/100`. `94` is the *remaining* allowance (100 − 6 reviewed), not a count reached; nothing had been reached, the due queue was simply longer than the day's remainder. It also never reported the queue length, so a truncated queue left no trace of what was dropped. Log text only, truncation behaviour unchanged and still covered. The sibling "quota reached (n / quota)" line is accurate and was left alone. Related and deliberately untouched: `totalDueCount` is itself clamped to the remaining quota (`review_service.dart:639`), so the bar reads "94 due" when more are due — quota-consistent with INV-031, but a product decision, not a wording fix.

Workflow polish, information architecture, performance, onboarding/import
improvements, remaining Lichess code removal (per CUT_PROPOSALS §2), and only
then differentiation features justified by specs or beta feedback.

### Orchestrated review-fix task queue (docs/tasks/)

A full-codebase review produced 37 self-contained task briefs in `docs/tasks/`,
each one worktree + one PR, executable by an agent without further context.
Status:

- **Merged**:
  - 01 (#45, scope mismatch)
  - 03 (#51, tree count memo)
  - 04 (#58, pgnHash backfill batching)
  - 05 (#57, presentation-db boundary)
  - 06 (#87, scope setup dedupe)
  - 08 (#88, foreign keys and not in)
  - 09 (#63, drawer breakpoint/sizing)
  - 10 (#69, isolate threshold / notation reserve)
  - 11/28 (#82, import concurrency lock / serialize imports)
  - 12 (#50, offload helper & drawer a11y)
  - 13 (#49, timezone UTC persistence)
  - 14 (#48, latency preservation)
  - 15 (#47, remove deleteDecisionsByStudy)
  - 18 (#53, pgn copied l10n)
  - 19 (#52, pumpAsync flake polling)
  - 21 (#84, getDueSummary targeted query)
  - 22 (#54, reachability test prune)
  - 23 (#91, getDueSummary tally extraction)
  - 24 (#55, debugPrint to Logger)
  - 25 (#64, import 10 MB size guard)
  - 29 (#66, route swallowed catches to Logger)
  - 31 (#65, prefs corruption backup & log)
  - 32 (#67/#68, session constructor cost pinning). Phase 2 (chunked async factory) was **declined on measurement**, not forgotten: ~41 ms at 10k decisions, ~3.7 ms at 2k, and QUALITY §4.1 covers the move path, not session start. Do not reopen Phase 2 without a real library above ~5k positions. Recorded in `test/review/session_constructor_cost_test.dart`.
  - 35 (#85, linux sound process leak)
  - 37 (#90, review keyboard shortcuts / Enter, NumpadEnter, ArrowRight)
  - PERF-FIX-21 (#84, targeted review-state load in getDueSummary)
  - REFACTOR-FIX-20 partial (#94, SrsMovePair removed)
  - Whole-codebase review program: Rounds 1–10 merged (#32, #40, #41, #42, #43, #56, #70, #83, #86, #92)
  - 16 (#46, review state mirroring docs & rename getReviewStatesByIds)
  - 34 (AUDIO-FIX-34: review mode move feedback & error sound/haptics, #93)
  - 20 (REFACTOR-FIX-20: nine zero-caller symbols removed, #105)
- **Withdrawn / Obviated**:
  - 02 (transposition FEN — audit proved non-bug)
  - 17 (chapters diagram reskin — screen deleted in #61)
  - 33 (retryMove ghost queue — re-test on lapse is intended spaced-repetition contract)
  - 30 (A11Y-FIX-30: analysis screen semantics — four of its five claims are false. `SrsSegmented` already passes `semanticLabel` and `semanticsToggled`; the variant picker is a `BottomSheetAction` wrapping `Text(context.l10n.variant)`; the "eval lines" widget renders player name/rating/clock and contains no eval lines; the surface's single `IconButton` has a `tooltip`. Wrapping already-labelled controls in `Semantics(label:)` produces double announcements.)
  - 05 (ARCH-FIX-05: presentation/db boundary — `git grep -ln "src/db/\|src/persistence/" -- 'lib/src/view/**'` returns nothing, so zero of 74 view files import either. The boundary the brief says is violated is clean.)
  - DOMAIN-FIX-36 (contagion tau guard and sub-ms stability floor already on main; probe showed no collapse — brief should be withdrawn)
  - ERROR-FIX-29 (account prefs and share catches already log with stack; the cited importer catch is gone; the one remaining catch records its message and was probed as reachable — nothing to add)
  - SAFETY-FIX-25 (10 MB guard `kMaxPgnInputBytes` already checked at file pick, paste and `importPgn`, with tests on the rejection and the limit boundary)
  - SYSTEM-FIX-35 (Linux player already uses `unawaited(Process.run(...))` with an `onError` swallow, landed in #85). Known gap: no test covers `_LinuxSoundPlayer`; the class is private and only observable through a real process, so a test would mock the subject. Do not reopen unless the player is refactored to expose its argument builder.
  - DATA-FIX-26 and ARCH-FIX-07 (both describe the non-atomic PKS/mirror dual write; `savePositionKnowledgeState` and `savePositionKnowledgeStates` already run in one transaction, and `a failed mirror write rolls back` fails when the transaction is removed, verified by a probe on a scratch copy). Do not reopen.
  - DATA-FIX-31 (corrupt prefs blob is copied to `<key>.corrupt-backup` and logged at SEVERE on both fetch paths; `corrupted prefs blob is backed up` fails when the backup write is disabled, verified by a probe on a scratch copy). Do not reopen.
- **In flight / Finishing CI**:
  - 27 (A11Y-FIX-27: review screen semantics)
  - 11 (POLISH-FIX-11: pgn shapes & board notify)
  - PERF-STARTUP (single-pass session start deduplication in ReviewService and ReviewController)
- **Queue pruned 2026-10-13.** 34 briefs were verified against `origin/main` and removed; only the two in-flight briefs above remain. They split three ways: landed by this fleet (often by another agent on the same brief), already correct in the code, or false premise. Evidence per brief is in issue #71; every file remains in git history. `docs/tasks/README.md` records the two habits that stop briefs rotting — state the premise as a runnable command rather than a line number, and say what "already fixed" would look like.
- **Remaining / Planned**:
  - None currently queued.
- **Pitfalls for queue work** (each verified on `origin/main`; read before picking a brief):
  - Re-check every brief claim with `git grep` on `origin/main` before editing. PERF-FIX-21 named a helper that had been renamed; DOMAIN-FIX-36 described fixes already present.
  - Before removing a "dead" symbol, grep `lib/` **and** `test/`. Several dead-code rows have live test callers, and removing them means deleting tests the gates forbid (G08). REFACTOR-FIX-20 landed nine symbols whose only reference was the declaration; `getDueReviewStates` is equally dead but still excluded, because deleting it deletes its only test and that needs a human `Ack-G08` signature — writing one on your own PR is the abuse the gate exists to prevent. `getDueCount` is dead in production but is the assertion helper for ~10 call sites, so retiring it is a test refactor rather than a deletion.
  - `CallbackShortcuts` fires only for a focused descendant. A binding on the widget that holds focus is skipped silently (DESKTOP-FIX-37, PR #90).
  - `sendKeyEvent(numpadEnter)` does not reach a numpad binding in widget tests. Numpad shortcuts need a manual check on a device.
  - A PR goes `BEHIND` whenever `main` moves; merge `main` in, re-verify, wait for CI on the new head, then merge. `mergeStateStatus` reads `UNKNOWN` for a few seconds after a push.
  - Protected referee files (`AGENTS.md`, `GATES.md`, `.gates/`, CI config) fail G07 in any non-gate-change PR. Lessons that belong in `AGENTS.md` need a separate, human-approved gate-change PR.

---

### Gate finding 2026-10-14 — G07 approval cannot be attributed

`protected_paths_check.py` accepts `--approved` when a label named
`gate-approved` exists, without checking who added it. The obvious hardening —
require the approver to differ from the PR author — is **impossible in this
repo**: `cassandre60` is the only collaborator and every PR author, because
agents push with the owner's credentials. That rule would block every
protected-path PR permanently.

In practice G07 stopped nothing this session: #95, #99 and #117 were each
approved by their own author. Recorded so the next agent does not assume G07
deters self-approval, and does not build an unsatisfiable rule.

The achievable change is a signed `Ack-G07: <reason>` commit trailer, matching
G08 — accountability rather than enforcement, since one shared account means
nothing in GitHub distinguishes the owner from an agent. Open as Q5 in
`docs/open-questions.md`.

### Measured 2026-10-14 — real-library session cost (PERF-FIX-24)

Every prior number came from a synthetic fixture. Measured against a **copy** of
the owner's database (10 active studies, 23 chapters, 519 decisions, 480 due,
7 MiB, canonical sharing 1.17x), median of 15 after 3 warmups:

| Measurement | Result |
|---|---|
| whole-library `startSession()` | **37–39 ms** |
| `getDueSummary()` alone | **26–30 ms** |
| largest single study `startSession()` | 15–16 ms |

The synthetic harness measured only the constructor (~2 ms at this size) and was
right about it; the path a user pays is **~18x** that, and ~75% of it is SQLite
query time no benchmark had measured. PERF-FIX-32 Phase 2 proposed chunking the
constructor, which would have targeted ~5% of the observed cost — declining it
was correct for the constructor, but the decline should not be read as "no
performance work needed".

**Not a QUALITY.md §4.1 breach.** §4.1's 16 ms is Move Response Time (legality
+ repertoire lookup on a move); a session start is off that path.

Follow-up worth a decision: `getDueSummary` at 26–30 ms. Read-only, and
PERF-FIX-21 already landed a targeted query there (#84), so it may be near the
floor for this schema.


### Dead-code audit 2026-10-13

Tree-wide sweep for declarations with exactly one occurrence across `lib/` +
`test/` + `scripts/`: 72 candidates in `lib/src/model/`. Triaged into
REFACTOR-FIX-21 (hand-written `deep_pick` `OrNull` helpers) and
REFACTOR-FIX-22 (14 dead predicates and providers), both verified
declaration-only and free of `@override`. The ~30 enum values that also matched
went to REFACTOR-FIX-23 as an investigation rather than a deletion: a sound
theme persisted as `sfx` must still parse after an upgrade, and deleting the
value silently resets it. The investigation concluded 2026-10-14: all four
groups (SoundTheme, StockfishLevel, MaiaRating, LinkSite, GameSource/GameRule)
are live via settings pickers, disk audio assets, opponent sliders, or API parsing;
zero enum values were deleted.

The sweep command is recorded in each brief so a stale brief is detectable in
seconds. Two symbols in the first draft (`asGameFullIdOrNull`, `asUserIdOrNull`)
were live and are marked "must stay" — caught by running the brief's own command
before shipping it.

### Runtime validation log

Per AGENTS.md §4, milestone runtime evidence. Only entries actually exercised are
recorded; a code PR verified by tests and CI alone is not runtime-validated.

| Date | Commit | What was exercised | Result |
|---|---|---|---|
| 2026-10-13 | `14f4bb3d0` | `fvm flutter run -d linux` against real data: launch, library load, review session start (11 studies, 452 due, quota-capped to 87), user move in review | Pass. Owner confirmed the #93 move sound is audible — the one thing the suite structurally could not check. Closed in `docs/manual-test-log.md`. |

Not covered by that run: capture-sound distinctness, check haptics, and the
`/api/token/test` connection failure logged at startup (single observation, not
investigated — likely transient, unconfirmed).

## Recording rule

Every completed task records what shipped, dated verification evidence and any
unverified runtime checks. Follow TEST_STRATEGY; protect normative changes with
GATES's dedicated spec-change/gate-change lane rather than bundling referee
edits into product commits.
