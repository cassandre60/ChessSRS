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
| **W1-Docs** | Add all 8 mega-review reports + this master plan; fix broken D020 link in `docs/decisions.md`; add authoritative redirect banners to 7 shadow docs in `docs/`; add ChessSRS Quick Start to `docs/setting_dev_env.md`; add `docs/troubleshooting.md` and ADRs D021–D023 | `docs/tasks/mega-review-*.md`, `docs/decisions.md`, `docs/tasks/README.md`, `docs/setting_dev_env.md`, `docs/troubleshooting.md`, 7 shadow docs | **PR #798** |
| **W1-Perf** | Eliminate `session.exposureThrottle` full-map copy on every `submitMove`/`retryMove` (2-A/4-C); eliminate 31K intermediate `TallyDecision` allocation in `loadSessionAndSummary` (1-C); optimize `_DueTally` map pre-allocation (4-A) and `_loadReviewData` query ID set construction (4-B) | `lib/src/domain/graph_aware_review_coordinator.dart`, `lib/src/domain/review/review_session.dart`, `lib/src/review/review_service.dart` | **PR #801** |
| **W1-Security** | Apply `redactLogText` / `redactLogRecord` to in-memory `AppLogService` `_logs` buffer so sensitive parameters (`email`, `username`, `code`, bearer tokens, OAuth PKCE params) never sit unredacted in memory for the log viewer/export (L-3, INV-006); expand unit test coverage | `lib/src/model/log/app_log_service.dart`, `lib/src/utils/log_redaction.dart`, `test/utils/log_redaction_test.dart`, `test/model/log/app_log_redaction_test.dart` | **PR #802** |
| **W1-Tests** | Add deterministically seeded property-based test suites for 4-field FEN & canonical key permutation/castling invariance (`INV-015/016/017/033`), PGN export→import round-trip fidelity (`INV-003/010/012/014`), graph contagion + fresh-cap partitioning (`INV-027/028/029/068`), plus dedicated unit suites for `fresh_introduction_order.dart` and `srs_settings_providers.dart` | `test/domain/position_identity_properties_test.dart`, `test/import/pgn_roundtrip_properties_test.dart`, `test/domain/contagion_and_fresh_cap_properties_test.dart`, `test/domain/fresh_introduction_order_test.dart`, `test/view/review/srs_settings_providers_test.dart` | **PR #803** |
| **W1-ECO & DX** | Expand `ecoToOpeningFamily` in `lib/src/import/opening_name.dart` to full 500-code (`A00–E99`) FIDE ECO coverage satisfying `isLikelyOpeningFamily` (`INV-067`); fix POSIX trailing newline in `scripts/dev_run.sh` | `lib/src/import/opening_name.dart`, `test/import/opening_name_test.dart`, `scripts/dev_run.sh` | **PR #804** |
| **W1-UX & Design** | Replace Material `TextButton`/`IconButton` leaks in `_UnlockBranchBanner` and `DynamicFreezeBanner` with Diagram `SrsTextButton`/`SrsPressable` (H2); use `SrsText.lineSize` token (M2); add responsive `wide` support to `SrsText.note` (H4); align `SrsSwitch` and `_kAccentDotTarget` hit boxes to `SrsLayout.minTouchTarget` = 48 px (M3/M4, INV-062) | `lib/src/design/tokens.dart`, `lib/src/design/primitives.dart`, `lib/src/view/review/review_screen.dart` | **PR #805** |
| **W1-Domain & Persistence** | Normalize king-takes-rook vs standard castling UCI (`e1h1` → `e1g1`) in `canonicalKeyForPosition` and `canonicalKey` (POS-03, INV-016/033); wrap `saveChapters` in `_db.transaction` (L-1); batch `deleteChapter` canonical ID cleanup in 400-item chunks (3-D, INV-004/051); add `kMaxPgnVariationDepth = 512` recursion depth guard in `pgn_importer.dart` (L-5 / EDGE-01, INV-011); document `review_engine.dart`, `ids.dart`, `transpose_scope.dart` | `lib/src/domain/position_knowledge_state.dart`, `lib/src/persistence/sqlite_study_repository.dart`, `lib/src/import/pgn_importer.dart`, `lib/src/domain/review/review_engine.dart`, `lib/src/domain/ids.dart`, `lib/src/domain/review/transpose_scope.dart` | **PR #806** |
| **W1-Architecture** | Remove verified dead methods in `player.dart` (`setOnGame`, `setGone`) and `offline_computer_game_controller.dart` (`goForward`, `goBack`) (F5); break `study_list_paginator.dart` ↔ `study_repository.dart` import cycle (F2d) and `utils/riverpod.dart` cycle (F2b) | `lib/src/model/game/player.dart`, `lib/src/model/offline_computer/offline_computer_game_controller.dart`, `lib/src/model/study/*`, `lib/src/utils/riverpod.dart` | **PR #807** |
| **W2-Perf/Domain Properties** | Add deterministically seeded property-based tests for `fast_date_parser.dart` (`parseUtcIso` fast-path vs `DateTime.parse`), `json_adapters.dart` round-trip fidelity, and `SimpleScheduler`, `EaseScalingScheduler`, and `ChessFsrsScheduler` algebraic invariants (`INV-024/025/026`) | `test/persistence/fast_date_parser_properties_test.dart`, `test/persistence/json_adapters_properties_test.dart`, `test/domain/scheduler_properties_test.dart` | **PR #808** |
| **W2-Mutant Killers** | Kill surviving boundary and security mutants in `AppLinksService` (`INV-008`), `AuthController` (`INV-006/007`), and `pgn_offload.dart` | `test/app_links_service_test.dart`, `test/model/auth/auth_controller_test.dart`, `test/import/pgn_offload_test.dart` | **PR #809** |

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

