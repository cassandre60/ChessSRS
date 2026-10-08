# Review 4 — Orchestration & Persistence Round-Trip

**Scope:** `lib/src/review/review_service.dart` (689 LOC), the persistence boundary in
`lib/src/persistence/sqlite_study_repository.dart` (992 LOC) and `srs_schema.dart` (127 LOC), the JSON
adapters in `json_adapters.dart`, and `lib/src/domain/clock.dart`. `review_controller.dart` (1508 LOC)
was reviewed only where it calls into the persist path.

**Intent.** Take a graded answer from the session, convert it into the stored representation, write it
atomically, and roll the session back if the write fails. Reading back must reproduce what was written.
This review's boundary was set deliberately to include the **round-trip** — field mapping and precision
— not just the orchestration.

**Verification status.** All line numbers were read against the working tree at `2646e0221` and each
citation re-checked by grepping for the quoted text. Reachability was checked before severity was
assigned. No Dart toolchain is available here, so nothing was executed.

---

## 1. Summary

The orchestration is the strongest part of the codebase reviewed so far. Persistence is atomic (a
single `_db.transaction` with one `batch.commit`), the rollback contract is correct and symmetric, and
`deleteStudy` handles the genuinely hard case — a canonical position shared with a surviving study —
with an explicit guard rather than an optimistic delete. The session load path queries both key kinds
and reconciles them correctly.

The defects are in the **field mapping across the boundary**, which is exactly where the review scope
said to look.

**Three confirmed defects:**

- **C1 (MEDIUM).** Latency telemetry is erased on every persisted answer. The `ReviewState` →
  `PositionKnowledgeState` conversion cannot carry it, and the write uses `INSERT OR REPLACE`, so the
  stored value is deleted rather than preserved. Not reachable today only because nothing populates
  the field yet.
- **C2 (MEDIUM).** Timestamps are local wall-clock written without an offset and read back as local, so
  changing the device timezone shifts every stored due date. This is review 1's D4, now traced
  end-to-end through clock, write, and read.
- **C3 (LOW).** Sub-millisecond precision is truncated on the round-trip. Immaterial at day scale;
  recorded so it is not mistaken for a bug later.

---

## 2. Confirmed issues

### C1 — Every persisted answer erases latency telemetry — **MEDIUM**

`review_service.dart:287-296`, `:303-312`, `:358-367`; `sqlite_study_repository.dart:573-584`

The service converts a `ReviewState` into a `PositionKnowledgeState` in three places, each copying the
same eight fields:

```dart
final kState = PositionKnowledgeState(
  canonicalId: canonicalId,
  firstReviewedAt: result.updatedState.firstReviewedAt,
  lastReviewedAt: result.updatedState.lastReviewedAt,
  nextDueAt: result.updatedState.nextDueAt,
  repetitionCount: result.updatedState.repetitionCount,
  lapseCount: result.updatedState.lapseCount,
  stability: result.updatedState.stability,
  difficulty: result.updatedState.difficulty,
);
```

`latencyEmaMs` and `latencySampleCount` are absent — and they **cannot** be present, because
`ReviewState` has no such fields (`review_state.dart:40-59` declares exactly eight). The domain already
has the one-way conversion `PositionKnowledgeState.toReviewState()`, which drops latency for the same
reason; there is no inverse that preserves it.

The write then lands with `conflictAlgorithm: ConflictAlgorithm.replace` (`:584`), which SQLite
implements as `INSERT OR REPLACE` — **delete the existing row, then insert**. The columns are supplied
explicitly from the state that lacks them (`:582-583`), so:

| column | before | after any answer |
|---|---|---|
| `latencyEmaMs` | whatever was measured | **NULL** |
| `latencySampleCount` | however many samples | **0** |

**Scope of the erasure.** `allKStates` contains the answered position *plus* every side-effect state —
lapse-contagion children, confusable siblings, and every auto-traversed decision
(`review_service.dart:300-314`). So a single answer that walks a 6-ply line resets latency on all
seven positions, none of which the user was even asked about.

**Why it is only MEDIUM.** Nothing populates the field yet: grepping `latencyEmaMs:` across `lib/`
returns only `copyWith` (`position_knowledge_state.dart:122`) and the row reader
(`sqlite_study_repository.dart:711`). There is no producer, so there is nothing to lose today. But the
architecture reserves it explicitly — *"Latency (`latencyEmaMs`) is preserved as optional post-hoc
telemetry only"* — and the schema carries the columns (`srs_schema.dart:83-84`). The moment telemetry
is wired up, it will be destroyed on every answer, silently, with no error and no test failure.

