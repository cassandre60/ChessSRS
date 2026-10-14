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

### Reproducing

```bash
cp ~/.local/share/org.chesssrs.chess_srs/chess_srs.db{,-wal,-shm} /tmp/perf/
CHESS_SRS_PERF_DB=/tmp/perf/chess_srs.db \
  fvm flutter test test/perf/real_library_session_cost_test.dart
```

The `-wal` sidecar is required: this database has a 4 MiB write-ahead log, and
copying only the `.db` yields a snapshot missing recent transactions.
