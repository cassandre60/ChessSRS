# Autonomous Work Ledger

> **Deduplication rule for agents.**
> Before picking a target file from `docs/AUTONOMOUS_IMPROVEMENT_CATALOG.md`,
> inspect this ledger:
>
> 1. **Content hash match:** If a target file is listed here as `COMPLETED`
>    or `SOUND` and its content hash has not changed
>    (`git hash-object <file>` or `git rev-parse HEAD:<file>` matches
>    `Content Hash`), **do not repeat work**. (`git log -- <file>` is the
>    *last commit touching* the file, not the content — a revert or
>    cherry-pick can give the same commit hash for different content or vice
>    versa.)
> 2. **In-flight PRs:** Run `gh pr list` and re-check immediately before
>    pushing — another agent may have opened a PR between your `next` query
>    and your push.
> 3. **Append on PR:** Every PR completing a work-stream item must append its
>    row to this ledger in the same PR.
> 4. **Merge contention:** Two agents appending to this file will conflict.
>    `git pull --rebase origin/main` and retry; do not overwrite the other
>    agent's row.

---

## Active & Historical Work Ledger

| Date | Stream | Target File / Module | Content Hash | Status | PR / Issue | Summary / Outcome | Re-Audit Trigger |
|---|---|---|---|---|---|---|---|
| 2026-10-18 | Stream 2 (Test Smell) | `test/view/offline_computer/offline_computer_game_screen_test.dart` | `91d535dbc` | COMPLETED | #229 | Removed the suite's last wall-clock sleep (the 1s-control timeout test): LocalGameClock now runs on package:clock's stopwatch, so `tester.pump` charges the countdown. Stashing the lib change fails the test at its 'White time out' expectation. | Any change to LocalGameClock's time source, or to this test. |
| 2026-10-18 | Stream 2 (Test Smell) | `test/review/review_service_test.dart` | `b4ec07cc6` | COMPLETED | #227 | The `incremental persistence` test claimed "without rewriting trees" but only checked that state and event landed. It now records every study/chapter/decision writer and compares the tree blob and decisions before/after; it fails when the answer path re-saves a decision. | Any change to the answer path or to this oracle. |
| 2026-10-18 | Stream 1 (Mutation) | `lib/src/domain/review/review_session.dart` | `d2b783d6f` | COMPLETED | #223 | 248 curated mutants: 78 killed by the pre-existing suite, 66 won't-compile, 101 survivors (+3 timeout artifacts). The new 39-test suite kills 67 of the 101: 50 of the 71 the first pass left, plus 17 of the 30 it had killed (recheck: 13 of those are no longer killed). 34 survivors recorded, L1224/L170/L1045 documented equivalents, L1060 open. | Any modification to review_session.dart. |
| 2026-10-18 | Stream 1 (Mutation) | `lib/src/domain/position_knowledge_state.dart` | `2860408ca` | COMPLETED | #208 | 29 curated mutants: 5 killed, 13 survived (11 invalid); all 13 closed with 2 tests. | Any modification to position_knowledge_state.dart. |
| 2026-10-18 | Stream 1 (Mutation) | `lib/src/persistence/sqlite_study_repository.dart` | `80b5f1647` | COMPLETED | #206 | 158 curated mutants: 91 killed, 67 survived; 8 real gaps closed with 6 tests, 59 documented equivalents (6 loop-boundary mutants pinned by 4 exact-multiple tests + SQLite IN () no-op evidence). | Any modification to sqlite_study_repository.dart. |
| 2026-10-18 | Stream 1 (Mutation) | `lib/src/import/pgn_exporter.dart` | `5e4c31a2d` | COMPLETED | #204 | 41 curated mutants: 27 killed, 6 compile-killed, 8 survivors; 3 real fidelity gaps closed with 4 tests (Chapter tag vs Event fallback; mainline and variation comments; black-to-move round trip; INV-014), 5 documented (L106 numbering form, L154–L159 unreachable else-branch). | Any modification to pgn_exporter.dart. |
| 2026-10-18 | Stream 1 (Mutation) | `lib/src/domain/chess_fsrs_scheduler.dart` | `f23a3db68` | COMPLETED | #203 | 76 curated mutants: 20 killed by the suite, 23 compile-killed, 33 survivors; 29 real gaps closed with 9 tests (the const-canonicalised equality test could not fail; runtime-constructed operands re-pin INV-026, plus INV-025 boundary guards), 4 documented equivalents (L144, L152, L236, L330). | Any modification to chess_fsrs_scheduler.dart. |
| 2026-10-17 | Stream 1 (Mutation) | `lib/src/domain/graph_aware_review_coordinator.dart` | `9e2c9e480` | COMPLETED | #202 | 27 curated mutants: 17 killed, 7 invalid (compile), 3 survived; closed 2 real INV-028 gaps with tests, L209 documented equivalent. | Any modification to graph_aware_review_coordinator.dart. |
| 2026-10-16 | Stream 2 (Spec Audit) | Full Repertoire SRS core (`44 invariants`) | `bad86151f` | COMPLETED | #191, #192 | Verified 44/44 invariants. Identified open findings F1–F5 in `docs/spec-conformance-audit-2026-10-16.md`. | Major architectural change or new spec version. |
| 2026-10-17 | Stream 1 (Mutation) | `lib/src/domain/scheduler.dart` | `a71a19096` | IN_PROGRESS | Issue draft | Evaluated 10 mutants: 6 killed, 4 survived. Found stability zero fallback gap & equality test gap. | Any modification to `scheduler.dart`. |
| 2026-10-17 | Stream 2 (Smell Audit) | Full Test Suite (`1855 declarations`) | `a71a19096` | IN_PROGRESS | `scripts/audit_2026-10/` | Screened 1855 tests with `smell_tests.py`; flagged 298 declarations (vacuous assertions, blocking sleeps). | Any new test additions without linter coverage. |

