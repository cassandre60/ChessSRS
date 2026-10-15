# Review brief queue

Work items for review passes over this codebase. Each `.md` here is a brief an
agent can pick up and execute top-to-bottom.

## Current state

| Brief | Status |
|---|---|
| `A11Y-FIX-27-review-screen-semantics.md` | In progress |
| `POLISH-FIX-11-pgn-shape-extension-and-board-notify.md` | In progress |
| `REFACTOR-FIX-21-pick-helpers-no-callers.md` | Ready |
| `REFACTOR-FIX-22-dead-predicates-and-providers.md` | Ready |
| `REFACTOR-FIX-23-enum-values-not-dead.md` | Ready — investigation, **read before deleting** |
| `PERF-FIX-24-real-library-measurement.md` | Measured 2026-10-15 — 31k-decision findings recorded |
| `PERF-FIX-33-slim-due-summary-decision-load.md` | Implemented |
| `PERF-FIX-34-adaptive-review-state-loading.md` | Implemented |
| `PERF-FIX-35-fast-utc-iso-date-parsing.md` | Implemented |
| `PERF-FIX-36-targeted-scope-due-summary.md` | Ready — eliminates 500ms hitch on scope navigation |

21–23 came from a tree-wide sweep for declarations with exactly one occurrence
across `lib/` + `test/` + `scripts/`, run 2026-10-13. It returned 72 candidates:
27 hand-written and removable, ~30 enum values that must **not** be deleted
blind (23 is about those), and the rest in files the reachability ratchet already
pins as dead. The sweep is reproducible — see the command in each brief.

**The queue was pruned on 2026-10-13.** It held 36 briefs; 34 were removed after
each was verified against `origin/main`. They fall into three groups:

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