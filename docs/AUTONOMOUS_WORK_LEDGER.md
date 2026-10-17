# Autonomous Work Ledger
*The Canonical Record of Completed Audits, Mutations, and Invariant Verifications*

> **Deduplication Rule for Agents:**
> Before picking a target file from `docs/AUTONOMOUS_IMPROVEMENT_CATALOG.md`, inspect this ledger:
> 1. **SHA Match:** If a target file is listed here as `COMPLETE` or `SOUND` and its Git commit SHA has not changed (`git log -n 1 --pretty=format:%h -- <file>` matches `Target SHA`), **DO NOT REPEAT WORK**.
> 2. **In-Flight PRs:** Check `gh pr list` to ensure no active PR is already modifying the target file.
> 3. **Append on PR:** Every PR completing a work stream item must append its row to this ledger.

---

## Active & Historical Work Ledger

| Date | Stream | Target File / Module | Target SHA | Status | PR / Issue | Summary / Outcome | Re-Audit Trigger |
|---|---|---|---|---|---|---|---|
| 2026-10-17 | Stream 1 (Mutation) | `lib/src/domain/graph_aware_review_coordinator.dart` | `9e2c9e480` | COMPLETED | #202 | 27 curated mutants: 17 killed, 7 invalid (compile), 3 survived; closed 2 real INV-028 gaps with tests, L209 documented equivalent. | Any modification to graph_aware_review_coordinator.dart. |
| 2026-10-16 | Stream 2 (Spec Audit) | Full Repertoire SRS core (`44 invariants`) | `bad86151f` | COMPLETED | #191, #192 | Verified 44/44 invariants. Identified open findings F1–F5 in `docs/spec-conformance-audit-2026-10-16.md`. | Major architectural change or new spec version. |
| 2026-10-17 | Stream 1 (Mutation) | `lib/src/domain/scheduler.dart` | `a71a19096` | IN_PROGRESS | Issue draft | Evaluated 10 mutants: 6 killed, 4 survived. Found stability zero fallback gap & equality test gap. | Any modification to `scheduler.dart`. |
| 2026-10-17 | Stream 2 (Smell Audit) | Full Test Suite (`1855 declarations`) | `a71a19096` | IN_PROGRESS | `scripts/audit_2026-10/` | Screened 1855 tests with `smell_tests.py`; flagged 298 declarations (vacuous assertions, blocking sleeps). | Any new test additions without linter coverage. |

---

## Target Candidates Ready for Pickup (Unchecked)

### Stream 1: Mutation Testing Targets (Never Audited)
- [x] `lib/src/domain/graph_aware_review_coordinator.dart` (Core graph propagation: contagion, exposure, sibling coupling)
- [ ] `lib/src/domain/chess_fsrs_scheduler.dart` (DSR power-law formulas, retrievability interval solving)
- [ ] `lib/src/domain/review/review_engine.dart` (Move validation, auto-traversal, line transitions)
- [ ] `lib/src/domain/review/review_session.dart` (Queue partitioning, prefetch refills, daily limits)
- [ ] `lib/src/import/pgn_exporter.dart` (PGN serialization, move comments, orientation tags)
- [ ] `lib/src/persistence/sqlite_study_repository.dart` (Targeted scope queries, transactions, mmap)
- [ ] `lib/src/domain/position_knowledge_state.dart` (Canonical key generation and state conversions)

### Stream 2: Test Smell Remediation Targets
- [ ] `test/view/offline_computer/offline_computer_game_screen_test.dart:1353` (Eliminate blocking `sleep()` with fake clock/pump)
- [ ] `test/review/review_service_test.dart:43` (Harden `INV-002`: verify chapter tree table is genuinely not rewritten)
- [ ] `test/persistence/sqlite_study_repository_test.dart:1745` (Harden `INV-051`: test delete chunking at SQLite variable limits)

### Stream 4: SQLite Migration & Data Preservation Targets
- [ ] Migration Fixtures: Create on-disk tests for migrations v6–v11 and v14–v15.
- [ ] Orphan Row Elimination: Trace origin of 117 orphaned `srs_review_state` rows and add cascade cleanup triggers.
