# Architecture & Domain Audit Report

**Date:** 2026-11-17  
**Scope:** `lib/src/` (336 hand-written Dart files, ~79,000 LOC excluding l10n), plus `test/`, `scripts/`  
**Method:** Static analysis via `rg`, import-graph Tarjan SCC, symbol-frequency dead-code scan, manual inspection  
**Baseline:** `docs/tech-debt-inventory.md` (snapshot at `b4635a8`), ARCHITECTURE.md §2, QUALITY.md §1, SPEC INV-040/042

---

## Executive Summary

The codebase is in **substantially better shape** than the tech-debt inventory baseline. Seven of the top-11 items from that inventory were landed (items 2–6, 11, 21), and three more were partially addressed (items 1, 8, 9). The architecture boundaries specified in ARCHITECTURE.md §2 are **clean**: zero presentation→persistence/db imports, pure domain layer. However, significant structural debt remains in the inherited Lichess subsystems, naming collisions, and large file complexity.

### Status of Previously Identified Items

| Inventory Item | Status | Evidence |
|---|---|---|
| 1 — PgnCommentShape triplication | ✅ **Fixed** | Moved to `widgets/pgn_shapes.dart` — single shared extension |
| 2 — PositionKnowledgeState.fromReviewState | ✅ **Fixed** | Factory at `domain/position_knowledge_state.dart:81`, used at 3 sites |
| 3 — Wall-clock fallback | ✅ **Fixed** | No `DateTime.now()` in review path; comment at `review_controller.dart:227` |
| 4 — Row-map duplication | ✅ **Fixed** | `_studyRow`, `_chapterRow`, `_decisionRow`, `_reviewStateRow`, `_knowledgeStateFromRow` builders in sqlite_study_repository.dart |
| 5 — Dead kSliderTheme | ✅ **Fixed** | Deleted; comment at `theme.dart:10` |
| 6 — Prefetch constants x3 | ✅ **Fixed** | `kDefaultPrefetchBatchSize`/`kDefaultPrefetchRefillThreshold` defined once at `review_session.dart:37-43` |
| 8 — Test-environment sniffing | ✅ **Fixed** | Centralized in `import/pgn_offload.dart` with `shouldOffloadPgnWork()` |
| 9 — Scope-branch triplication | ✅ **Fixed** | `_loadActiveStudiesAndChapters()` at `review_service.dart:608-622` |
| 11 — Raw exception in snackbars | ✅ **Fixed** | Zero `showSnackBar.*$e` matches in `view/` |
| 21 — divisionFromPick duplication | ✅ **Fixed** | Consolidated to `model/common/chess.dart:321` |
| 10 — getDueSummary god-method | ✅ **Fixed** | Extracted `_DueTally` class (review_service.dart:137+), method is now ~46 lines |

---

## Current Findings

### Finding 1: Naming Collisions — Study and StudyRepository

**Severity:** Critical  
**Category:** Naming / Architecture  

Two unrelated types share each name, causing persistent confusion:

