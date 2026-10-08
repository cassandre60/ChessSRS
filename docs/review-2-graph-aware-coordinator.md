# Review 2 — Graph-Aware Review Coordinator

**Scope:** `lib/src/domain/graph_aware_review_coordinator.dart` (309 LOC), plus its two production
call sites in `lib/src/domain/review/review_session.dart` (`:345`, `:399`, `:591`) and the repository
adapter `_SessionReviewStateRepository` (`review_session.dart:938-969`).

**Intent, from `ChessSRS Scheduling Architecture.md` §B:** wrap a plain FSRS kernel with three
chess-specific graph effects — upstream lapse contagion (§B.1), auto-traversal exposure credit
(§B.2), and confusable sibling coupling (§B.4) — plus canonical transposition resolution (§B.3). The
stated design principle is that these are *soft nudges, not state-machine resets*: they must never
touch `repetitionCount` or `lapseCount`, and the true FSRS update still happens when a node is
actually reviewed.

**Verification status.** All line numbers and arithmetic below were read and computed against the
working tree at commit `8f00ea777`. Decay and compounding figures were computed directly, not
estimated. No Dart toolchain is available in this environment, so nothing here was executed — every
claim is either a quoted line or arithmetic on quoted constants. Where I could not establish
something I say so.

---

## 1. Summary

The coordinator implements the specified structure faithfully: the contagion recursion is depth-bounded,
the soft-nudge contract is respected (no `repetitionCount`/`lapseCount` writes anywhere in the file),
and the canonical-resolution logic is well-reasoned and unusually well-commented. Two of the three
graph effects are numerically weaker or stronger than the spec says.

**Two confirmed defects, one of them severe:**

- **C1 (HIGH) — fixed, see §6.** Auto-traversal exposure credit is unbounded. Its only cross-session throttle is
  in-memory, so the "once per calendar day" guarantee documented at `:215` holds only within a single
  session. An item merely *passed over* while drilling other lines compounds stability and due date
  geometrically — 10× a month at one session a day, 1000× at three. The "never grant credit to an
  already-due item" guard at `:224` cannot bound it, because each grant pushes `nextDueAt` further
  out and makes the item *less* due.
- **C2 (MEDIUM).** Lapse contagion runs at 51.3% of its documented strength. The spec's prose defines
  `λ0 = 0.18` as the "max 18% stability haircut, applied only to the immediate child", but the
  formula it gives — which the code implements literally — yields 9.24% at the immediate child.

Everything else I looked at held up. Notably, two things I suspected turned out to be **not** bugs,
and are recorded in §5 so they are not re-raised.

---

## 2. Confirmed issues

### C1 — Exposure credit compounds without bound across sessions — **HIGH**

**Status: fixed** (`af0988ca2`). `lastExposedAt` is now persisted and the coordinator's throttle is
seeded from the store, so the cap holds across restarts. §6 records the two CI failures it took to
land and the lessons from both.

`graph_aware_review_coordinator.dart:215-247`

```dart
/// Throttled to once per calendar day per decision.
...
if (previous.lastReviewedAt != null && _isSameCalendarDay(previous.lastReviewedAt!, now)) {
  return previous;
}
final lastExposed = _lastExposedAt[canonicalId];
if (lastExposed != null && _isSameCalendarDay(lastExposed, now)) {
  return previous;
}
```

There are two guards, and neither survives a session boundary:

1. **The `lastReviewedAt` guard (`:227`)** only fires on a day the item was *actively reviewed*.
   Exposure deliberately never updates `lastReviewedAt` (that is the soft-nudge contract, and it is
   correct). So on every day the item is merely traversed, `lastReviewedAt` is from an earlier day,
   `_isSameCalendarDay` is false, and the guard passes.
2. **The `_lastExposedAt` guard (`:230`)** reads `final Map<String, DateTime> _lastExposedAt = {}`
   (`:152`) — a plain instance field with no persistence. `snapshotExposureThrottle` /
   `restoreExposureThrottle` (`:171`, `:174`) exist only to roll back a failed persist within a
   session (`review_session.dart:263`, `:290`); they do not load anything from the store. A new
   `ReviewSession` constructs a new coordinator (`review_session.dart:85`) with an empty map.