> **Note on existing rows:** Hashes recorded before 2026-10-18 used
> `git log -- <file>` (commit hash). They remain valid as "last audited
> commit" markers; new rows must use `git hash-object` content hashes.
> Re-audit is triggered by content change, not commit identity.

---

## Target Candidates Ready for Pickup (Unchecked)

Derived from `IMPLEMENTATION_PLAN.md` Future Horizon and
`docs/spec-conformance-audit-2026-10-16.md` findings F2–F5. This list is not
a second work queue — it is a convenience index into plan-owned work.

### Stream 1: Mutation Testing Targets (Never Audited)

- [x] `lib/src/domain/graph_aware_review_coordinator.dart` (Core graph propagation: contagion, exposure, sibling coupling)
- [x] `lib/src/domain/chess_fsrs_scheduler.dart` (DSR power-law formulas, retrievability interval solving)
- [ ] `lib/src/domain/review/review_engine.dart` (Move validation, auto-traversal, line transitions)
- [x] `lib/src/domain/review/review_session.dart` (Queue partitioning, prefetch refills, daily limits)
- [x] `lib/src/import/pgn_exporter.dart` (PGN serialization, move comments, orientation tags)
- [x] `lib/src/persistence/sqlite_study_repository.dart` (Targeted scope queries, transactions, mmap)
- [x] `lib/src/domain/position_knowledge_state.dart` (Canonical key generation and state conversions)

### Stream 2: Test Smell Remediation Targets

- [x] `test/view/offline_computer/offline_computer_game_screen_test.dart:1353` (Eliminate blocking `sleep()` with fake clock/pump)
- [x] `test/review/review_service_test.dart:43` (Harden `INV-002`: verify chapter tree table is genuinely not rewritten)
- [ ] `test/persistence/sqlite_study_repository_test.dart:1745` (Harden `INV-051`: test delete chunking at SQLite variable limits) — parked 2026-10-18: SQLite here allows 250000 bound variables and the app's DB layer exposes no per-connection limit, so exceeding it is impractical; needs a different oracle.

### Stream 4: SQLite Migration & Data Preservation Targets

- [ ] Migration Fixtures: Create on-disk tests for migrations v6–v11 and v14–v15.
- [ ] Orphan Row Elimination: Trace origin of 117 orphaned `srs_review_state` rows and add cascade cleanup triggers.
