# Session Handoff — Current Status & Remaining Tasks

**Date:** 2026-10-16  
**Repository:** `cassandre60/ChessSRS`  
**Current HEAD:** `a3d75b8a5` (up to date with `origin/main`)  
**Build Status:** Verified green (`fvm flutter analyze` zero warnings; `t1 ok`; CI `Tests` passed).

---

## 1. What Landed in This Session

### A. Move-Based Opening Classification (`IMPORT-BUG-42` — PR #152)
- **Problem**: Opening hubs were created exclusively from PGN headers (`[Opening]`, `[Event]`, `[ECO]`). Studies with `[Opening "?"]`, custom FEN setups, or titles merely mentioning openings (`[Event "White vs French"]`) either failed to classify or created spurious/duplicate hubs (e.g. UK "French Defence" vs US "French Defense").
- **Solution**:
  - Implemented `detectOpeningFamilyFromMoves` and `detectOpeningFamilyFromFen` in `lib/src/import/opening_name.dart`. When metadata headers are missing or non-standard, the importer inspects initial game tree moves (`1. e4 e6` $\to$ French Defense, `1. e4 c5` $\to$ Sicilian Defense, etc.) and custom FEN setups.
  - Implemented `normalizeOpeningFamily` to unify UK/US spellings across import and scope filtering (`ReviewScope.matches`).
  - Verified against real French study fixtures (`test_fixtures/lichess_study_white-vs-french_by_MansourMohamed_2024.04.09.pgn`).

### B. Dynamic Repertoire Branch Selection (`FEAT-REP-43` — PR #156)
- **Problem**: When importing an opening study containing multiple candidate moves for the player (e.g. `3. Nc3`, `3. e5`, and `3. Nd2` vs French), all moves were previously scheduled as active cards, causing interference and review fatigue.
- **Solution**:
  - Added `dynamicRepertoireMode` toggle in `StudyPrefs` (with per-study and per-opening overrides).
  - In Dynamic Repertoire Mode, all candidate moves in the encyclopedia are valid, but only lines the player actively chooses are scheduled.
  - Unchosen alternative branches remain dormant reference material: excluded from due and fresh card tallies. When the chosen line is mastered, the review queue correctly reads **0 due, 0 new**.
  - **Database schema v19**: Added `srs_unlocked_decision` table with cascading foreign keys to track unlocked decisions.
  - **Practice Mode Opt-in**: Rehearsing in Practice Mode (`ReviewMode.practice`) remains zero-stakes. When playing an unactivated branch, a non-intrusive banner appears:
    `New branch played: <san>. Add to review queue? [Add to SRS]`
    Tapping "Add to SRS" unlocks that branch and its descendants into the active review queue.

### C. Session-Start & Review Path Performance (`PERF-FIX-44` — PR #158)
- **Problem**: Whole-library review start on large repertoires (31,182 decisions across 61 active studies) suffered from 61 sequential SQLite round-trips for chapters, JSON move parsing overhead across 31k decisions, and redundant multi-pass queue filtering.
- **Solution**:
  - **Batch Chapter Loading**: Added `getChaptersByStudyIds` and `getAllChapters` to `StudyRepository` and `SqliteStudyRepository`, collapsing 61 serial queries in `_loadActiveStudiesAndChapters` into a single batch query.
  - **Fast Move Decoding**: Implemented allocation-free fast path in `decodeExpectedMoves` for standard single moves (`[{"from":"..","to":"..","san":".."}]`), covering ~88% of rows in SQLite. Reduced `getAllDecisions` mapper time from **195.34 ms** to **142.13 ms** (27% faster) and `getDueSummary()` total from **208.89 ms** to **162.89 ms**.
  - **Query Deduplication**: Forwarded `preloadedUnlockedDecisionIds` through `loadSessionAndSummary` to prevent duplicate `getUnlockedDecisionIds` SQLite queries.
  - **Single-Pass Queue Partitioning**: In `ReviewSession`, partitioned `dueBucket` and `freshBucket` in the primary filtering loop, eliminating duplicate multi-pass queue traversals and tens of thousands of redundant status lookups.

### D. Targeted Scope Decision Queries & SQL-Level Orientation Filtering (`PERF-FIX-45` — PR #172)
- **Problem**: Side and opening scopes previously loaded and parsed all 31,182 decisions across all studies before filtering in Dart, and side scopes loaded chapter tree JSON for both White and Black chapters before discarding the inactive colour.
- **Solution**:
  - **Targeted Decision Query**: Added `getDecisionsByChapters(chapterIds)` to `StudyRepository` and `SqliteStudyRepository` with 400-item chunking. Updated `_getSideDecisions` and `_getOpeningDecisions` in `ReviewService` to query matching in-scope chapters directly, dropping opening scope decision loading from ~142 ms to ~2 ms.
  - **SQL-Level Chapter Orientation Filter**: Added optional `Side? side` parameter to `getChaptersByStudy` and `getChaptersByStudyIds`. When training White, 142 Black chapters (8.6 MB of JSON) are filtered at the SQL level and never parsed into memory.
  - **Deterministic Ordering**: Preserved study and chapter input ordering across chunked batch results.
  - **Measured**: Whole-library White session start dropped from **1,086 ms** to **569 ms** (~48% faster).

