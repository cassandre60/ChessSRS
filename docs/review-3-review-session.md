# Review 3 — Review Session & Engine

**Scope:** `lib/src/domain/review/review_session.dart` (996 LOC), `review_engine.dart` (64 LOC), and
the surrounding value types in `lib/src/domain/review/`. Focus is the state machine in `submitMove`
(`:298-455`), `retryMove` (`:461-501`), `_continueWithCorrectMove` (`:504-619`), `skip` (`:627-640`)
and `_advanceToNextDue` (`:646-670`).

**Intent.** Drive a repertoire review: present a due decision, grade the answer through the graph
coordinator (review 2), advance along the line auto-playing opponent replies and learned
continuations, honour the daily quota, and re-test anything the user failed before the session ends.
`ReviewMode.practice` must grade nothing; `ReviewMode.srs` grades and enforces the quota.

**Verification status.** All line numbers were read against the working tree at `d4737f609` and each
citation below was re-checked by grepping for the quoted text. Reachability was checked before
assigning severity — see §5 for what that ruled out. No Dart toolchain is available here, so nothing
was executed.

---

## 1. Summary

The core grading path is sound and the two subtlest pieces of it are correct: the corrected-false-start
guard from review 1's C2 is wired properly at `:329`, and practice mode is consistently excluded from
grading at `:334`, `:387` and `:583`. Transposition handling fails closed (`:754-798`), which is the
right default.

The problems are in the **bookkeeping around** the state machine, not in the grading. Two counters
that are supposed to describe the same thing count different things; the re-test-after-lapse promise
is silently voided by the quota check; and one positional list access is unguarded where every
neighbouring use of the same list is safe.

**Four confirmed defects, none severe in isolation**, and the highest-severity one is severe only
because of a compounding interaction with review 2's C1.

---

## 2. Confirmed issues

### C1 — `completedCount` and the quota counter count different things — **MEDIUM**

`review_session.dart:320`, `:363`, `:478-481`

Two counters track session progress and they are not kept in step:

| | `_completedDecisionIds` (quota) | `_completedCount` (progress) |
|---|---|---|
| type | `Set<String>` of canonical ids | `int` |
| `submitMove` correct | added, `:320` | incremented, `:363` |
| `retryMove` correct | added, `:481` | **never incremented** |
| lapse re-tested later | no change (already in set) | **incremented again** |

**Demonstrating input.** One due decision `D`, `ReviewMode.srs`.

1. User submits a wrong move → lapse recorded, `D` re-queued (`:435-441`), prompt unchanged.
2. User submits the correct move via `submitMove` → `isCorrectedFalseStart` is true so no SRS update
   (`:334`), but `_completedCount` is incremented unconditionally at `:363`. Now `1`.
3. `_advanceToNextDue` eventually pops `D` again — it was re-queued at the back — and the user is
   asked a second time.
4. Correct again → `_completedCount` is `2` for **one** decision.

`_completedDecisionIds` stays at `1` throughout, because it is a set. So after this sequence
`completedCount == 2` while `initialDueCount == 1`: the session reports having completed more
decisions than it started with.

Conversely, the `retryMove` path deliberately increments *only* the quota counter, per the comment at
`:478-480` — *"Counting it here is what stops a run of retries from exceeding the daily quota."* That
comment is right about the quota and says nothing about progress, so a session driven entirely through
`retryMove` ends with `completedCount == 0` while the quota is fully consumed.

**Why it matters less than it looks.** `completedCount` has **no production consumer** — a repo-wide
grep for `.completedCount` outside the session returns only
`test/review/review_engine_test.dart:182` and `test/review/review_service_test.dart:164`. It is
nevertheless public API and is checkpointed (`:262`, restored at `:289`), so it survives a restart and
will be wrong in whatever UI eventually binds to it.

**Expected:** one source of truth. `completedCount` should be `_completedDecisionIds.length`, which
makes the double-count impossible by construction and makes the two counters agree by definition
rather than by discipline.

---

### C2 — The daily quota silently discards re-queued lapses — **MEDIUM**

`review_session.dart:433-434` vs `:646-655`

The lapse handler re-queues with an explicit promise:

```dart
// Re-queue the failed decision at the end of the session queue
// so the user can re-test it before completing the session
```

But `_advanceToNextDue` opens with:

```dart
if (mode == ReviewMode.srs && remainingDailyQuota != null &&
    _completedDecisionIds.length >= remainingDailyQuota!) {
  _dueQueue.clear();
  _unbufferedQueue.clear();
  _currentPrompt = null;
  return;
}
```

**Demonstrating input.** `remainingDailyQuota = 10`. The user completes 9 decisions, lapses on the
10th, and then answers it correctly on the re-test. `_completedDecisionIds.length` reaches `10`, so the
next `_advanceToNextDue` **clears both queues** — including the re-queued lapse of the 10th decision,
which is still waiting for its re-test.

The re-test never happens and nothing records that it was skipped. Capping the day is a legitimate
policy, so the behaviour is defensible; what is not defensible is that the comment two hundred lines
above promises the opposite and no code or log notes the abandonment.

**Expected:** either keep re-queued lapses out of the quota cap (they are re-tests, not new work, and
the set already contains them so they cost nothing), or say plainly in the comment that reaching the
quota abandons pending re-tests.

---

### C3 — Auto-traversal picks the first user continuation and ignores the rest — **MEDIUM**

`review_session.dart:570`

```dart
final userChild = opponentChild.children.first;
```

The node model explicitly supports more than one child: `childForMove` (`repertoire_node.dart:97-102`)
iterates and returns the first match, and `_childDecisionIdsOf` (`:892-910`) loops over
`decision.expectedMoves` and collects *all* matching opponent children into a set. So multiplicity is
modelled and handled in two other places.

Here it is not. When the traversal auto-plays a learned user continuation, only `children.first` is
followed; every other continuation at that node is neither traversed nor granted exposure credit
(`:583-597`), so those decisions are invisible to §B.2 for the whole session.

**Why this is the highest-severity item here.** It is a *mitigating* factor, not an aggravating one —
but it interacts with review 2's C1. Over-crediting an item the user never recalled is bad; silently
under-crediting whole alternative lines is the same class of error in the other direction, and the two
cannot be reasoned about together while the traversal order depends on list position.

**Expected:** either the repertoire invariant is "a user node has exactly one continuation", in which
case `children.first` is correct and should be asserted and documented, or the traversal must visit all
of them. I could not establish which invariant holds — see §5.

---

### C4 — Unguarded positional access where every neighbour is safe — **LOW**

`review_session.dart:395`

```dart
expectedMoveUci: prompt.expectedMoves.first.uci,
```

`expectedMoves` is `TEXT NOT NULL` in the schema (`srs_schema.dart:54`) but is decoded from JSON by
`decodeExpectedMoves` (`json_adapters.dart:55-60`), which does `jsonDecode(raw) as List` with no
non-empty check. So the string `"[]"` is representable and yields an empty list, and `.first` on it
throws `StateError` mid-answer.

Every other consumer of the same list is safe:
`accepts()` uses `.any()` (`repertoire_decision.dart:63`), `_resolvePlayedMove` uses
`.where(...).firstOrNull` (`:740`), and the lapse log uses `.map(...).join(...)` (`:422`). Only `:395`
indexes positionally.

**Reachability not established.** I found no code path that writes an empty array — decisions are
constructed only at `sqlite_study_repository.dart:952` from rows written by the importer. So this is a
latent crash on malformed or hand-edited data, not a demonstrated one. Flagged because the fix is free:
`prompt.expectedMoves.firstOrNull?.uci` with a null guard, matching the style already used at `:740`.

---

### C5 — The two entry points disagree on identity in their fallback — **LOW**

`review_session.dart:308` vs `:475`

```dart
// submitMove
ReviewState.initial(decisionId: decision.canonicalId);
// retryMove
ReviewState.initial(decisionId: prompt.decision.id);
```

The same lookup — "state for this decision, or a fresh one" — falls back to the **canonical** id in one
method and the **occurrence** id in the other. Today this is harmless: both only run when no state
exists, and `retryMove` never persists the value it builds (it passes `updatedState: currentState`
straight into the result). But the two paths disagree about what identifies a decision, which is exactly
the kind of divergence that review 2 found the coordinator had already resolved carefully at
`:938-969`.

**Expected:** both use `canonicalId`, matching `RepertoireDecision.canonicalId`
(`repertoire_decision.dart:62`) and the coordinator.

---

## 3. Design concerns

