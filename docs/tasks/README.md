# Review brief queue & Autonomous Improvement

> **Autonomous Improvement Engine:**
> For continuous, autonomous improvement cycles, mutation tests, or test suite audits,
> follow the **[Autonomous Improvement Catalogue](../AUTONOMOUS_IMPROVEMENT_CATALOG.md)**.
> All agents working on repo improvement must follow the **Fail-to-Pass Invariant**
> and the **Worktree Isolation Rule** defined there.

Work items for review passes over this codebase. Each `.md` here is a brief an
agent can pick up and execute top-to-bottom.

## Current state

| Brief | Status |
|---|---|
| `REFACTOR-FIX-23-enum-values-not-dead.md` | Investigation complete — **0 dead enum values; all are actively persisted/used** |
| `PERF-FIX-24-real-library-measurement.md` | Measured on 31k-decision real library — durable findings recorded |
| `PERF-FIX-48-session-start-move-list-ceiling.md` | Closed 2026-10-24 — lazy expectedMoves refuted (~30 ms ceiling); path decision open as Q15 |

### Recently Landed Briefs (Swept)

| Brief | PR / Commit | Summary |
|---|---|---|
| `A11Y-FIX-27` | PR #75 (`bacc64e39`) | Review screen semantics: board label, continue button, figurine SAN |
| `POLISH-FIX-11` | PR #109 (`17100cd64`) | Single shared `PgnCommentShape` to `Shape` extension |
| `REFACTOR-FIX-21` | PR #112 (`8dfcb7c78`) | Remove dead Pick conversion helpers |
| `REFACTOR-FIX-22` | PR #113 (`90287a940`) | Remove dead predicates and unused providers |
| `PERF-FIX-33` | PR #142 (`a3c428781`) | Slim due summary decision load (omit JSON move parsing in tallies) |
| `PERF-FIX-34` | PR #143 (`442751fbc`) | Adaptive review state query chunking vs single-query scan |
| `PERF-FIX-35` | PR #144 (`13efce44c`) | Fast UTC ISO date parsing (`parseUtcIso`) |
| `PERF-FIX-36` | PR #145 (`a6d36e2ca`) | Targeted scope due summary |
| `PERF-FIX-37` | PR #146 (`22b7a4bf0`) | SQLite native page memory mapping (mmap) |
| `PERF-FIX-38` | PR #151 (`34141bb64`) | Differential summary tallying |
| `PERF-FIX-39` | PR #148 (`3488b6661`) | Pipelined animation with overlapped answer durability |
| `PERF-FIX-40` | PR #147 (`77000334d`) | Board repaint boundary isolation |
| `PERF-FIX-41` | PR #150 (`bc1404bc5`) | Sub-sensory move pre-warming on touch |
| `FEAT-REP-43` | PR #156 (`584b5c383`) | Dynamic repertoire branch selection & practice mode unlocking |
| `PERF-FIX-44` | PR #158 (`0fbf8666b`) | Batch chapter queries, fast move decoding, single-pass partitioning |
| `PERF-FIX-45` | PR #172 (`903445155`) | Targeted decision queries and SQL-level orientation filtering |
| `PERF-FIX-46` | PR #175 (`72e413b51`) | Lazy chapter tree deserialization and on-demand session indexing |

21–23 came from a tree-wide sweep for declarations with exactly one occurrence
across `lib/` + `test/` + `scripts/`, run 2026-10-13. It returned 72 candidates:
27 hand-written and removable, ~30 enum values that must **not** be deleted
blind (23 is about those), and the rest in files the reachability ratchet already
pins as dead. The sweep is reproducible — see the command in each brief.

**The queue was pruned on 2026-10-13 and swept on 2026-10-16.** All completed
briefs were verified against `origin/main` before removal. They fall into three groups:

- **Landed** — the work shipped in a PR, often by another agent working the same
  brief concurrently. Examples: `ARCH-FIX-06` (#87), `PERF-FIX-21` (#84),
  `SYSTEM-FIX-35` (#85), `DESKTOP-FIX-37` (#90), `REFACTOR-FIX-23` (#91),
  `REFACTOR-FIX-20` (#105), `AUDIO-FIX-34` (#93).
- **Already correct** — the brief's recommended change is what the code already
  does. `RATCHET-FIX-22` asked for stale entries to be pruned from the
  reachability ratchet; a fresh import-graph trace found 0 of 11 stale.
  `POLISH-FIX-09` asked for `768` to become the shared `720` token; the drawer
  already called `SrsLayout.isWide`.
- **Premise false** — following the brief would make things worse.
  `ARCH-FIX-05` named three screens violating the `QUALITY.md §1.1`
  presentation boundary; `git grep -ln "src/db/\|src/persistence/" -- 'lib/src/view/**'`
  returns nothing, so **zero of 74** view files import either.
  `DOMAIN-FIX-33` called a ghost prompt a defect; it is the intended lapse
  re-test, guarded by an assertion in the review controller tests.

Full per-brief evidence is in [issue #71](https://github.com/cassandre60/ChessSRS/issues/71).
Nothing was lost: every file is in this repo's history.

## Writing a brief that survives the week

Observed yield before the prune was roughly 1 brief in 4 workable. The cause was
never the analysis — it was staleness. A brief is written from a tree snapshot,
and this repo merges several PRs a day, so a brief has a shelf life of days. Two
of the "premise false" briefs were invalidated *by the same fleet doing correct
work*.

Two habits fix it:

1. **State the premise as a command someone can re-run**, not as a line number.
   A brief whose premise is a `git grep` is self-checking; a brief whose premise
   is `review_service.dart:157` is stale the moment anyone inserts an import.
   Compare the two above: the `ARCH-FIX-05` grep was still runnable and proved
   the brief wrong, which is exactly what you want.

2. **Say what would make the brief wrong.** If an agent checks and finds the
   change already made, that is a fast close. If the brief cannot say what
   "already fixed" looks like, the next agent has to guess.

Also worth writing down: briefs describing *intent* rather than a defect need
the intent checked against `QUALITY.md` and the guarded tests first. Several of
the dead ones here proposed removing behaviour that was deliberate — the lapse
re-test, the review-state mirror.