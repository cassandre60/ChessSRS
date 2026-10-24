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
due, 7 MiB** (2026-10-14). It does not stay that size — by 2026-10-24 it is
**61 studies, 309 chapters, 31,156 decisions, 330 due, 34 MiB** (§9). Re-read
the shape from the harness output each time; do not trust a remembered number.
Synthetic fixtures are worse than useless here — see section 4.

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
---

## 9. Measured 2026-10-24 — the library grew 60x; where the time is now

The landed harnesses (`test/perf/real_library_session_cost_test.dart`,
`test/perf/due_summary_attribution_test.dart`), run against a copy of the
owner's database (`CHESS_SRS_PERF_DB`), median of 15 after 3 warmups, single
worker, on the 2026-10-24 tree (`0704e4824`). This is the run the playbook
asked for: benchmark first, run it, rank suspects from the numbers.

**Shape:** 61 active studies, 309 chapters, 31,156 decisions, 330 due,
34 MiB — versus 11/25/528/480/7 MiB on 2026-10-14.

| Measurement | 2026-10-14 (519 decisions) | 2026-10-24 (31,156 decisions) |
|---|---|---|
| whole-library `startSession()` | 37–39 ms | **795 ms** |
| `loadSessionAndSummary()` | — | **880 ms** |
| `getDueSummary()` (due queries only) | 26–30 ms | **~170–175 ms** |
| largest single study `startSession()` | 15–16 ms | 49 ms |

No order-of-magnitude regression: the harness's 2000 ms ceiling passes, and
~20x session-start growth against 60x decision growth is roughly linear
(~25 µs/decision end to end, versus the synthetic constructor's ~4 µs/decision
estimate — the real cost is the queries, as §3 predicted).

**Due-summary attribution (the interleaved harness, medians with spread):**

| Call | Median | Share |
|---|---|---|
| `getAllDecisions` | 172.6 ms (151.7–206.8) | **61%** |
| `getTallyDecisions` | 84.3 ms (75.9–111.7) | **30%** |
| `getAllReviewStates` | 15.0 ms (14.2–32.3) | 5% |
| `getKnowledgeStates` | 9.6 ms (7.7–25.0) | 2–3% |
| chapter openings/orientations/ids | ~2 ms each | ~1% each |
| sum of parts / `getDueSummary()` total | 284.6 / 225.6 ms | |

Date-parse control on 1743 stamps: `DateTime.parse` 2.6 ms vs `parseUtcIso`
0.5 ms — parsing is not the cost.

**Ranked suspects for any future optimisation (owner decides whether to spend
the change; the mandate is "instant" and QUALITY §4.1's 16 ms governs the move
path, not session start):**

1. `getAllDecisions` — a full-table load of 31k rows to build the summary
   (61%). A due-aware targeted query is the lever PERF-FIX-21 used at 519
   decisions; the summary path has outgrown it.
2. `getTallyDecisions` — the second full-table load (30%).
3. `startSession()`'s non-summary remainder (~620 ms over 31k decisions) —
   not yet attributed; the attribution harness covers the summary path only.
   Do not touch it before giving it its own attribution pass.
4. Everything else measured ≤15 ms — noise at this shape.

**Harness fix shipped with this record:** the default 30 s per-test timeout
killed `real_library_session_cost_test.dart` mid-run at this shape (3 warmups
+ 15 calls at ~0.9 s each exceed it) — the run died before printing
`startSession()`. The test now carries `timeout: Timeout(Duration(minutes:
10))`. `due_summary_attribution_test.dart` still fits at this shape but has
the same exposure; give it the same parameter if a future shape outgrows it.

Runtime checks owed: none new — this pass measured, changed no product code.

---

## 10. Session-start attribution, 2026-10-24 (answers §9's suspect 3)

`test/perf/session_start_attribution_test.dart` (same conventions: real-DB copy,
median of 15 after 3 warmups, interleaved rotated rounds, no synthetic fallback).
The all-studies path on the 34 MiB library:

| Part | Median |
|---|---|
| `getAllStudies` | 2 ms |
| `getChaptersByStudyIds` | 34–52 ms |
| `getAllDecisions` | 160–162 ms |
| review-data load (SQL + the maps `_loadReviewData` builds) | 30 ms |
| `getUnlockedDecisionIds` | 0 ms (mode off by default) |
| **force-decode all chapter trees (control probe)** | **358 ms** |
| **session build, fully preloaded (no DB)** | **606–677 ms** |
| whole `startSession()` | 795–889 ms |