### E. Lazy Chapter Tree Deserialization & On-Demand Indexing (`PERF-FIX-46` — PR #175)
- **Problem**: In-scope chapters still parsed and allocated deep `RepertoireNode` trees from multi-megabyte `treeJson` strings during SQLite row mapping, and `ReviewSession` eagerly indexed all 39k+ nodes across all chapters even though only ~24 chapters held due cards.
- **Solution**:
  - **Lazy Chapter Tree Parsing**: Added `rootResolver` closure support to `Chapter`. `SqliteStudyRepository._chapterFromRow` supplies a lazy closure instead of eagerly decoding megabytes of `treeJson` during row mapping, completely skipping JSON decoding on unused chapters.
  - **On-Demand Session Indexing**: `ReviewSession` indexes only chapters holding active queue decisions on startup. Inactive chapters (~146 chapters / ~10 MB JSON in whole-library review) are not parsed or indexed at startup. If an off-book move triggers transposition search (`_findTransposedNode`), remaining chapters are indexed on demand.
  - **Preserved Invariants & Tests**: Passed all 46 `ReviewSession` engine tests, 21 `ReviewService` tests, and 60 `ReviewController` tests.

### F. Cold-Start Pre-warming & Flash Elimination (`PERF-FIX-47` — PR #181)
- **Problem**: Cold app startup caused a momentary flash of `_NoStudiesView` ("Bring your study" / empty screen) because `ReviewController.build()` prematurely returned a dummy `ReviewScreenState(studies: [])` on Frame 0 before SQLite opened, and database initialization was deferred until `ReviewScreen` mounted.
- **Solution**:
  - **Splash Pre-warming**: Eagerly prewarm `srsStudyRepositoryProvider` and `reviewControllerProvider` in `AppInitializationScreen` during the native splash screen, overlapping database initialization with device memory and disk checks.
  - **Loading Fencing**: In `ReviewController.build()`, awaited `srsStudyRepositoryProvider.future` directly. The controller remains in `AsyncLoading` until the repository is ready, transitioning directly to the loaded board with zero empty-state flicker.
  - **Pinned by SPEC INV-032**: Added test in `test/review/review_controller_test.dart` asserting that `ReviewController` stays loading while the repository initializes and never emits a premature empty state.

---

## 2. Next Tasks in Queue

The remaining work is organized into two active priorities:

### Priority 1: Performance Mandate (`docs/performance-handoff.md`)
- **Owner mandate** (`docs/open-questions.md` Q1): *"Everything in the app needs to be as fast as possible."*
- **Status**:
  - Whole-library White session start is down from >1,080 ms to **569 ms**, and single study start is **44 ms**.
  - Cold-start session pre-warming and empty-state flash elimination landed (PR #181).
- **Session Lifecycle & Memory Profile**:
  - `ReviewSession` is an isolated domain state machine with zero persistent timers or stream subscriptions.
  - Scope switching cleanly deallocates previous session instances and their node indexes for garbage collection.
  - On-demand chapter tree parsing deferral keeps heap overhead bounded (~20–35 MB on 31k-decision libraries).

### Priority 2: Product Backlog (`IMPLEMENTATION_PLAN.md`)
1. **`F-MOBILELOGIN`** (Awaiting real device verification):
   - Desktop sign-in (loopback OAuth) is verified working against production `lichess.org`.
   - Verify email-code sign-in on a physical Android or iOS device against production `lichess.org` (cannot be tested in desktop dev environment).
2. **`P-EXPORT-ALL`** (Full backup export — deferred to Post-MVP):
   - Single-study/chapter PGN export is already built and working (Milestone R11).
   - Full export bundles every study (PGN with variations/comments/orientation per INV-014) plus SRS state (`srs_review_state`, `position_knowledge_state`, `srs_review_event`) into a local export file with a restore path.
   - Deferred until review core and beta testing are finalized.

---

## 3. Critical Rules for the Next Agent

1. **Worktree Isolation**:
   - Always create a dedicated worktree and branch:
     ```bash
     git worktree add ../chesssrs-<slug> -b <type>/<area>-<slug> origin/main
     cd ../chesssrs-<slug>
     fvm flutter pub get
     fvm dart run build_runner build --delete-conflicting-outputs
     ```
2. **Code Generation Quirk (Freezed & JSON)**:
   - Generated files (`*.freezed.dart`, `*.g.dart`) are `.gitignore`d.
   - Whenever modifying data models or preferences, run:
     ```bash
     fvm dart run build_runner build --delete-conflicting-outputs
     ```
   - **Crucial**: After pulling or merging changes into the primary checkout, run `build_runner` or `fvm flutter build linux --debug` locally before declaring the task done, to ensure local generated files match the committed models.
3. **Local Test Budget**:
   - Iterate with `fvm flutter test <file> --plain-name '<test name>'`.
   - Never run full-suite `./verify` locally (the full 1,800+ test suite is CI's job).
   - Run `fvm flutter analyze` on touched files after the last edit.
4. **Quality Gates**:
   - Run `BASE_REF=origin/main ./scripts/gates.sh t1` **after committing** (diff-based gates read `origin/main...HEAD`).
   - Zero test-weakening patterns (G08).
   - Respect domain LOC and dependency ratchets (G10).