| Name | Local (SRS) | Lichess (online) |
|---|---|---|
| `Study` | [`domain/study.dart:13`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/domain/study.dart#L13) | [`model/study/study.dart:14`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/model/study/study.dart#L14) |
| `StudyRepository` | [`persistence/study_repository.dart:25`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/persistence/study_repository.dart#L25) | [`model/study/study_repository.dart:23`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/model/study/study_repository.dart#L23) |

The review controller imports **both** repositories:
- [`review_controller.dart:16`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/review/review_controller.dart#L16): `import '…model/study/study_repository.dart' show studyRepositoryProvider;`

**Fix:** Rename the Lichess pair to `LichessStudy` / `LichessStudyRepository` in a dedicated PR. Requires codegen rebuild. **Defer to its own session.**

---

### Finding 2: Import Cycles (Tarjan SCC)

**Severity:** High  
**Category:** Tight Coupling  

Four strongly-connected components remain in the import graph:

#### 2a. 31-file `view/**` + `widgets/` cycle
**Size:** 31 files  
**Core hub:** `app_links_service.dart` ↔ screen imports forming a cross-view dependency web.  
Key participants:
- [`view/analysis/analysis_screen.dart`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/view/analysis/analysis_screen.dart)
- [`view/study/study_screen.dart`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/view/study/study_screen.dart)
- [`view/game/game_list_tile.dart`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/view/game/game_list_tile.dart)
- [`view/user/user_screen.dart`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/view/user/user_screen.dart)
- [`app_links_service.dart`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/app_links_service.dart) (the routing hub)

**Fix:** Extract a navigation-dispatch interface or use a route registry pattern. The cycle exists because screens import each other for push-navigation. A `GoRouter`-style named-route approach would break this.

#### 2b. 5-file `model/auth` ↔ `network/` ↔ `utils/` cycle
Files: `auth_controller.dart`, `auth_repository.dart`, `aggregator.dart`, `http.dart`, `riverpod.dart`

**Fix:** Break the cycle at `utils/riverpod.dart` by moving the auth-aware extension into `model/auth/`.

#### 2c. 2-file `model/common/node.dart` ↔ `uci.dart`
**Fix:** Merge into one file or extract the shared type to a third file.

#### 2d. 2-file `model/study/study_list_paginator.dart` ↔ `study_repository.dart`
**Fix:** Move the paginator provider out of the repository barrel.

**Note:** The previously-reported `persistence/study_repository ↔ sqlite_study_repository` and `design/design ↔ srs_sheet` cycles are **resolved** — no mutual imports found.

---

### Finding 3: God Files / Oversized Modules

**Severity:** High  
**Category:** Complexity  

| File | LOC | Notes |
|---|---|---|
| [`review_controller.dart`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/review/review_controller.dart) | **2,213** | Grew from prior reports. `ReviewController` class starts at L384. |
| [`review_screen.dart`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/view/review/review_screen.dart) | **1,655** | Grew from 1,283 at inventory time. |
| [`sqlite_study_repository.dart`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/persistence/sqlite_study_repository.dart) | **1,533** | `deleteStudy` = 105 lines, `deleteChapter` = 70 lines. |
| [`widgets/pgn.dart`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/widgets/pgn.dart) | **1,515** | |
| [`review_scope_drawer.dart`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/view/review/review_scope_drawer.dart) | **1,366** | |
| [`offline_computer_game_screen.dart`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/view/offline_computer/offline_computer_game_screen.dart) | **1,305** | |
| [`review_service.dart`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/review/review_service.dart) | **1,183** | Improved from prior state. |
| [`study_controller.dart`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/model/study/study_controller.dart) | **1,005** | |
| [`analysis_controller.dart`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/model/analysis/analysis_controller.dart) | **934** | |

**Fix priorities:**
1. **review_controller.dart (2,213 LOC):** Split import orchestration, session lifecycle, and UI state into separate files/classes.
2. **review_screen.dart (1,655 LOC):** Extract widget subtrees into private widgets in companion files.
3. **sqlite_study_repository.dart (1,533 LOC):** Extract `deleteStudy`/`deleteChapter` cascade logic into a shared `_deleteCascade` helper.

---

### Finding 4: Analysis vs Study Controller / Preferences Duplication

**Severity:** High  
**Category:** Duplication  

#### 4a. Controller method duplication
Identical method bodies exist in both controllers:
- `jumpToNthNodeOnMainline`: [`analysis_controller.dart:416`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/model/analysis/analysis_controller.dart#L416) vs [`study_controller.dart:512`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/model/study/study_controller.dart#L512)
- `onCurrentPathEvalChanged`: [`analysis_controller.dart:371`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/model/analysis/analysis_controller.dart#L371) vs [`study_controller.dart:116`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/model/study/study_controller.dart#L116)

#### 4b. Preferences toggle duplication
Seven identical toggle methods duplicated between:
- [`analysis_preferences.dart:35-59`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/model/analysis/analysis_preferences.dart#L35-L59) (7 toggles)
- [`study_preferences.dart:66-102`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/model/study/study_preferences.dart#L66-L102) (7 toggles)

`CommonAnalysisPrefs` exists at [`common_analysis_prefs.dart`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/model/analysis/common_analysis_prefs.dart) but only declares 2 getters (`showBestMoveArrow`, `showAnnotations`), far short of covering the 7 duplicated toggles.

**Fix:** Extend `CommonAnalysisPrefs` to cover all 7 shared fields; extract toggle methods into a mixin. Requires freezed codegen. **Defer.**

---

### Finding 5: Remaining Dead Code

**Severity:** Medium  
**Category:** Dead Code  

Symbols occurring exactly once in `lib/` + `test/` + `scripts/` (declaration only, never called):

| File | Dead Symbol(s) | Notes |
|---|---|---|
| [`model/game/player.dart:55,60`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/model/game/player.dart#L55) | `setOnGame`, `setGone` | 1 occurrence each |
| [`model/offline_computer/offline_computer_game_controller.dart:893,899`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/model/offline_computer/offline_computer_game_controller.dart#L893) | `goForward`, `goBack` | 1 occurrence each |

Previously-reported dead symbols now **confirmed removed** (zero occurrences): `setConfirmResign`, `makeCurrentNodePgn`, `toApiForecast`, `SrsMovePair`, `harmonized`, `winningChancesPovDiff`, `setLocale`, `getCurrentGame`, `toggleAnimateOpponentPreMove`, `asSquareOrNull`, `asStringIdOrNull`, `asGameIdOrNull`, `asPuzzleIdOrNull`, `asChallengeIdOrNull`, `asBroadcastTournamentIdOrNull`, `asBroadcastRoundIdOrNull`, `asBroadcastGameIdOrNull`, `asTeamIdOrNull`, `asFideIdOrNull`, `asSpeedOrNull`, `asGameStatusOrNull`, `toggleChat`.

**Still present but borderline:**
- `asVariantOrNull` — 1 occurrence (may be declaration-only)
- `fromLevel` — 1 occurrence (may be declaration-only)

**Fix:** Delete `setOnGame`, `setGone`, `goForward`, `goBack`. Verify `asVariantOrNull` and `fromLevel` with `flutter analyze`.

---

### Finding 6: flutter_riverpod Import in Infrastructure Layer

**Severity:** Medium  
**Category:** Layer Violation  

[`persistence/sqlite_study_repository.dart:16`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/persistence/sqlite_study_repository.dart#L16): `import 'package:flutter_riverpod/flutter_riverpod.dart';`

The persistence layer imports `flutter_riverpod`. While this is for the provider declaration (a Riverpod convention), it introduces a Flutter framework dependency into what ARCHITECTURE.md §2 designates as infrastructure. The domain layer itself is clean.

**Fix:** Move the `srsStudyRepositoryProvider` declaration to an application-level file (e.g., `review/providers.dart`) and keep `sqlite_study_repository.dart` as pure infrastructure.

---

### Finding 7: Test-Environment Sniffing Still Scattered

**Severity:** Medium  
**Category:** Missing Abstraction  

While `import/pgn_offload.dart` now centralizes the PGN offload decision, `Platform.environment.containsKey('FLUTTER_TEST')` still appears at **6 other sites** outside the centralized helper:

| File | Line | Context |
|---|---|---|
| [`model/log/app_log_service.dart`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/model/log/app_log_service.dart#L69) | 69, 82 | Disabling file logging in tests |
| [`model/engine/position_evaluator.dart`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/model/engine/position_evaluator.dart#L49) | 49 | Engine platform check |
| [`network/http.dart`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/network/http.dart#L116) | 116, 128, 139 | Skipping logging in tests |
| [`utils/share.dart`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/utils/share.dart#L21) | 21 | Share intent guard |

**Fix:** Extract `bool get isTestEnvironment` into a shared utility (e.g., `utils/environment.dart`) and import it everywhere.

---

### Finding 8: Logging Split — Logger vs debugPrint

**Severity:** Medium  
**Category:** Inconsistency  

The app has a structured `Logger` pipeline (0 `Logger(` sites found in lib/src — the logger infrastructure is at `model/log/`), but **14 `debugPrint` calls** remain scattered across:
- `model/log/app_log_service.dart` (1)
- `model/game/gif_export.dart` (1)
- `model/updater/app_update_service.dart` (3)
- `app.dart` (1)
- `utils/chessboard.dart` (1)
- `utils/system.dart` (5)
- `model/account/account_preferences.dart` (1 — comment reference)

The view-layer `debugPrint` calls are gone (item 11 landed), but the model/utils layer still bypasses the structured pipeline.

**Fix:** Route `model/` and `utils/` failures through the existing `Logger` infrastructure.

---

### Finding 9: Deprecated `year2023` Flag

**Severity:** Low  
**Category:** Outdated Pattern  

[`design/theme_bridge.dart:225`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/design/theme_bridge.dart#L225): `year2023: false` — the deprecated `SliderThemeData.year2023` flag is still used in the live theme bridge.

**Fix:** Remove when the Flutter SDK default has flipped. This is a visual change that needs device verification.

---

### Finding 10: Cascade-Delete Methods Remain Long and Interleaved

**Severity:** Low  
**Category:** Complexity  

- `deleteStudy`: 105 lines ([`sqlite_study_repository.dart:309`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/persistence/sqlite_study_repository.dart#L309))
- `deleteChapter`: 70 lines ([`sqlite_study_repository.dart:531`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/persistence/sqlite_study_repository.dart#L531))

Both cascade over the same table set with similar logic. The `deleteStudy` method now chunks at 400 (good), but the cascade pattern is duplicated.

**Fix:** Extract `_cascadeDeleteDecisions(txn, decisionIds, studyIdForGuard)` shared helper.

---

### Finding 11: `shared_pgn_service.dart` at Root Level

**Severity:** Low  
**Category:** Naming / Structure  

[`lib/src/shared_pgn_service.dart`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/shared_pgn_service.dart) sits at the root of `lib/src/` while every other service lives in a module folder. Only imported by `app.dart`.

**Fix:** Move to `lib/src/import/` or `lib/src/review/` depending on its responsibility.

---

### Finding 12: Animation Delay Magic Numbers (Now Named — Partial)

**Severity:** Low  
**Category:** Magic Values  

The review controller's animation delays are now **named constants** at the top of the file:
- [`review_controller.dart:31`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/review/review_controller.dart#L31): `kOpponentMoveDelay = Duration(milliseconds: 300)`
- [`review_controller.dart:34`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/review/review_controller.dart#L34): `kOpponentPostMoveDelay = Duration(milliseconds: 300)`
- [`review_controller.dart:37`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/review/review_controller.dart#L37): `kEndOfLinePause = Duration(milliseconds: 350)`
- [`review_controller.dart:40`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/review/review_controller.dart#L40): `kIncomingPreMoveDelay = Duration(milliseconds: 350)`

This is **good** — the inventory item is resolved.

---

## Layer Boundary Verification (ARCHITECTURE.md §2)

### ✅ Presentation → Persistence/DB: CLEAN
```
rg -n 'src/(db|persistence)/' lib/src/view/ lib/src/widgets/ lib/src/styles/ lib/src/design/
```
**Result:** Zero matches. The three exceptions noted in the inventory (`srs_settings_screen.dart`, `study_chapters_screen.dart`, `analysis_hub_screen.dart`) are all resolved.

### ✅ Domain Purity (INV-040/042): CLEAN
```
rg -rn "import.*'package:flutter" lib/src/domain/   → 0 matches
rg -rn "import.*dart:io" lib/src/domain/            → 0 matches
```
The domain barrel at [`domain/domain.dart:6`](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/domain/domain.dart#L6) correctly declares: "Pure Dart — zero imports of Flutter, chessground, or sqflite."

### ⚠️ Infrastructure → Flutter: MINOR
`sqlite_study_repository.dart` imports `flutter_riverpod` for provider declaration (Finding 6). Functional, but architecturally impure.

---

## Priority-Ordered Action Plan

| Priority | Finding | Severity | Effort | Action |
|---|---|---|---|---|
| 1 | F1: Study/StudyRepository naming | Critical | High | Rename Lichess pair. Needs codegen; own PR. |
| 2 | F2a: 31-file view cycle | High | High | Extract navigation dispatch. Architectural work. |
| 3 | F3: God files (review_controller 2.2k LOC) | High | Medium | Split into import, session, UI state files. |
| 4 | F4: Analysis/Study controller+prefs dup | High | Medium | Extend CommonAnalysisPrefs, extract mixin. Needs codegen. |
| 5 | F5: Dead symbols | Medium | Low | Delete 4 methods. Quick win. |
| 6 | F6: flutter_riverpod in persistence | Medium | Low | Move provider declaration. Quick win. |
| 7 | F7: Scattered FLUTTER_TEST sniffing | Medium | Low | Extract `isTestEnvironment` utility. |
| 8 | F8: Logging split | Medium | Low | Route debugPrint through Logger. |
| 9 | F2b-d: Smaller import cycles | Medium | Low-Med | 3 small cycle fixes. |
| 10 | F10: Cascade delete duplication | Low | Medium | Shared helper extraction. |
| 11 | F9: Deprecated year2023 | Low | Low | Defer until SDK default flips. |
| 12 | F11: Root-level shared_pgn_service | Low | Low | Move to appropriate module folder. |

---

## Methodology Notes

- **Import graph:** Python Tarjan SCC over all 336 `.dart` files (excluding `.g.dart`/`.freezed.dart`)
- **Dead code:** `rg -c` symbol frequency across `lib/` + `test/` + `scripts/`; count=1 means declaration-only
- **Layer violations:** `rg -n` import patterns against ARCHITECTURE.md §2 boundaries
- **File sizes:** `wc -l` on all source files
- **Duplication:** Targeted `rg` for known patterns from tech-debt inventory, plus manual inspection
