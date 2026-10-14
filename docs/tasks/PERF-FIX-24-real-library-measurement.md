# PERF-FIX-24 — Measure the review path against a real library, not a synthetic one

> **CLAIMED 2026-10-14 by OpenCode (Space Bunny Free)** — branch
> `perf/real-library-measurement`, in progress. **Do not pick this up.** If this
> banner is stale (branch merged or abandoned), remove it before starting.

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