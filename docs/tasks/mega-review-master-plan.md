# ChessSRS 8-Dimension Mega-Review — Master Plan & Roadmap

**Date:** 2026-11-17  
**Repository:** `cassandre60/ChessSRS`  
**Scope:** Synthesis of 8 specialized engineering audits covering Architecture, Performance, Test Quality, UX & Design System, Security & Data Integrity, DevOps & CI/CD, Chess/SRS Domain Logic, and Documentation & Knowledge Management.

---

## 1. Audit Reports Index

| # | Dimension | Report File | Key Findings Summary |
|---|---|---|---|
| 1 | **Architecture & Domain** | [`mega-review-architecture-audit.md`](mega-review-architecture-audit.md) | 0 layer/purity violations; 11 of 23 historical tech-debt items verified fixed; 4 remaining areas: `Study`/`StudyRepository` naming collisions, 4 import cycles (including 31-file `view/**` SCC), god files (`review_controller.dart` 2,213 LOC, `review_screen.dart` 1,655 LOC), and controller/preferences duplication |
| 2 | **Performance & Scalability** | [`mega-review-performance-analysis.md`](mega-review-performance-analysis.md) | 13 findings across session start, 16 ms move response path, SQLite queries, memory churn, widget rebuilds, PGN import, and lazy loading (7 Quick wins, 4 Medium effort, 1 Major refactor) |
| 3 | **Test Quality & Coverage** | [`mega-review-test-quality-audit.md`](mega-review-test-quality-audit.md) | 190 test files across 299 `lib/src/` files; 0 flakiness risks (deterministic clocks/seeds); 45/45 SPEC invariants traced; gaps in `view/` widget coverage (45%) and property-based invariant fuzzing |
| 4 | **UX & Design System** | [`mega-review-ux-design-audit.md`](mega-review-ux-design-audit.md) | Strong Diagram token compliance in `lib/src/view/review/`; 4 High and 6 Medium polish items: residual Material `TextButton`/`IconButton` in banners, hardcoded `lineFontSize`, responsive wide `SrsText.note` token, and 44 px vs 48 px touch target constants |
| 5 | **Security & Data Integrity** | [`mega-review-security-audit.md`](mega-review-security-audit.md) | 0 Critical, 1 High (accepted upstream query-string fallback in SPEC INV-006), 4 Medium, 5 Low; 100% parameterized SQLite queries, transactional critical writes, WAL + FK enabled; hardening opportunities in in-memory `AppLogService` redaction and `saveChapters` transaction wrapping |
| 6 | **DevOps & CI/CD** | [`mega-review-devops-audit.md`](mega-review-devops-audit.md) | 0 Critical, 3 High, 8 Medium; strong trusted-base gate execution and docs-only fast lane; opportunities in `~/.pub-cache` caching, `.fvmrc` in `build_runner` cache key, `release-proof.yml` codegen cache, and `.gates/protected-paths.txt` coverage |
| 7 | **Chess & SRS Domain** | [`mega-review-chess-srs-domain-audit.md`](mega-review-chess-srs-domain-audit.md) | FSRS-4.5 binary DSR math and graph-aware contagion/exposure/sibling coupling verified exact against `ChessSRS Scheduling Architecture.md`; 1 Medium fix for castling UCI normalization (`e1h1` vs `e1g1`) in `canonicalKeyForPosition` |
| 8 | **Documentation & Knowledge** | [`mega-review-documentation-audit.md`](mega-review-documentation-audit.md) | 158 `.md` files audited; authority map (`AGENTS.md §1`) verified sound; fixed broken D020 reference, added redirect banners to 7 shadow docs in `docs/`, and modernized `docs/setting_dev_env.md` |

---

## 2. Prioritized Execution Roadmap

### Wave 1 — Immediate Non-Protected Code, Test & Documentation Improvements (Active PRs)

Every item in Wave 1 respects `AGENTS.md §10` and `.gates/protected-paths.txt` (zero unapproved referee/spec edits) and is delivered in an isolated branch/worktree:

| Stream | Scope & Deliverables | Target Files | Status |
|---|---|---|---|
| **W1-Docs** | Add all 8 mega-review reports + this master plan; fix broken D020 link in `docs/decisions.md`; add authoritative redirect banners to 7 shadow docs in `docs/`; add ChessSRS Quick Start to `docs/setting_dev_env.md` | `docs/tasks/mega-review-*.md`, `docs/decisions.md`, `docs/tasks/README.md`, `docs/setting_dev_env.md`, 7 shadow docs | In Progress |
| **W1-Perf** | Eliminate `session.exposureThrottle` full-map copy on every `submitMove`/`retryMove` (2-A/4-C); eliminate 31K intermediate `TallyDecision` allocation in `loadSessionAndSummary` (1-C); optimize `_DueTally` map pre-allocation (4-A) and `_loadReviewData` query ID set construction (4-B) | `lib/src/domain/graph_aware_review_coordinator.dart`, `lib/src/domain/review/review_session.dart`, `lib/src/review/review_service.dart` | In Progress |
| **W1-Domain & Persistence** | Normalize king-takes-rook vs standard castling UCI (`e1h1` → `e1g1`) in `canonicalKeyForPosition` and `canonicalKey` (POS-03, INV-016/033); wrap `saveChapters` in `_db.transaction` (L-1); batch `deleteChapter` canonical ID cleanup in 400-item chunks (3-D, INV-004/051); document `review_engine.dart`, `ids.dart`, `transpose_scope.dart` | `lib/src/domain/position_knowledge_state.dart`, `lib/src/persistence/sqlite_study_repository.dart`, `lib/src/domain/review/review_engine.dart`, `lib/src/domain/ids.dart`, `lib/src/domain/review/transpose_scope.dart` | In Progress |
| **W1-UX & Design** | Replace Material `TextButton`/`IconButton` leaks in `_UnlockBranchBanner` and `DynamicFreezeBanner` with Diagram `SrsTextButton`/`SrsPressable` (H2); use `SrsText.lineSize` token (M2); add responsive `wide` support to `SrsText.note` (H4); align `SrsSwitch` and `_kAccentDotTarget` hit boxes to `SrsLayout.minTouchTarget` = 48 px (M3/M4, INV-062) | `lib/src/design/tokens.dart`, `lib/src/design/primitives.dart`, `lib/src/view/review/review_screen.dart` | In Progress |
| **W1-Architecture** | Remove verified dead methods in `player.dart` (`setOnGame`, `setGone`) and `offline_computer_game_controller.dart` (`goForward`, `goBack`) (F5); break `study_list_paginator.dart` ↔ `study_repository.dart` import cycle (F2d) and `utils/riverpod.dart` cycle (F2b) | `lib/src/model/game/player.dart`, `lib/src/model/offline_computer/offline_computer_game_controller.dart`, `lib/src/model/study/*`, `lib/src/utils/riverpod.dart` | In Progress |
| **W1-Tests** | Add deterministically seeded property-based test suites for 4-field FEN & canonical key permutation/castling invariance (`INV-015/016/017/033`), PGN export→import round-trip fidelity (`INV-003/010/012/014`), and graph contagion + fresh-cap partitioning (`INV-027/028/029/068`) | `test/domain/position_identity_properties_test.dart`, `test/import/pgn_roundtrip_properties_test.dart`, `test/domain/contagion_and_fresh_cap_properties_test.dart` | In Progress |
| **W1-Security** | Apply `redactLogText` to in-memory `AppLogService` `_logs` buffer so sensitive parameters (`email`, `username`, `code`, bearer tokens) never sit unredacted in memory for the log viewer/export (L-3, INV-006); expand unit test coverage | `lib/src/model/log/app_log_service.dart`, `lib/src/utils/log_redaction.dart`, `test/utils/log_redaction_test.dart` | In Progress |

---

### Wave 2 — Protected-Path Proposals (Require Explicit Owner Consent per `AGENTS.md §10`)

Per `GATES.md` and `AGENTS.md §10`, edits to `.github/workflows/*`, `.gates/*`, `SPEC.md`, `GATES.md`, and `pubspec.yaml` must run in dedicated `gate-change` or `spec-change` PRs after explicit per-item owner approval:

1. **CI & Gate Hardening (`gate-change` lane)**:
   - Add `actions/cache@v4` for `~/.pub-cache` in `.github/workflows/test.yml` (saves 15–30 s per CI run).
   - Include `hashFiles('.fvmrc')` in the `build_runner` cache key in `.github/workflows/test.yml` so Flutter SDK bumps never restore stale generated code.
   - Add `build_runner` caching to `.github/workflows/release-proof.yml`.
   - Add `pubspec.lock` and `build.yaml` to `.gates/protected-paths.txt` (G07).
   - Reconcile `GATES.md` line 17–18 prose with §Operator checklist item 2 (merge queue availability note).
2. **Open SPEC Owner Decisions (`docs/open-questions.md`)**:
   - **Q7 (INV-060)**: Settle `"repertoire move"` vs `"study move"` in screen-reader lapse announcement.
   - **Q8**: Settle `parseUtcIso` fast-path out-of-range calendar rollover vs `FormatException`.
   - **Q12 (INV-050 vs QUALITY §4.1)**: Settle 16 ms budget scope (validation/lookup vs full durable persistence on reference device).
   - **Q13 (INV-025)**: Settle `ChessFsrsScheduler` preserving `repetitionCount` on lapse vs universal streak-reset wording.
   - **Q14 (INV-068)**: Settle legacy non-null `ReviewState` with `nextDueAt == null` counting as due.

---

### Wave 3 — Medium/Long-Term Structural Refactorings

1. **Disambiguate Lichess vs Domain `Study` / `StudyRepository` Names (Arch F1)**:
   - Rename `lib/src/model/study/study.dart` (`Study` → `LichessStudy`) and `lib/src/model/study/study_repository.dart` (`StudyRepository` → `LichessStudyRepository`) to eliminate the 11 `as domain` import aliases across `lib/src/review/` and `lib/src/view/`.
2. **Decompose God Files (Arch F3 & Perf 5-B)**:
   - Split `lib/src/review/review_controller.dart` (2,213 LOC) into focused collaborators (`ReviewImportCoordinator`, `ReviewScopeCoordinator`, `ReviewPracticeExplorer`).
   - Split `lib/src/view/review/review_screen.dart` (1,655 LOC) into sub-files (`review_board_area.dart`, `review_feedback_tray.dart`, `review_banners.dart`, `review_idle_views.dart`) with targeted `ConsumerWidget` leaves.
3. **Break the 31-File `view/**` Import Cycle (Arch F2a)**:
   - Extract route builders or shared navigation callbacks so feature screens (`analysis_screen.dart`, `study_screen.dart`, `game_screen.dart`, `settings_screen.dart`) do not form a single strongly connected component.
4. **Lazy `treeJson` Loading & `inScope` Node Index Optimization (Perf 7-D & 1-D)**:
   - Exclude `treeJson` (~34 MB across 312 chapters) from read-only chapter metadata queries (`SELECT id, studyId, title, ...` without `treeJson`), loading trees on demand via `getChapterById`.
   - Replace startup `getNodeIndex` 71K-row full table scan with on-demand SQL lookup by `fenKey` or lazily populated index when `transposeScope == TransposeScope.inScope`.
