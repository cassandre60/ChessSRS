# Verification & Testing Strategy

This document defines **how the invariants and properties in `QUALITY.md`
are mechanically proven** through automated tests, static analysis, quality
gates — and mandatory runtime validation.

> Adapted to the Lichess Mobile foundation (Phase 1+). Test file paths will be
> re-established as the new suite is built; the *enforcement matrix* below is
> the durable contract. Legacy tests (`legacy/pre-reset`) are contract
> references — mine them for intended behavior, translate valuable cases,
> never copy tests that only encode the old architecture.

---

## 1. Quality Invariant Enforcement Matrix

| Invariant / Property in `QUALITY.md` | Enforcement Mechanism | Test Target |
|---|---|---|
| **Layer Independence & Clean Architecture** | Static analysis (`fvm flutter analyze`, zero warnings) + import-boundary gate G03 (`.gates/banned-apis.json`) + in-suite boundary test | whole project; the domain layer is `lib/src/domain/`; boundary test is `test/gates/domain_boundary_test.dart` |
| **Single Chess Representation (dartchess only)** | Dependency review + analyzer import linting | `pubspec.yaml`, domain & application code |
| **Legal Move Validation & SAN/UCI** | dartchess itself (already upstream-tested); our adapter unit tests | `test/import/pgn_importer_test.dart` |
| **PGN Multi-game & Variation Preservation** | Unit tests of import pipeline (dartchess `PgnParser` → Study/Chapter/tree) | `test/import/pgn_importer_test.dart` |
| **Study Tree Normalization & Error Reporting** | Integration tests incl. malformed-PGN quarantine | `test/import/pgn_importer_test.dart`, `test/import/chapter_orientation_test.dart` |
| **SRS Interval Growth & Lapse Recovery** | Deterministic unit tests with injected `Clock` + clock rule in G03 (no `DateTime.now` in scheduling/review paths) | `test/domain/scheduler_test.dart`, `test/domain/chess_fsrs_scheduler_test.dart`, `test/gates/domain_boundary_test.dart` |
| **Repertoire Answer Validation & Persistence** | Service tests over repository (in-memory + sqflite) | `test/review/review_service_test.dart` |
| **Auto-Traversal & No Permanent Exclusion** | Deterministic engine tests (fixed clock) | `test/review/review_engine_test.dart` |
| **Review Scene Rendering & Interaction** | Widget tests using Lichess `test_helpers.dart` board helpers | `test/view/review/review_screen_test.dart` |
| **Incremental Persistence** | Repository tests asserting write scope | `test/persistence/sqlite_study_repository_test.dart` |
| **Move Validation Latency (< 16 ms, §4.1)** | Wall-clock assertion on the median of a graded-move batch, sample list printed on failure | `test/review/move_latency_test.dart` |
| **Spec-to-Test Traceability (SPEC.md)** | Every `INV-xxx` cited by at least one test; tests cite only real IDs (gate G05) | `SPEC.md` ↔ `test/` suites via SPEC coverage comments |
| **No Unreachable Source** | Import/export graph walk from `lib/main.dart`; new unreachable files fail, ratcheted against a baseline | `test/reachability/reachability_test.dart` |
| **Complete Mandatory Quality Gate** | Executable script | `verify` |

## 2. Test Suite Organization (target)

```text
test/
├── domain/          # pure Dart: entities, scheduler, review engine (no Flutter)
├── import/          # PGN → study normalization, variation preservation, errors
├── persistence/     # sqflite store (sqflite_common_ffi in CI), durability
├── review/          # review session engine + provider-level tests
└── view/            # review scene widget tests (board helpers, feedback states)
```

New tests are written **with the contract** (test-first or test-with) per the
development loop in `AGENTS.md`.

## 3. Verification Levels

### Level 1: Targeted Brick Check
During development of a specific function or contract, run only the targeted
test file:
```bash
fvm flutter test test/domain/scheduler_test.dart
```

### Level 2: Full Local Quality Gate (`./verify`)
Before committing or marking a task complete:
```bash
./verify
```
executing `fvm flutter analyze` (zero warnings) + `fvm flutter test`.

### Level 3: Runtime Validation (MANDATORY for user-visible work)
Automated green is **not** evidence of a working app (this project has been
burned by exactly that before). For every user-visible milestone:
1. `./verify` passes.
2. `fvm flutter run -d linux` (or attached device) and manually exercise the
   affected feature.
3. Visually inspect the UI (screenshots for UI work).
4. Only then record the milestone complete in `IMPLEMENTATION_PLAN.md`.

### Level 4: Continuous Integration
GitHub Actions runs `./verify` on every PR and push to `main` in a clean
environment.