**Expected:** a round-trip that preserves columns the caller does not mention.

**Fix.** Two parts, both small:
1. Add `PositionKnowledgeState.fromReviewState(ReviewState, {String? canonicalId})` as the inverse of
   the existing `toReviewState()`, and use it at all three sites. This makes the omission impossible
   rather than merely fixed — see D1.
2. Change the knowledge-state write from `INSERT OR REPLACE` to an upsert that touches only the columns
   being written, or read-modify-write the latency fields. Option 1 alone does not fix the erasure,
   because a correct conversion still has nothing to copy from a `ReviewState`.

---

### C2 — Timestamps are local time with no offset, so a timezone change shifts every due date — **MEDIUM**

`clock.dart:19`; `sqlite_study_repository.dart:548`, `:969-971`; `json_adapters.dart`

Traced end-to-end:

1. **Produced local.** `SystemClock.now() => DateTime.now()` (`clock.dart:19`) — a local `DateTime`.
2. **Written without an offset.** `s.firstReviewedAt?.toIso8601String()` (`:548`, and the same at
   `:574-576` and in `json_adapters.dart`). For a local `DateTime`, Dart emits
   `2026-10-08T10:00:00.000` — **no `Z`, no offset**. A UTC `DateTime` would emit the `Z`.
3. **Read back as local.** `DateTime.parse(first)` (`:969-971`) interprets an offset-less string in the
   reader's *current* zone.

**Demonstrating input.** A card becomes due at 10:00 in Tunis (UTC+1) and is stored as
`2026-10-08T10:00:00.000`. The user flies to New York (UTC−4) and opens the app. `DateTime.parse`
yields 10:00 New York, which is 15:00 Tunis. The card that was due is now scheduled five hours later
than the instant it was earned — and every other stored date shifts with it.

The reverse direction is worse: a card due at 10:00 New York read in Tunis becomes due at 10:00 Tunis,
i.e. **four hours earlier than intended**, and items whose `nextDueAt` is still in the future can flip
to overdue on landing, manufacturing a review backlog from a plane ticket.

**Expected:** an absolute instant. Either `toUtc().toIso8601String()` on write plus
`DateTime.parse(...).toUtc()` on read, or epoch-milliseconds in an `INTEGER` column.

**Fix, and the honest caveat about migration.** The write side is a one-line change per site. Existing
rows are the problem: the stored strings carry no offset, so the zone they were written in is not
recoverable from the data. The pragmatic migration is to reinterpret existing values as UTC in place —
a one-time shift of at most one timezone offset for pre-existing cards, after which all new writes are
correct. That is strictly better than the status quo, where *every* future zone change shifts
*everything*. This is review 1's D4 and it wants its own PR.

---

### C3 — Sub-millisecond precision is truncated — **LOW**

`sqlite_study_repository.dart:548`, `:969-971`

Dart's `DateTime` carries microsecond precision; `toIso8601String()` emits three decimal places. So a
round-trip loses up to 999 µs.

Recorded for completeness, not as a defect: SRS intervals here are measured in days
(`maxIntervalDays = 1095`), and the smallest meaningful quantity in the scheduler is
`minIntervalDays = 1/1440` (one minute). A microsecond is nine orders of magnitude below anything the
scheduler can express. If the timestamp columns ever become epoch-milliseconds as part of the C2 fix,
this disappears for free.

---

## 3. Design concerns

**D1 — The same eight-field conversion is hand-written three times.** `review_service.dart:287-296`,
`:303-312` and `:358-367` are identical copies. Any field added to `PositionKnowledgeState` must be
added in three places or it is silently dropped on every write — which is precisely the mechanism by
which C1 exists. The domain already owns `toReviewState()`; the missing inverse is the fix. This is
the same class of drift review 3 found at `review_session.dart:308`/`:475`, so it is a codebase-wide
pattern, not a one-off.

**D2 — `saveAnswerBatch` writes `kTableSrsReviewState` twice per state.** Once keyed by the canonical
SHA-1 (`:586-595`) and once per occurrence id via `INSERT … SELECT … WHERE canonicalStateId = ?`
(`:597-617`). Verified sound — the read path queries both key kinds — but it is undocumented and
doubles the row volume on the table for no stated reason. Worth a comment saying the mirroring is
deliberate and what reads depend on it.