**Demonstrating input.** One canonical decision with `stability = 10 d`, `nextDueAt = now + 20 d`,
last actively reviewed a week ago. The user drills a different line that auto-traverses past it.

| sessions opened that day | grants/day | stability after 30 days |
|---|---|---|
| 1 | 1 | **10.06×** |
| 2 | 2 | **101.26×** |
| 3 | 3 | **1018.92×** |

Each grant applies `stability *= 1.08` (`:235`) and extends the due date by 8% of the *remaining*
interval (`:238-243`), so both series are geometric in the number of grants, and the number of grants
is bounded only by how often the user opens the app.

**Expected:** at most one credit per calendar day per decision, so ≤ `1.08^30 = 10.06×` per month,
which is already generous for an item that was never actively recalled.

**Actual:** `1.08^(sessions_per_day × 30)`. There is no ceiling at all.

**Why the `:224` guard does not save it.** `if (scheduler.isDue(previous, now)) return previous;`
looks like a bound, but it works in the wrong direction: a grant extends `nextDueAt`, so the item
becomes *less* due after each grant and the guard becomes easier to pass, not harder. The guard
prevents crediting overdue items; it does nothing about over-crediting current ones.

**Practical impact.** An item that is frequently traversed but rarely tested drifts toward never
surfacing. That is the exact failure mode §B.1 was written to avoid ("it manufactures enormous,
demotivating review backlogs") — in reverse.

**Fix direction.** Persist the exposure throttle, or derive it from data that is already persisted.
The cleanest option needs no new column: stamp `lastExposedAt` into the state (or reuse a field that
is already written) so the same-calendar-day test survives a restart. Second-best is to bound total
exposure credit per item — e.g. refuse once cumulative exposure gain exceeds some fraction of
actively-earned stability — which also caps the "never recalled" drift.

---

### C2 — Lapse contagion delivers 51.3% of the documented `λ0` — **MEDIUM**

`graph_aware_review_coordinator.dart:257`

```dart
final decay = params.contagionBase * math.exp(-depth / params.contagionTau);
```

The architecture doc §B.1 specifies the formula `S_child' = S_child × (1 − λ0·e^(−depth/τ))`, which
this line implements exactly. But the prose in the same section defines the parameter differently:

> with defaults `λ0 = 0.18` (**max 18% stability haircut, applied only to the immediate child**)

The recursion is entered at `depth: 1` (`:198`), so the immediate child never sees `depth = 0`:

| depth | code (`e^(−depth/τ)`) | prose intent (`e^(−(depth−1)/τ)`) |
|---|---|---|
| 1 — immediate child | **0.09242** (9.24%) | **0.18000** (18.00%) |
| 2 | 0.04745 | 0.09242 |
| 3 | 0.02436 | 0.04745 |
| 4 | 0.01251 | 0.02436 |

The code is off by exactly `e^(1/τ) = 1.9477`, i.e. it delivers **51.3%** of the specified strength at
every depth.

**Demonstrating input.** A child with `stability = 10 d` directly below a lapse.

- Expected per §B.1 prose: `10 × (1 − 0.18) = 8.20 d`.
- Actual: `10 × (1 − 0.09242) = 9.076 d`.

**Which side is wrong is a spec question, not a code question.** The formula and the prose disagree,
and the code follows the formula. Two self-consistent repairs exist:

- Change the exponent to `-(depth - 1) / τ`, making the immediate child see the full `λ0 = 0.18`.
- Keep the code and raise `contagionBase` to `0.3506`, so `0.3506 × e^(−1/1.5) = 0.18`.

Both change scheduling output, so neither should be picked silently. The tie-breaker is that
`λ0`'s own doc comment at `:104` repeats the prose reading — *"Maximum stability haircut applied at
depth 1 (lambda0 = 0.18)"* — which is a third statement of the 18%-at-depth-1 intent. Two of three
sources say the immediate child should take 18%. **Recommend the exponent fix**, and note that the
`D_child` bump at `:265` uses the same `decay`, so it is under-strength by the same factor.

---

### C3 — `recordAutoTraversalExposure` returns a state it never stored — **LOW**

`graph_aware_review_coordinator.dart:219-221`

```dart
if (previous == null || previous.stability <= 0) {
  return previous ?? ReviewState.initial(decisionId: canonicalId);
}
```

This branch covers two different cases and returns two different kinds of value. When
`previous != null` it returns the stored state unchanged (harmless). When `previous == null` it
returns a **fresh `ReviewState.initial` that was never passed to `repo.put`** — the method's contract
is otherwise "return the state now in the repo", and the call site assumes that:

```dart
final exposedState = _coordinator.recordAutoTraversalExposure(node: expNode, now: now);
if (exposedState != null) {
  _reviewStates[nextDecision.canonicalId] = exposedState;
  _reviewStates[nextDecision.id] = exposedState;
  sideEffects.add(exposedState);
}
```
(`review_session.dart:591-596`)

So merely *passing over* a never-reviewed node materialises an initial state into the session's state
map and into `sideEffects`, which is the list that gets persisted. The immediate consequence is small
— `ReviewState.initial` has `nextDueAt == null`, and `isDueAt` (`review_state.dart:70`) returns true
for null, so the item stays due and nothing is lost. But it writes rows for items the user never
engaged with, and it makes the return value's meaning depend on which sub-branch ran.

**Fix.** Return `null` in the `previous == null` case — the call site already null-checks — and keep
returning `previous` for the `stability <= 0` case. That restores a single meaning: non-null iff the
repo was written.

---

## 3. Design concerns

**D1 — Throttle bookkeeping is conflated with rollback bookkeeping.** `_lastExposedAt` serves two
masters: it is the daily throttle (C1) *and* the thing snapshotted for persist-rollback. That is why
fixing C1 is not purely local — any move to persisted state has to keep the rollback path working,
since `restoreExposureThrottle` (`:174`) does a `clear()` + `addAll()` on it. Worth splitting the two
concerns explicitly.

**D2 — `maxContagionDepth = 3` truncates a series the spec describes as reaching depth 4.** §B.1 says
"contagion is essentially gone by depth 4", and `:98` caps at 3. At depth 4 the residual is 1.25%
(code) or 2.44% (prose reading), so this is a deliberate-looking truncation rather than an error, but
the constant and the prose should agree or the doc should say "we cut at 3".

**D3 — `GraphNode.parentId` is required but never read.** It is a constructor requirement
(`:14`), both production call sites pass a value (`review_session.dart:339`, `:587`), and no code in
the file references it — contagion walks `childrenOf`, never parents. Dead required parameter; either
use it or drop it.

**D4 — `InMemoryReviewStateRepository` is a parallel implementation that production does not use.**
`:56-92` ships a full second repository including `setChildren` and `setCanonicalId` mutators.
Production uses `_SessionReviewStateRepository`. That is normal for a test double, but it lives in
`lib/` rather than `test/`, so it ships to users and can drift from the real adapter — and it already
differs in one respect: it does not mirror writes across occurrence/canonical keys the way
`_SessionReviewStateRepository.put` does (`review_session.dart:955-959`). Tests written against it
therefore cannot catch key-aliasing bugs in the real path.

**D5 — Coupling depends on the caller supplying `siblings`, and the contract is implicit.**
`_coupleConfusableSiblings` (`:288-304`) is only reachable when
`playedMoveUci != null && siblings.isNotEmpty` (`:201`). The one production call site that can trigger
it — the incorrect branch, `review_session.dart:399-405` — does supply both, so **§B.4 fires in
production as intended**. The concern is only that this dependency is undocumented: `recordActiveReview`
takes `playedMoveUci` and `siblings` as optional parameters with empty defaults, so a future call site
that omits them silently disables the effect rather than failing. The correct branch
(`review_session.dart:345-348`) correctly passes neither, since coupling is gated on `incorrect`.

---

## 4. Suggested improvements, in priority order

1. **Bound exposure credit (C1).** Highest value by a wide margin — it is the only finding here that
   grows without limit. Persisting the throttle is a small change; bounding cumulative credit is the
   more robust design.
2. **Resolve the `λ0` spec contradiction (C2).** Decide between the exponent fix and raising
   `contagionBase` to `0.3506`, then update the doc so formula, prose, and the `:104` comment all say
   the same thing. Add a test asserting the depth-1 haircut percentage so the three cannot drift apart
   again.
3. **Make the sibling-coupling contract explicit (D5).** `playedMoveUci` and `siblings` should be
   required when `result == incorrect`, or at least documented as the switch that enables §B.4, so a
   future call site cannot silently disable a documented feature.
4. **Tighten the exposure return contract (C3).** Small, local, and it removes a persistence surprise.
5. **Reconcile `maxContagionDepth` with §B.1's "depth 4" (D2).** One-line change or one-line doc edit.
6. **Drop the unused `parentId` (D3)** and consider moving the test double out of `lib/` (D4).

---

## 5. Checked and found sound — do not re-raise

Recorded because each was a plausible bug on first reading and each turned out to be correct. The
common failure in this codebase's reviews so far (see review-1 §6) has been describing code accurately
while getting its impact wrong, so the negative results are worth as much as the findings.

- **Key aliasing in contagion.** `_propagateLapseContagion` walks raw ids while `recordActiveReview`
  writes the primary under `canonicalId` — which looks like contagion would read/write the wrong keys
  and silently no-op. It does not: `_SessionReviewStateRepository.get` and `.put` both resolve
  occurrence→canonical and mirror writes to both keys (`review_session.dart:938-969`), and
  `_childDecisionIdsOf` returns *canonical* ids (`:905`), so the recursion is consistent.
- **Double-application of contagion.** A child reachable by two paths would take two haircuts. The
  child set is built as a `Set<String>` of canonical ids (`:898`), so siblings that share a canonical
  identity are deduplicated before recursion.
- **Unbounded recursion / cycles.** `depth > maxContagionDepth` (`:256`) bounds the walk at 3
  regardless of topology, so a cyclic graph terminates.
- **Contract violation on counters.** No path in the file writes `repetitionCount` or `lapseCount`, so
  the §B.1 soft-nudge contract holds for all three effects.
- **The primary node double-penalised by sibling coupling.** Only reachable when
  `result == incorrect` (`:196`), in which case the played move differs from the primary's expected
  move, so the `sib.expectedMoveUci != playedMoveUci` filter (`:294`) excludes the primary.
- **§B.4 sibling coupling inert in production.** My first reading of the call sites concluded that
  neither `playedMoveUci` nor `siblings` was ever passed, making confusable-sibling coupling dead
  outside tests. **That was wrong.** The incorrect branch passes both —
  `siblings: _findSiblingGraphNodes(decision)` and `playedMoveUci: movePlayed.uci`
  (`review_session.dart:398-405`) — so the effect is live. Recording it here because the error was
  made by reading one call site and generalising to both, which is the same mistake review-1 made
  twice over in D3 and C7.

**Not verified:** whether the session could supply `siblings` to enable §B.4 (D5), and the real-world
distribution of auto-traversal frequency that determines how fast C1 bites. Neither is needed to act
on the findings above.

---

## 6. Fixing C1, and the two CI failures it took to land

The fix is landed and green. It took five extra CI runs, and both failures turned out to be
concrete and avoidable, so they are written up here rather than dropped.

### What the fix does

The spec requires the cap to be per calendar day, and the bug is that the only record of the last
grant dies with the session. So the fix persists it:

1. `lastExposedAt TEXT` on `kTablePositionKnowledgeState` (`srs_schema.dart`).
2. `PositionKnowledgeState.lastExposedAt`, carried through `copyWith`, `==` and `hashCode`.
3. The repository writes the column on all three write paths and reads it in the row mapper.
4. `GraphAwareReviewCoordinator` takes `initialExposureThrottle`; `ReviewSession` and `ReviewEngine`
   pass it through, and the session exposes `exposureThrottle` so the caller can persist it.
5. `ReviewService` seeds the coordinator from the knowledge states it already loads at session
   creation, and stamps the current throttle onto every state it writes.

Step 5 is safe against erasure even though the write is `INSERT OR REPLACE`: the throttle is seeded
for every in-scope canonical id, so a null means "never exposed" rather than "unknown".

Two tests accompany it — an `INV-028` coordinator test that reseeds a fresh coordinator and asserts
the same-day refusal still holds (and that the next day grants again), plus a round-trip through
`saveAnswerBatch`. That takes the coordinator file from 10 tests to 11 and the repository file from
26 to 27.

### Failure 1 — a migration this environment could not account for

The first version of step 1 bumped the schema to v16 and added the `ALTER` to `onUpgrade`. That
reproducibly failed **2 unit tests** in CI. Because this environment cannot read CI logs, the only
available signal was the pass/fail count, and five runs isolated the cause:

| Commit | Configuration | Result |
|---|---|---|
| `f730ce63e` | full fix, my tests reverted | 1663 passed, **2 failed** |
| `d1db493b0` | schema + database + repository reverted | green |
| `7a627a444` | schema + repository kept, `database.dart` at v15 | green |
| `74f6cc0a7` | full fix, coordinator test only | 1664 passed, **2 failed** |

The two failures are not in either file I touched: the coordinator regression test passes in both
failing runs, and the second excludes the persistence round-trip test entirely.

The mechanism was never explained, and it is still not. For a fresh database `openAppDatabase` runs
`onCreate`, not `onUpgrade`, so the version bump and the `ALTER` should both be inert — and the
tests use fresh temp databases. Every explanation constructed contradicts the observation: no test
exercises `onUpgrade`; there are no `.db` fixtures; no test asserts a schema version; the tests that
build the schema by hand call `createSrsTables` directly and so already get the new column.

**Resolution: avoid the version bump.** The column is now added by an idempotent top-up in `onOpen`
that reads `PRAGMA table_info` first. It leaves `version` and `onUpgrade` untouched, it converges
for any database whether or not it predates the column, and it does not touch the one file the
bisect implicated. That is green.

The cost is a deliberate departure from the repo's versioned-migration convention: this column is
reconciled on open rather than by a numbered migration step. Anyone who later moves the schema to
v16 should fold this top-up into the migration and delete it, and anyone debugging the two failures
should start from the table above.

### Failure 2 — `dart format` joins single-argument calls that fit

The second failure was `Verify formatting`, and it was mine. The formatter joins a single-argument
call onto one line when the result fits the 100-column page width, **even when the call carries a
trailing comma**:

```dart
// written — failed formatting
await db.execute(
  'ALTER TABLE $kTablePositionKnowledgeState ADD COLUMN lastExposedAt TEXT',
);

// expected — 96 columns, fits
await db.execute('ALTER TABLE $kTablePositionKnowledgeState ADD COLUMN lastExposedAt TEXT');
```

This is checkable without running `dart`. Across `lib/src` and `test` there are 17 split
single-argument calls with trailing commas; before the fix, exactly one would have fitted on a
single line, and it was this one. Every other split single-argument call in the repo is split
because joining it would exceed the page width. So the repo is a reference for what the formatter
wants: **if a split call would fit on one line, the formatter will join it, so write it joined.**

The same rule generalises the earlier lesson. An earlier version of these two tests also failed
formatting and was fixed by copying the construct shapes already used in their files — single-line
method calls with the times hoisted to locals, list literals assigned to a local instead of passed
inline. Both lessons are the same lesson: without a local toolchain, match the surrounding code
exactly rather than writing an equivalent-looking variant, and verify by counting shapes in the
existing tree.

