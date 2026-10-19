# Performance optimisation handoff

A brief for an agent whose job is to make this app as fast as possible without
changing what it does. Written 2026-10-14.

The owner's mandate, verbatim in intent: **it needs to be instant; everything in
the app needs to be as fast as possible.**

That mandate is taken seriously. So is the obvious risk, which this brief spends
most of its length on: *optimising "to death" without measurement is how an app
becomes subtly wrong while every test still passes.* Read section 2 before
touching anything.

---

## 1. Mission

Make it faster. Leave it correct.

Specifically: reduce wall-clock time on every user-facing path, with evidence for
each change, and with behaviour byte-identical unless the owner has agreed
otherwise.

**Done means all of:**

- A measured before and after for every change, on the real library.
- The full suite green, and `./scripts/gates.sh t1` → `t1 ok`.
- Every SPEC invariant still cited and still enforced.
- No test weakened, skipped, or deleted to accommodate an optimisation.
- The change runtime-validated in the running app (section 6).

---

## 2. The rules that matter

### Measure first, every time

Do not optimise what has not been measured on this database. The owner library
is the only realistic workload: **11 studies, 25 chapters, 528 decisions, 480
due, 7 MiB.** Synthetic fixtures are worse than useless here — see section 4.

Copy the database and benchmark the copy. **Copy the `-wal` sidecar too.** It has
a 4 MiB write-ahead log, and copying only the `.db` gives a snapshot missing
recent transactions.

```bash
cp ~/.local/share/org.chesssrs.chess_srs/chess_srs.db{,-wal,-shm} /tmp/perf/
export CHESS_SRS_PERF_DB=/tmp/perf/chess_srs.db
```

Two harnesses already exist and print what they measure:

- `test/perf/real_library_session_cost_test.dart` — end-to-end session start.
- `test/perf/due_summary_attribution_test.dart` — per-call attribution of the
  due-summary cost.

Both harnesses skip without `CHESS_SRS_PERF_DB` and never fall back to a synthetic
fixture. Extend them rather than writing a third from scratch.

The attribution harness has two tests since 2026-10-19: the sequential
median-of-15 attribution, and an interleaved variant that rotates the call order
every round and reports min/p25/median/p75/max per call. Trust the interleaved
one. Its findings (first use documented in
`docs/tasks/PERF-FIX-24-real-library-measurement.md`, fifth pass):

- measurement order biases a sequential harness: `getAllReviewStates()` produced
  16, 29 and 36 ms under it for the same call, depending on harness and order;
- residual spread survives the rotation (GC/allocation interruptions), and the
  whole instrument still moves between processes minutes apart;
- so: measure before and after **in one process**, quote bands
  (min/p25/median/p75/max), and never decide on a sub-band difference.

### Median, generous ceilings

Median of ≥10 after warmups. The first run reads roughly 2x the warmed one
because it is compilation, not the code under test.

**Do not assert real frame budgets in benchmarks.** They flake on a loaded CI
runner and then get loosened until they mean nothing. Assert loose ceilings
(catch an order-of-magnitude regression, not a slow machine) and put the real
number in a comment.

### Refute before you optimise

Every hypothesis below was tested and **refuted by measurement**. Optimising any
of them is wasted work, and worse, it is wasted work that looks like diligence:

| Hypothesis | Measured | Verdict |
|---|---|---|
| Session start is slow because the SQL is slow | ~1.4 ms for every statement involved | **Refuted** |
| It is ISO-8601 date parsing in the row mapper | `DateTime.parse` ×1473 = **1.92 ms** | **Refuted** |
| The `ReviewSession` constructor dominates | ~2 ms of a 37 ms path | **Refuted** |
| Chunking the constructor (PERF-FIX-32 Phase 2) would help | targets ~5% of the cost | **Refuted** |

### A warning about a trap already fallen into twice

On this codebase, two different "control" measurements were invalid in the same
way — a helper was called with a different argument than intended, so it did
less work than assumed, and the comparison was between two things doing
different work. One of those led to a confident wrong conclusion.

**Check what your control actually did before believing it.** A benchmark that
returns 66 rows cannot tell you about the cost of 347.

### Behaviour is the contract

- No SPEC invariant may be weakened, and its citation may not be removed.
- No test may be deleted, skipped, or loosened to make a change pass. G08 watches
  for exactly this (`docs/ESCAPE_TO_GATE.md`).
- If an optimisation changes observable behaviour — ordering, tie-breaking,
  numeric results, what is cached — it is not an optimisation. Stop and ask.
