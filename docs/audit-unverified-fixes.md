# Audit fixes shipped without a test that fails without them

Four of the fixes in this series are shipped on reasoning rather than on a
regression test. This records what each one does, what evidence exists, and what
would close the gap. It exists so the caveat is not something a future reader has
to rediscover from a commit message. Two more have since been closed — M4, at the
end, and M10, whose entry below is marked closed.

Of those still open, none is a suspected defect. They are unproven.

## M3 — engine subscription is cancelled on supersession

**The fix.** `position_evaluator.dart:583` cancels `_searchInfoSubscription`
when a search is superseded. A superseded search kept reporting until its own
bestmove, and nothing was listening for it.

**Evidence.** The generation tag and the `_isCurrentSearch` guard around it are
covered by a test that fails without them. The subscription cancel is not.

**What would close it, and why it probably should not be closed.** Investigated:
`Search` objects are created and owned inside the evaluator (`_currentSearch` is
private, and the test fake operates at the UCI transport layer below the point
where `search.infos` exists). The only observable consequence of the cancel is
that a stream nobody can reach stops having a listener, and every callback is
already gated on `_isCurrentSearch`, so there is no behavioural difference left
to observe.

Testing it would mean exposing `_currentSearch` or injecting a search factory —
a production change made purely for testability, in order to assert a two-line
hygiene call. That is a bad trade. Recommendation: leave it, and stop describing
it as untested work waiting to be done.

**Risk if wrong.** Low, and bounded by construction: with `_isCurrentSearch`
gating every callback, a redundant live subscription cannot produce a wrong
evaluation. Worst case it wastes work.

## M6 — threefold repetition compares full position identity

**The fix.** Repetition compares the 4-field FEN rather than piece placement, so
the same pieces with the other side to move, different castling rights or a
different en-passant square are not the same position.

**Evidence.** None. Two attempts failed and both were removed. The first used a
knight shuffle, which was vacuous: moving a knight and a bishop out and back
preserves castling rights, so the position genuinely *was* identical and neither
the old nor the new code triggered.

**What would close it.** A king shuffle, because moving the king and back
destroys castling rights permanently while leaving the board identical. That
produces three board-identical positions of which only one is the same position.
It needs the sequence played twice to reach three occurrences, and both sides
must return to their starting squares — which means scripting the engine, and
the existing fakes control the NNUE weights rather than the search.

**Risk if wrong.** Very low. QUALITY.md §2.3 requires identity to account for
side to move, castling and en-passant, so this is compliance with a written
invariant rather than a judgement call. It is in the offline move path, which is
why it is worth a test eventually.

## M10 — retry persists its side effects — **now closed**

**The fix.** `review_service.dart:282` persists `result.sideEffectStates` and
rolls the session back if the write fails, mirroring `submitMove`.

**Evidence.** A service-level test now covers it, and fails without the fix.
`review_service_test.dart`, *"retry side effects: a correct retry that walks a
learned continuation persists the auto-traversal exposure credit"*.

**The recipe, which is what the four earlier attempts were missing.** A line of
**three** decisions, not two and not four:

1. the prompted decision (due),
2. a decision that is **learned but not due** (so auto-traversal plays through it
   and grants it exposure credit — the state that gets persisted),
3. a decision that is **due** (so the traversal stops there).

The retry is preceded by a lapse on decision 1, so `retryMove` is the natural
next call. Then `retryMove` walks `e5 → Nf3 (auto-played) → Nc6` and stops at 3,
and `canon_r2` in `position_knowledge_state` comes back with a boosted stability
and a later due date.

**The measurement trap, worth recording because it is what made the first
version of this test fail.** Decision 2 is a *descendant* of decision 1, so the
lapse on decision 1 propagates contagion into it first. Its stability after the
lapse is roughly 0.908 of the seeded value, and the exposure credit then
multiplies that by 1.08 — a net **0.98**, i.e. *below* where the seed was.
Asserting "greater than the seeded stability" therefore fails on correct code.
The test measures the retry against the state the lapse left behind.

Verified by disabling the persistence and watching the assertion fail with
`Actual: 392076684.8240257` against `Expected: greater than
392076684.8240257` — identical values, i.e. no write happened — and pass again
with it restored.

**Risk if wrong.** Now demonstrably none for this path: the fix does real work,
and the test proves it.

## M15 — large imports hash off the UI isolate

**The fix.** `importPgnText` uses the existing `computePgnHashAsync` helper
instead of hashing synchronously before the large-import branch.

**Evidence.** Not obtainable in this harness. The helper short-circuits to the
synchronous path under `FLUTTER_TEST`, so the worker path cannot be reached from
a test suite. The test that exists pins that the helper agrees with the
synchronous one, which is what would break duplicate detection — it does not
show that work left the UI isolate.

**What would close it.** A test that observes the isolate boundary, which means
either removing the `FLUTTER_TEST` short-circuit for this path or asserting on
the helper's internals. Neither is worth it for a two-line change that reuses a
helper whose contract is already pinned elsewhere.

**Risk if wrong.** Very low. The helper is the one the codebase already provides
for exactly this, and it is covered where the behaviour is observable.

## Summary

| Item | Unproven part | Risk if wrong | Closable in this harness |
|---|---|---|---|
| M3 | subscription cancel | low — hygiene only | no — would need a production change for testability |
| M6 | repetition identity | very low — spec-mandated | awkward, needs a scripted engine |
| M10 | ~~retry side effects~~ | **closed** | **closed** |
| M15 | isolate offloading | very low | no — unreachable under test |

Two of the four (M6, M15) are better argued from the spec and from the helper's
existing contract than from a test, and I would not spend more on them. M3 is not
worth closing: its only observable effect is on a stream no test can reach, and
asserting it would need a production change made purely for testability.
M10 is closed — the test exists and fails without the fix; its own entry records
the recipe and the measurement trap.

## Closed since this file was written

### M4 — cloud evaluation subscribes before it sends

Now covered by a test. `ImmediateResponseWebSocketChannel` answers a request
inside the `add` call that carried it, which no previous fake could do: they all
reply on a `Timer`, a whole event-loop turn later, and against an asynchronous
reply there is always time to subscribe first. The test asserts both orders and
gets 1 reply for subscribe-then-send against 0 for send-then-subscribe.

The mechanism is `SocketClient._handleEvent` checking `_streamController.hasListener`
and dropping the event outright when nobody is listening. That check runs
synchronously, so the last hop being asynchronous does not save the old ordering.
This was worth measuring rather than reasoning about: the prediction that it
could not happen was wrong.

**One caveat, stated rather than buried.** The drop needs a transport that
delivers synchronously, which the fake arranges deliberately. Whether
`web_socket_channel` does this against a real socket is *not* established, so the
production severity of the original ordering is still unproven. What is now proven
is that the ordering is load-bearing under a synchronous transport, so the
subscribe-first form has to stay.