**D3 — `deleteDecisionsByStudy` is dead code with a trap.** `:505-507` deletes only from
`kTableSrsDecision`, leaving review states, knowledge states and events behind. It has **no production
callers** — only the interface declaration at `study_repository.dart:74`. The live path is
`deleteStudy` (`:182`), which does the cleanup correctly. If anyone wires up the shorter method they
inherit an orphan leak. Either delete it or give it the same guard `deleteStudy` has.

**D4 — `getReviewStatesByDecisions` is called with a mixed id set.** `review_service.dart:226-229`
passes `{...decisionIds, ...canonicalIds}`. That is correct given the mirroring in D2, but the method
name says "by decisions" while half the argument is canonical ids. The behaviour is right; the name
will mislead whoever maintains it next.

---

## 4. Suggested improvements, in priority order

1. **Fix the timezone handling (C2).** It is the only finding here that corrupts scheduling for real
   users today, and it needs no new feature to trigger — just a flight. Own PR, own migration.
2. **Add `PositionKnowledgeState.fromReviewState` and use it at all three sites (D1, then C1 part 1).**
   Removes the duplication that caused C1 and prevents the next field from being dropped the same way.
3. **Make the knowledge-state write non-destructive (C1 part 2).** Upsert only the columns being
   written, so columns the caller does not mention survive.
4. **Delete or fix `deleteDecisionsByStudy` (D3).**
5. **Document the review-state mirroring (D2)** and rename `getReviewStatesByDecisions` to reflect that
   it accepts both key kinds (D4).

---

## 5. Checked and found sound — do not re-raise

Each of these was a plausible bug on first reading. Recording them because the recurring failure in
this codebase's reviews has been describing code accurately while getting its impact wrong (review-1 §6).

- **`deleteStudy` orphaning shared positions.** It does not. Occurrence-keyed rows are deleted outright
  (`:222-231`); canonical-keyed rows are deleted only when no *surviving* study still references them,
  via the explicit `sharedGuard` subquery (`:241-243`, applied at `:244-262`). A transposition shared
  with another study keeps its history. This is the hard case and it is handled.
- **The double write to `kTableSrsReviewState` (D2) causing missed reads.** The session load path
  queries `{...decisionIds, ...canonicalIds}` (`review_service.dart:226-228`) and then overrides from
  `getKnowledgeStatesByCanonicalIds` (`:231-234`), so both key kinds resolve. The session's own lookup
  (`_reviewStates[decision.canonicalId] ?? _reviewStates[decision.id]`) matches.
- **Duplicate rows inflating the dashboard counts.** `getAllReviewStates()` results are folded into a
  map keyed by `decisionId` (`review_service.dart:411-413`), and the tally loops iterate *decisions*,
  not states. Extra map entries are never consulted.
- **`reviewStateToJson` / `reviewStateFromJson` losing fields.** They round-trip all eight fields
  (`json_adapters.dart`), including `difficulty`.
- **`firstReviewedAt` being reset on rewrite.** It is copied explicitly at all three conversion sites,
  so it survives `INSERT OR REPLACE`.
- **The persist-failure rollback being incomplete.** `checkpoint()` at `:281`/`:350`, `restoreCheckpoint`
  at `:322`/`:371`, then `rethrow`. The write is a single transaction with one `batch.commit`, so a
  failure leaves the store untouched and the session restored. Symmetric across `submitMove` and
  `retryMove`.
- **Review 1's C7 (the `?? 5.0` difficulty fallback).** Re-checked and still unreachable: both columns
  are `NOT NULL` (`srs_schema.dart:82`, `:101`) and every write supplies an explicit value. The two
  tables' *defaults* genuinely differ (0.0 vs 5.0), but a default only applies to a row inserted
  without the column, and no such insert exists.
- **`savePositionKnowledgeState` / `savePositionKnowledgeStates`.** Confirmed dead code, as review 1's
  D3 retraction found. Only `saveAnswerBatch` is live.

**Not established:** whether latency telemetry has a planned producer. C1's severity depends on it —
if the field is abandoned rather than reserved, C1 is a cleanup rather than a latent data-loss bug.
The schema columns and the architecture doc both suggest it is reserved, which is why it is rated
MEDIUM rather than LOW.
