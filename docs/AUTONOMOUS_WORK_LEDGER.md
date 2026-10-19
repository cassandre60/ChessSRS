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
| 2026-10-17 | Stream 1 (Mutation) | `lib/src/domain/graph_aware_review_coordinator.dart` | `9e2c9e480` | COMPLETED | #202 | 27 curated mutants: 17 killed, 7 invalid (compile), 3 survived; closed 2 real INV-028 gaps with tests, L209 documented equivalent. | Any modification to graph_aware_review_coordinator.dart. |
| 2026-10-16 | Stream 2 (Spec Audit) | Full Repertoire SRS core (`44 invariants`) | `bad86151f` | COMPLETED | #191, #192 | Verified 44/44 invariants. Identified open findings F1–F5 in `docs/spec-conformance-audit-2026-10-16.md`. | Major architectural change or new spec version. |
| 2026-10-17 | Stream 1 (Mutation) | `lib/src/domain/scheduler.dart` | `a71a19096` | IN_PROGRESS | Issue draft | Evaluated 10 mutants: 6 killed, 4 survived. Found stability zero fallback gap & equality test gap. | Any modification to `scheduler.dart`. |
| 2026-10-17 | Stream 2 (Smell Audit) | Full Test Suite (`1855 declarations`) | `a71a19096` | IN_PROGRESS | `scripts/audit_2026-10/` | Screened 1855 tests with `smell_tests.py`; flagged 298 declarations (vacuous assertions, blocking sleeps). | Any new test additions without linter coverage. |
| 2026-10-18 | Stream 2 (Smell Audit) | `test/model/offline_computer/practice_analyser_test.dart` | `bdf1e3d42` | COMPLETED | #197, #221 | Converted 23 fixed wall-clock waits (22 × `settleEvals` 400 ms + one 100 ms `usableEval` deadline await) to `fakeAsync`/`async.elapse`; 0 real sleeps remain (`rg` clean), 8/8 green on the fake clock, deadline-edge mutant killed by the new 99/100 ms boundary expect. | Any reintroduction of fixed real-clock waits into this file. |

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