---

## 3. Delivered PRs & Created GitHub Issues Ledger

### 3.1 Pull Requests Opened (Wave 1 & Wave 2)

| PR | Branch | Summary | Verification |
|---|---|---|---|
| [#798](https://github.com/cassandre60/ChessSRS/pull/798) | `docs/mega-review-audit-and-plan` | Master Plan, 8-Dimension Audit Reports, Developer Troubleshooting Guide (`docs/troubleshooting.md`), ADRs D021–D023, Shadow-Doc Redirects, Dev Quick-Start | `./scripts/gates.sh t1` (`t1 ok`), CI docs-only fast lane |
| [#801](https://github.com/cassandre60/ChessSRS/pull/801) | `perf/review-session-and-move-hotpaths` | O(1) `exposureTimeFor` on 16 ms move critical path (`INV-050`, `INV-028`), eliminate 31K `TallyDecision` allocation, optimize `_DueTally` and `_loadReviewData` | 63/63 tests passed (`move_latency_test.dart` median 2.97 ms), `t1 ok` |
| [#802](https://github.com/cassandre60/ChessSRS/pull/802) | `fix/security-in-memory-log-redaction` | In-memory `AppLogService` `redactLogRecord` hardening + OAuth PKCE & Bearer token redaction (`INV-006`) | 24/24 tests passed, `t1 ok` |
| [#803](https://github.com/cassandre60/ChessSRS/pull/803) | `test/property-oracles-and-roundtrip` | Property-based test suites for FEN/canonical key invariance, PGN round-trip fidelity, graph contagion & fresh caps + unit suites for `fresh_introduction_order` & `srs_settings_providers` | 48/48 tests passed, `t1 ok` |
| [#804](https://github.com/cassandre60/ChessSRS/pull/804) | `feat/eco-coverage-and-dx-polish` | Full 500-code (`A00–E99`) FIDE ECO opening family coverage (`INV-067`) + POSIX trailing newline in `scripts/dev_run.sh` | 45/45 tests passed, `t1 ok` |
| [#805](https://github.com/cassandre60/ChessSRS/pull/805) | `fix/ux-diagram-tokens-and-a11y` | Diagram `SrsTextButton`/`SrsPressable` in review banners, `SrsText.lineSize` & responsive `SrsText.note(wide:)`, 48 px touch targets (`INV-062`), scoped `boardPreferencesProvider` watch | 93/93 tests passed, `t1 ok` |
| [#806](https://github.com/cassandre60/ChessSRS/pull/806) | `fix/domain-castling-key-and-persistence-tx` | Castling UCI normalization in `canonicalKeyForPosition` (`INV-016/033`), atomic `saveChapters` transaction, 400-item chunked `deleteChapter` cleanup (`INV-004/051`), 512-ply PGN recursion guard (`INV-011`), domain API doc comments | 269/269 tests passed, `t1 ok` |
| [#807](https://github.com/cassandre60/ChessSRS/pull/807) | `refactor/arch-cycles-and-dead-code` | Remove dead methods in `player.dart` & `offline_computer_game_controller.dart`; break `study_list_paginator.dart` ↔ `study_repository.dart` and `utils/riverpod.dart` ↔ `auth_controller.dart` import cycles | 34/34 tests passed, `t1 ok` |
| [#808](https://github.com/cassandre60/ChessSRS/pull/808) | `test/perf-parser-and-scheduler-properties` | Property-based tests for `fast_date_parser.dart` (`parseUtcIso`), `json_adapters.dart` round-trip fidelity, and SRS schedulers (`INV-024/025/026`) | 29/29 tests passed, `t1 ok` |
| [#809](https://github.com/cassandre60/ChessSRS/pull/809) | `test/security-and-import-mutant-killers` | Kill surviving mutants in `AppLinksService` (`INV-008`), `AuthController` (`INV-006/007`), and `pgn_offload.dart` | 58/58 tests passed, `t1 ok` |

### 3.2 GitHub Issues Created (Multi-PR & Protected-Lane Backlog)

| Issue | Title & Scope |
|---|---|
| [#795](https://github.com/cassandre60/ChessSRS/issues/795) | `[gate-change] CI caching improvements & protected-paths hardening (C1–C4, G1–G2)` — Ready-to-apply YAML/config diffs for `~/.pub-cache`, `.fvmrc` in `build_runner` cache key, `release-proof.yml` cache, and `.gates/protected-paths.txt` |
| [#796](https://github.com/cassandre60/ChessSRS/issues/796) | `[arch] Resolve Study/StudyRepository naming collisions, break view/** import cycle, and split god files (F1–F3)` |
| [#797](https://github.com/cassandre60/ChessSRS/issues/797) | `[perf] Lazy treeJson loading (~34 MB heap reduction) & inScope node-index strategy (Findings 7-D, 1-D)` |
| [#799](https://github.com/cassandre60/ChessSRS/issues/799) | `[ux/a11y] Diagram sound/haptics wiring, crossfade route transitions, and textScaler support (H1, H3, H5, M5, M7)` |
| [#800](https://github.com/cassandre60/ChessSRS/issues/800) | `[test] Mutation campaigns for core SRS files and full-stack integration journeys 3–5` |
