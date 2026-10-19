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
| 2026-10-19 | Stream 2 (Smell Audit) | Full Test Suite | `d76e4395e` | COMPLETED | #233, #240 | The 1855-declaration screening's products landed: #233 built `scripts/audit_2026-10/` evidence, tightened assertions and property tests; #240 retired the duplicate task queue leaving evidence read-only. Re-screen when the suite grows by a batch. | Suite-reaching test batches without a re-screen. |
| 2026-10-19 | Stream 1 (Mutation) | `lib/src/domain/review/review_session.dart` | `d2b783d6f` | COMPLETED | #223 | 50 ReviewSession mutation survivors killed per the merged PR summary. Content hash from `git hash-object` at main `d76e4395e`. | Any modification to review_session.dart. |

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

- [x] `test/view/offline_computer/offline_computer_game_screen_test.dart:1353` (Eliminate blocking `sleep()` with fake clock/pump) — swept: `rg -n "sleep\(" test/view/offline_computer/offline_computer_game_screen_test.dart` returns nothing (#229 pinned the game clock on the fake stopwatch).
- [x] `test/review/review_service_test.dart:43` (Harden `INV-002`: verify chapter tree table is genuinely not rewritten) — swept: `_TreeWriteRecordingRepository` records chapter-table writes; #227 asserts the answer path never rewrites the study tree.
- [x] `test/persistence/sqlite_study_repository_test.dart:1745` (Harden `INV-051`: test delete chunking at SQLite variable limits) — swept: the delete-chunking bounds oracle (#232) and FK-cascade refusal tests live in the repository suite.

### Stream 4: SQLite Migration & Data Preservation Targets

- [x] Migration Fixtures: Create on-disk tests for migrations v6–v11 and v14–v15. — swept: `test/persistence/migration_fixtures_test.dart` (added by #236) fixtures every shipped schema path from v6 to v15 on disk.
- [x] Orphan Row Elimination: Trace origin of 117 orphaned `srs_review_state` rows and add cascade cleanup triggers. — swept: #239 carries review-state mirrors through the canonical rekey and sweeps stranded ones.