**D1 — `submitMove` is 162 lines with two near-duplicate halves.** The correct branch (`:319-377`) and
the incorrect branch (`:378-454`) each build a `GraphNode`, call `_coordinator.recordActiveReview`,
write `_reviewStates` under both keys, and construct a `ReviewEvent`. The four shared statements are
copied rather than extracted, so a change to state-mirroring has to be made twice — and C5 is precisely
a case where the two copies already drifted.

**D2 — `movePlayed` is constructed three times from the same arguments.** `:312`, `:381` and `:490`
each build `RepertoireMove(from: from, to: to, promotion: promotion)`; the latter two shadow the outer
binding in their own scope. Harmless, but it obscures that the value is already available.

**D3 — Nothing marks a re-queued entry as a re-test.** The lapse handler pushes the same
`RepertoireDecision` object back onto a queue (`:435-441`). When it is later popped, the session cannot
tell a first attempt from a re-test except by consulting `_lapsedThisSession` — which is the mechanism
that makes C1's double-count possible and that C2's quota check ignores. An explicit re-test marker
would let all three sites reason about it directly.

**D4 — `continueAfterIncorrect()` is a one-line forwarder.** `:622-624` just calls
`_advanceToNextDue()`. It exists so callers do not have to know the private name, which is fine, but it
is the only such forwarder in the file and its name implies it does something to the incorrect state,
which it does not.

**D5 — Checkpoint fidelity depends on remembering to add fields.** `ReviewSessionCheckpoint`
(`:976-996`) must be updated whenever session state is added; `_lapsedThisSession` was threaded through
it as part of review 1's C2 fix. There is no compile-time link between a new mutable field and the
checkpoint, so the next addition can silently become non-restorable.

---

## 4. Suggested improvements, in priority order

1. **Make `completedCount` derive from `_completedDecisionIds.length` (C1).** One-line change, removes
   the double-count by construction, and makes the two counters agree by definition.
2. **Decide the quota-vs-re-test policy and write it down (C2).** Either exempt re-tests from the cap
   or correct the comment at `:433-434`. Right now the code and the comment promise different things.
3. **Establish the user-continuation invariant (C3).** Assert-and-document if a user node has exactly
   one continuation; otherwise traverse all of them. Until this is settled, §B.2 exposure credit is
   order-dependent.
4. **Use `firstOrNull` at `:395` (C4)** and align the two fallback keys at `:308`/`:475` (C5). Both
   free, both remove a divergence.
5. **Extract the shared grading block out of `submitMove` (D1).** This is what stops C5 recurring.
6. **Add a re-test marker (D3)** and consider a test asserting every mutable session field appears in
   `ReviewSessionCheckpoint` (D5).

---

## 5. Checked and found sound — do not re-raise

- **Corrected-false-start grading.** `:329` reads `_lapsedThisSession`, and `:334` skips the SRS
  update when it is set. A lapse followed by a successful re-test records exactly one lapse. This is
  review 1's C2 fix and it is wired correctly in both directions.
- **Practice mode grading nothing.** Guarded at `:334` (correct), `:387` (incorrect) and `:583`
  (exposure credit). All three paths bypass the coordinator.
- **Duplicate queue entries.** `skip()` (`:627-640`) appends without removing first, which looks like
  a duplicate risk, but the decision was already popped by `_advanceToNextDue`'s `removeAt(0)`. The
  lapse path removes before appending (`:435-436`). Neither produces a duplicate.
- **Transposition failing open.** `_resolvePlayedMove` (`:736-748`) returns the direct match first and
  only falls through to transposition when `transposeScope != off`; `_findTransposedNode` fails closed
  on unparseable FEN, illegal moves and out-of-scope targets.
- **Quota double-counting.** `_completedDecisionIds` is a `Set`, so a decision answered twice counts
  once against the quota. The bug in C1 is confined to `_completedCount`.
- **`_completedCount` being user-visible.** It is not — no production consumer exists. This is why C1
  is MEDIUM rather than HIGH. Checked before assigning severity, per the lesson recorded in review-1 §6.

**Not established, and it matters:** whether a repertoire node can have more than one user continuation
(C3). The node model permits it and two call sites handle it, but I did not trace the importer to see
whether it can produce one. That single fact decides whether C3 is a real defect or a missing
assertion.