The parts account for the whole (remainder −4% to −42% run to run; the build
figure is noisy across runs — read the interleaved spread in the harness output,
not a single number). **The database is not the bottleneck: ~75% of session
start is Dart-side session construction**, and roughly half of that is the
constructor's chapter-index loop force-decoding lazy trees:

- `Chapter.root` jsonDecodes the chapter's whole tree on first access
  (`_root ??= rootResolver?.call()`), and the constructor's
  "index chapters holding decisions in queue" loop reads `chapter.root` for
  every chapter with a queued item — with 330 due items spread over 309
  chapters, that decodes nearly the whole library at open. PERF-FIX-46 made
  chapter trees lazy; the session constructor's eager indexing defeats it.

**Why this is recorded, not fixed:** the index the constructor builds
(`_decisionsByFenKey`, `_canonicalByFenMove`, `_nodesById`) is read by
cross-chapter transposition lookups (the acceptance path behind INV-065 and the
coordinator's canonical resolution). Those lookups are correct *because* every
queued chapter is indexed before the first answer; indexing lazily per chapter
would hide transposition candidates from not-yet-prompted chapters — a behavior
change, and the handoff's rule is that behaviour is the contract.

**Optimisation paths, in risk order (owner decides):**

1. *None of them are small.* The candidates are: decoding trees off the UI
   thread (isolate) — wall clock unchanged, jank removed; restructuring grading
   to not need a prebuilt global fen-key index — a domain redesign in
   invariant-dense territory; or making `RepertoireDecision.expectedMoves` lazy
   (the 162 ms `getAllDecisions` is row mapping — mostly move-list parsing the
   queue build never touches). Each needs its own brief, its own equivalence
   story, and the full suite. Nothing here justifies a quick edit.
2. The 2-second ceiling still passes; the owner's "instant" mandate at 31k
   decisions is a design conversation, not a patch.

---

## 11. The lazy-expectedMoves path is closed (2026-10-24)

Direction 3 of the option-3 handoff — make `RepertoireDecision.expectedMoves`
lazy so session start stops paying for move-list parsing — is refuted for
whole-library session start. Measured, nothing to do here.

Two access-site facts, both verified against the tree:

- The constructor reads every queued decision's move list. `_indexChapter`
  (`review_session.dart:363`) iterates `d.expectedMoves` for every decision in
  every indexed chapter to build `_canonicalByFenMove` (line 373), and
  `neededChapterIds` (line 218) is derived from the final trimmed queue. At
  the 2026-10-24 shape the constructor's decode matches §10's force-decode
  control probe, so nearly every chapter indexes and nearly every decision's
  moves are read before the first prompt. Laziness would relocate the parse
  from `getAllDecisions` into the constructor, not remove it. It would also
  de-const `RepertoireDecision`, whose const constructor ~150 test fixtures
  rely on.
- The 162 ms attributed to `getAllDecisions` double-counted. A raw row scan
  over the same table (query + row maps, no move decode) runs in ~93 ms of the
  145 ms mapping median; only ~52 ms is move parsing.

The ceiling probe (`test/perf/session_start_move_list_ceiling_test.dart`, real
DB copy, median of 15 after 3 warmups, interleaved rotated rounds agreeing):

| Measurement | Median |
|---|---|
| `getAllDecisions` (full mapping) | 145 ms |
| decision rows, no move decode | 93 ms |
| session build, real move lists | 552 ms |
| session build, empty move lists | 521 ms |
| **constructor cost that depends on move-list content** | **~30 ms** |

The whole direction is therefore bounded by ~30 ms of constructor work plus
≤52 ms of parsing the constructor consumes anyway. Separately recorded: 98.6%
of decision rows (30,731 of 31,182) already carry `canonicalStateId`, so
`_canonicalByFenMove` — the map that per-move loop exists to build — is read
only for pre-v10 legacy nodes. Not building it on fully migrated libraries is
a semantic decision (mixed libraries still need it), not a laziness win; it
went to open-questions Q15 together with the two paths that do address the
remaining ~800 ms: storing the fen key on decision rows (removes the tree
decode) and two-phase indexing (moves it off the first frame).
