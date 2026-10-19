# PERF-FIX-24 — Measure the review path against a real library, not a synthetic one


## 1. Why this is a brief at all

Every performance number in this repo comes from a synthetic fixture.
`test/review/session_constructor_cost_test.dart` measures a constructed session at
500 / 2000 / 5000 decisions. PERF-FIX-32 Phase 2 was **declined on that
measurement** — cost was linear at ~4 µs/decision, crossing the 16 ms budget only
past 5000 decisions.

None of that is wrong. It is also not evidence about this app, because the app
has never been measured with a real repertoire in it. The owner's live database
holds **11 studies and 452 due positions** — a shape no fixture reproduces,
because fixtures are usually balanced and this is not.

**The premise:** either the synthetic curve is representative and there is
nothing to do, or it is optimistic and the real number says otherwise. Both
outcomes are worth having. Right now nobody knows which.

## 2. Read before touching anything

1. `test/review/session_constructor_cost_test.dart` — the existing curve, and the
   ratchet it pins. **Do not weaken it.**
2. `QUALITY.md §4.1` — the budget this has to answer to.
3. `docs/tech-debt-inventory.md` — item on the due-summary path.

## 3. The constraint that matters: do not touch the owner's database

The measurement runs against a **copy**. The owner's library is real data and
real review history; a benchmark that opens it read-write can corrupt it, and one
that migrates it can change the thing being measured.

```bash
# Find it (Linux desktop build):
find ~/.local/share -name '*.db' -path '*chess*' 2>/dev/null
```

Copy to a scratch path first and point the harness at the copy. If no database is
present, **stop** — this brief needs the owner's data and must not substitute a
synthetic one, which is the exact thing it exists to replace.

## 4. What to measure

Session start for the default scope (whole library, White), and separately for a
single study — the first number is the cold path a user hits on open, the second
is what they hit repeatedly.

Report, for each:

- wall time, median of N ≥ 10 after 2 warm-up runs
- the due-count query and the tree walk separately, if they can be isolated
- the shape of the data driving it: studies, decisions, nodes, max depth

**Use median, and a generous ceiling.** Phase 2's own lesson was that a
real frame budget asserted in a benchmark is a flake waiting for a loaded CI
runner. Report the number; do not turn it into a hard threshold unless it is
already far outside `QUALITY.md §4.1`.

## 5. What counts as done

- A written number with the data shape that produced it.
- The existing cost ratchet **still passing, unmodified**.
- A statement of whether the synthetic curve held. If it did not, say by how
  much and at what shape — that is the finding.
- If the result is "nothing to do", say so plainly. A brief that concludes "no
  action needed" has done its job.

## 6. What this is not

Not an optimisation task. Do not start optimising. The deliverable is a
measurement, because the current evidence base is entirely synthetic and that is
the gap.
---

## 7. Findings (measured 2026-10-14, owner library)

Measured on a **copy** of the owner's database via
`test/perf/real_library_session_cost_test.dart`. Median of 15 after 3 warmups,
stable across repeated runs.

### The data shape

| | |
|---|---|
| active studies | 10 (11 total) |
| chapters | 23 |
| decisions | 519 |
| due (all scopes) | 480 |
| database size | 7 MiB |
| decisions carrying `canonicalStateId` | 77 of 528 — sharing factor **1.17x** |

The sharing factor matters: a fixture that shares canonical states heavily will
not reproduce this, and the canonical-merge path is a plausible source of the
query cost below.

### The numbers

| Measurement | Result |
|---|---|
| whole-library `startSession()` | **37–39 ms** |
| `getDueSummary()` alone (the queries) | **26–30 ms** |
| largest single study `startSession()` | 15–16 ms |

### What this means

**The synthetic harness was right about its subject and silent about the one
that matters.** `session_constructor_cost_test.dart` measures
`ReviewSession`'s constructor at ~4 µs/decision, which at 519 decisions is
~2 ms. The constructor is genuinely cheap. But the path a user actually pays is
**37 ms**, and **~75% of it is SQLite query time inside `getDueSummary`** — a
cost no benchmark in this repo had ever measured.

The consequence for PERF-FIX-32: Phase 2 proposed chunking the constructor.
The constructor is ~2 ms of a ~37 ms path, so that work would have targeted
roughly **5%** of the observed cost. Declining it was correct *for the
constructor*; the risk was reading that decline as "no performance work needed."

### This is NOT a QUALITY.md §4.1 breach

§4.1's 16 ms is **Move Response Time** — legality validation and repertoire
lookup on a move. A session start is not on that path, and 37 ms is not a
violation of anything the spec asserts. It is a visible pause on opening review,
which is a product judgement about whether that matters, not an invariant.

### Suggested follow-up (not done here)