- `QUALITY.md §4.1` is a real bound: **move response time < 16 ms**, covered by
  `test/review/move_latency_test.dart`. Session start is off that path.

---

## 3. Where the time is

Measured 2026-10-14 on the owner's library. Stable across runs.

| Path | Time |
|---|---|
| whole-library `startSession()` | **37–39 ms** |
| `getDueSummary()` alone | **21–29 ms** |
| largest single study `startSession()` | 15–16 ms |

Of `getDueSummary`'s 21 ms, one call dominates:

| Call | Time | Share |
|---|---|---|
| **`getAllReviewStates()`** | **16.2–16.7 ms** | **76%** |
| `getAllDecisions()` | 1.9–2.3 ms | 11% |
| `getKnowledgeStates()` | 1.9–2.0 ms | 9% |
| three `srs_chapter` selects | ~1.2 ms | 5% |

**~13 ms of that 16.2 ms is unattributed.** SQL (~0.9 ms) and date parsing
(~1.9 ms) together account for under 3 ms. The rest is Dart, constructing and
merging **772** objects (491 returned after merge), including a `toReviewState()`
per knowledge row.

**The first move is therefore to find out where those 13 ms are, not to guess.**
Two plausible explanations were already tested and refuted, so a third guess is
no more reliable. Use a profiler (`--observe`, or the Dart VM's allocation
tracking) on a single `getAllReviewStates()` call against the real database.

That said, one structural observation worth testing rather than assuming:
`getDueSummary` builds a map of **every** review state and knowledge state in
order to compute due counts. If those counts can come from the database without
materialising 772 domain objects, the 13 ms disappears with it. That is a
hypothesis — measure it, do not assume it.

---

## 4. What is not measured

The owner library is small. That cuts both ways:

- Anything that only bites at 50k decisions will not show up here.
- Anything measured only here may not generalise. Say so when reporting.
- `PERF-FIX-32` Phase 2 was declined because real cost is ~4 µs/decision and only
  crosses a 16 ms budget past ~5000 decisions. **That analysis still holds** for
  the constructor. Do not reopen it without a real library above that size.

Fixtures are the wrong instrument for this repo's workload. `canonicalStateId`
sharing in the real data is **1.17x** (77 of 528 decisions); a fixture that shares
canonical states heavily does not reproduce it, and the canonical-merge path is a
plausible source of cost.

---

## 5. Paths not yet measured

The two harnesses cover the review-open path. **Unmeasured, and plausible
targets:**

- Import of a large PGN.
- Study/chapter browsing with many studies.
- The offline engine path — search, evaluation, opponent play.
- Widget build and layout — `lib/src/view/` is 23k lines and has never been
  profiled.
- Startup, before any review session exists.

Measure before proposing. Several of these may already be fine.

---

## 6. Verify like this repo expects

- **Targeted tests for what you touched**, then `./scripts/gates.sh t1` **after
  committing** — the diff-based gates read `origin/main...HEAD` and see nothing
  while your work is uncommitted. Run against your commit, not your tree.
- **Never run the full suite locally.** ~1750 tests, no path filter; it saturates
  the owner's machine. CI runs it on every push. See `AGENTS.md §3.1`.
- **Runtime validation is mandatory** (`AGENTS.md §4`). Launch
  `fvm flutter run -d linux`, exercise the path you optimised, and look at it.
  Green CI is not evidence that the app works; the perf work this brief asks for
  is exactly the work where that is hardest to notice.
- **Record what the suite cannot check** in `docs/manual-test-log.md`, in the same
  PR. If an optimisation changes how something *feels* — latency of a tap, a
  scroll, a sound — only a person can confirm it.
- **No release builds on the dev machine.** They have OOM-killed it. Release
  artifacts come from the `release-proof` workflow on CI runners.

---

## 7. Deliverable per change

A PR containing:

1. The measurement before, with the data shape that produced it.
2. The change.
3. The measurement after, same harness, same database copy.
4. What was refuted along the way, if anything — that is often the most useful
   part.
5. Runtime evidence: what you ran in the app and what you saw.

If a change makes something faster but you cannot say by how much, it is not a
finished change. If you optimise something and it turns out to be irrelevant,
say so — **"measured, nothing to do here" is a valid and valuable result**, and
cheaper than a speculative refactor.

---

## 8. Where the open questions are

`docs/open-questions.md` holds anything that needs the owner rather than an
engineer. Add to it rather than asking in a PR comment that scrolls away.

The owner's standing answer on speed is the mandate at the top of this brief:
**instant, everything, as fast as possible.** That is the target. Where it
conflicts with keeping the app correct, correctness wins and the conflict is
recorded — not silently resolved either way.