`getDueSummary` at 26–30 ms is the thing worth a decision. It is read-only, so
an index or a single-pass query may help — but that is optimisation work, and
this brief's deliverable was the measurement. Note that PERF-FIX-21 already
landed a targeted query here (#84); whatever remains may already be near the
floor for this schema.

### Second pass — attribution (2026-10-14)

The first pass said "the queries cost 26–30 ms". **That was wrong**, and it is worth
recording how, because the wrongness was invisible without measuring.

`getDueSummary()` makes six repository calls. Timed individually
(`test/perf/due_summary_attribution_test.dart`, same database, median of 15):

| Call | Result | Share |
|---|---|---|
| **`getAllReviewStates()`** | **16.7 ms** | **76%** |
| `getAllDecisions()` | 2.3 ms | 11% |
| `getKnowledgeStates()` | 1.9 ms | 9% |
| `getChapterOpenings()` | 0.4 ms | 2% |
| `getChapterOrientations()` | 0.4 ms | 2% |
| `getChapterStudyIds()` | 0.4 ms | 2% |
| sum of parts | 22.0 ms | |
| `getDueSummary()` total | 20.8 ms | |

One call dominates, and it is not the one the "queries are slow" reading points at.

#### The queries are not the cost

Timing the same SQL directly in sqlite3 against the same file:

| statement | ms | rows |
|---|---|---|
| `SELECT * FROM srs_decision` | 0.45 | 528 |
| `SELECT * FROM srs_review_state` | 0.44 | 425 |
| `SELECT * FROM position_knowledge_state` | 0.43 | 347 |
| three `srs_chapter` selects | 0.05 total | 25 |

**~1.4 ms of SQL for everything.** An index would buy nothing here.

#### Refuted hypothesis: `DateTime.parse`

The obvious next suspect was the mapper's ISO-8601 parsing. `_reviewStateFromRow`
calls `DateTime.parse(...).toUtc()` on three fields per row. Measured directly,
with no database in the loop:

```
DateTime.parse x 1473   1.92 ms
```

**1.92 ms of the 16.7 ms.** Not the cost. The temptation would be to stop here and
tell someone "don't optimise the date parsing" — which is the useful outcome, but
only because it was measured rather than assumed.

A note on how nearly this went the other way: `getKnowledgeStates()` looked like a
control showing the same parsing costing 2 ms for 347 rows, which would have made
`DateTime.parse` implausible. That control was invalid — it was called with 66
canonical ids, so it fetched 66 rows, not 347. The comparison was between two calls
doing different work.

#### Still unattributed: ~13 ms

SQL (~0.9 ms) and date parsing (~1.9 ms) account for under 3 ms of
`getAllReviewStates`' 16.7 ms. The remainder is in Dart: constructing and merging
**772** `ReviewState`/`PositionKnowledgeState` objects (491 returned after merge),
plus `toReviewState()` per knowledge row.

**Not guessed at.** Two plausible explanations were tested and refuted; a third
guess would be indistinguishable from the two that were wrong. Closing this needs a
profiler run (`--observe` / allocation tracking), not another inference.

#### What this changes

The first pass's "add an index" implication is dead — there is nothing to index.
Any fix has to be on the Dart side: either stop materialising all 772 rows to
count them, or find the ~13 ms above. **Neither is decided here**, because Q1 in
`docs/open-questions.md` asks whether the pause matters to the owner at all.

### Third pass — the measurement is noisier than the target (2026-10-14)

Three more components ruled out, then the measurement itself turned out to be the
problem.

**Ruled out:** `toReviewState()` being heavy (an 8-field copy); FFI driver
marshalling (raw fetch through `sqflite_common_ffi` is **3.05 ms** for both tables
against python's sqlite3 at 0.87 ms — the Dart driver is ~3.5x slower, still far
too small); and column width (single-column fetch 0.68 ms vs 1.66 ms for
`SELECT *`).

**The finding.** `getAllReviewStates()` has measured **16 ms, 29 ms and 36 ms** for
the same call on the same database, varying only by harness and measurement order.
Within one harness the spread is 20.4–27.8 ms.

So **"76% of `getDueSummary`" and "~13 ms unattributed" are both unreliable**, and
any optimisation chosen on those numbers is chosen on noise. The likely cause is
allocation and GC — 772 objects per call, fifteen calls back to back — but that is
a hypothesis, not a measurement, and is recorded as one.

**What this blocks.** Not code — the next step. A harness that controls for
measurement order and reports spread rather than a single median. Until that
exists, a change that appears to halve the cost may have halved nothing.

### Fourth pass — real library scale jump: 31k decisions and the true bottleneck (2026-10-15)

Following bulk study import (#131, #134), the owner's library grew by 60x:
- **63 studies** (from 11)
- **312 chapters** (from 25)
- **31,182 decisions** (from 528)
- **25,102 distinct canonicalStateId** (from 66)
- Database size: 35 MiB with WAL checkpointed

At 31,182 decisions, `getDueSummary()` jumped from **20 ms to ~512 ms**.
This 60x scale jump completely shifted the bottleneck and made the true costs
obvious:

1. **Move decoding in `getAllDecisions()` dominates (`186 ms` / 66%)**:
   `getAllDecisions()` parses JSON move lists for all 31,182 decisions, even
   though `_DueTally` only uses `id, studyId, chapterId, canonicalStateId`.
   -> Handed off to **PERF-FIX-33**.

2. **143 sequential SQLite queries for ~400 rows (`~80 ms`)**:
   `_loadReviewData` chunked 32,000 decision IDs and 25,102 canonical IDs into
   400-item `IN` queries (80 queries for review state, 63 queries for knowledge
   state). The two tables hold only 427 and 349 rows! Querying 143 times over
   FFI to find 400 rows is pathological.
   -> Handed off to **PERF-FIX-34**.

3. **Date parsing overhead (`~14 ms`)**:
   General-purpose `DateTime.parse` costs ~5-6 µs on real FFI strings. Only
   `nextDueAt` is needed for the summary, yet 3-4 dates per row are parsed.
   -> Handed off to **PERF-FIX-35**.

4. **Redundant full-library tallying on scope changes (`~500 ms` hitch)**:
   Switching between White/Black drawers or tapping a study re-runs the entire
   31k-decision pipeline, even though only the active scope filter changed.
   -> Handed off to **PERF-FIX-36**.

### Fifth pass — an order-controlled instrument (2026-10-19)

Pass three blocked on: *"a harness that controls for measurement order and
reports spread rather than a single median. Until that exists, a change that
appears to halve the cost may have halved nothing."* That harness exists now —
the second test in `test/perf/due_summary_attribution_test.dart`:

- warmup rounds, then 10 rounds x 7 calls, one sample of each call per round,
  the call order rotated every round so no call owns a fixed slot;
- output per call: min / p25 / median / p75 / max, plus the chronological
  sequence for `getAllReviewStates` and `getAllDecisions`, so the pure shape of
  the spread is visible in the log.

Measured twice against a copy of the current library (31,182 decisions,
25,102 canonical ids):

| call | run A min/med/max | run B min/med/max |
|---|---|---|
| `getAllReviewStates()` | 12.4 / 17.7 / **48.7** ms | 10.4 / 11.0 / 20.5 ms |
| `getAllDecisions()` | 147.9 / 181.3 / **271.6** ms | 120.5 / 130.6 / 155.7 ms |
| `getDueSummary()` total (sequential block) | — | 152.5 ms |
| `parseUtcIso` x1743 (post PERF-FIX-35) | — | 0.38 ms vs 2.49 ms `DateTime.parse` |

Two verdicts.

**1. Within one process, the rotation does its job.** Run A's
`getAllReviewStates` outliers (44.6 and 48.7 ms) fall at rounds 4 and 8 of 10,
at two different positions in the rotation, while the same call produced 12.6
and 12.4 ms samples in the same process. The pauses are real interruptions —
allocation and GC, as pass three hypothesised — not artifacts of where a call
happens to sit in a fixed sequence. A single median can now be shown to be what
it is: one sample of a distribution whose p75 sits 21% away from its min even
for small calls.

**2. Across processes, the same harness still moves.** Minutes apart, unchanged
code, same database copy: `getAllReviewStates` median 17.7 -> 11.0 ms,
`getAllDecisions` 181.3 -> 130.6 ms. So the practice rule for any future
before/after claim: measure before and after **in the same process**, report
the band rather than the median, and treat a sub-band difference as
unconcluded rather than as a win.

The second pass's "16.7 ms, 76% of getDueSummary" and the third pass's ~13 ms
unattributed residue both belonged to the 519-decision scale and were found
noisy by this very instrument before they could mislead anyone. At the current
31k scale the summary is dominated by decision loading (`getAllDecisions()` raw
~131-181 ms; the summary's own `getTallyDecisions()` ~62-96 ms after
PERF-FIX-33 slimmed the tally path), which the handed-off
PERF-FIX-33/34/35/36 already addressed. No further attribution is owed on the
old numbers; the instrument change is the deliverable of this pass.


### Reproducing

```bash
cp ~/.local/share/org.chesssrs.chess_srs/chess_srs.db{,-wal,-shm} /tmp/perf/
CHESS_SRS_PERF_DB=/tmp/perf/chess_srs.db \
  fvm flutter test test/perf/real_library_session_cost_test.dart
```

The `-wal` sidecar is required: this database has a 4 MiB write-ahead log, and
copying only the `.db` yields a snapshot missing recent transactions.
