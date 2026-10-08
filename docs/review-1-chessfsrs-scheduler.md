# Algorithm & Design Correctness Review — #1 of 4

**Target:** `ChessFsrsScheduler` and the FSRS math layer — `lib/src/domain/chess_fsrs_scheduler.dart`
(308 LOC), its state carrier `lib/src/domain/review_state.dart`, the two sibling schedulers in
`lib/src/domain/scheduler.dart`, and the SQLite round-trip in `lib/src/persistence/`.

**Reference spec:** `ChessSRS Scheduling Architecture.md` §C (C.1–C.9).

No code was modified in this pass.

---

## 0. Verification status (read this first)

The Dart/Flutter SDK is **not available in this sandbox** and cannot be installed: `storage.googleapis.com`,
`dl.google.com`, `api.dart.dev` and `pub.dev` all returned `000` (unreachable), and the GitHub release
asset for the SDK returned `404`. So **I could not execute `flutter test`.**

To avoid hand-waving the arithmetic, I wrote a throwaway line-by-line port of
`chess_fsrs_scheduler.dart` and validated it by re-deriving **all 26 assertions** in
`test/domain/chess_fsrs_scheduler_test.dart`. All 26 reproduce (e.g. `R(10,10)=0.9`,
`I(10,0.90)=10.0`, cold-start `S=190080000.0 ms`, interval `2.7323 d`). Every number below comes from
that validated port.

**That port is deliberately not committed.** A parallel Python reimplementation of the scheduler would
drift from the authoritative Dart one and become its own liability. To confirm any trace below, run the
real suite — `flutter test test/domain/chess_fsrs_scheduler_test.dart` — and add a case for the scenario
in question; the port only existed to make the review tractable without an SDK.

One caveat earned the hard way: my first port used Python `or` where Dart has `??`, which treats
epoch `0.0` as null and silently corrupted an early trace. It is fixed; the numbers below are post-fix.

All static claims (line numbers, call-graph, greps) come from tool calls, not memory.

---

## 1. Summary

**Correct but fragile, with one high-severity behavioural bug and one high-severity dead-code path.**

The core DSR mathematics are a faithful implementation of the spec. I verified the two properties that
are easiest to get wrong and both hold exactly:

- `R(S,S) = 0.9` by construction — `fsrsRetrievability(10,10)` returns exactly `0.9`, and
  `kFsrsFactor` computes to `0.23456790123456783` vs. `19/81 = 0.2345679012345679` (§C.1).
- `I(S, 0.90) = S` — `fsrsIntervalForTarget(10, 0.90)` returns exactly `10.0` (§C.2).

Difficulty uses the *new* `D'` in both stability formulas, which matches canonical FSRS (many
implementations get this backwards). The interval ladder is monotonic and the preview function matches
`schedule()` to 0.000000 d drift for its first 6 steps. `schedule()` is O(1) time and allocation-free
beyond the returned state.

The problems are not in the formulas. They are in **what the formulas are fed** and **which parts of
the spec are actually reachable**.

---

## 2. Confirmed issues

### C1 — The same-day guard protects stability but not difficulty. Three failures in one session pin `D` at 10 and cut stability growth ~6×. **(High)**

**Where:** `chess_fsrs_scheduler.dart:234` applies `fsrsNextDifficulty` *unconditionally*, before the
same-day branch at `:236`.

**Spec:** §C.7 — *"If elapsed t < t_same-day: **skip the full DSR update**. Instead apply a small
linear nudge: S' = S × {1.02 if g≥Good; 0.85 if g=Again}."* The difficulty update is part of the DSR
update the spec says to skip. The code skips only the stability half.

**Reachability (verified, three separate checks):**
- `review_session.dart:411-416` — on an incorrect move the decision is unconditionally re-queued. No attempt cap exists anywhere in the file.
- `review_session.dart:642` — `_advanceToNextDue` pops with `_dueQueue.removeAt(0)` and applies **no** `isDueAt` check, so the re-queued item is re-presented in the same session even though the lapse just pushed its `nextDueAt` ~10 days out.
- Therefore N lapses on one item in one session is user-reachable.

**Traced example** — mature item, `S=100 d`, `D=4.93`, fails then passes, 30 s apart, five times:

| # | result | D | S (days) | next interval (d) |
|---|---|---|---|---|
| 1 | incorrect | 7.009 | 7.8911 | 9.80 |
|   | correct   | 6.988 | 8.0490 | 10.00 |
| 2 | incorrect | 9.047 | 6.8416 | 8.50 |
|   | correct   | 9.005 | 6.9785 | 8.67 |
| 3 | incorrect | **10.000** | 5.9317 | 7.37 |
|   | correct   | 9.949 | 6.0503 | 7.51 |
| 5 | correct   | 9.949 | 4.5480 | 5.65 |

`D` saturates at the `clamp(1.0, 10.0)` ceiling after **three** failures. The cost is in
`fsrsNextStabilitySuccess`'s `(11 - d)` term (`:161`):

| D | (11−D) | growth vs. D=4.93 |
|---|---|---|
| 4.93 | 6.07 | 1.000× |
| 7.009 | 3.99 | 0.657× |
| 8.87 | 2.13 | 0.351× |
| 10.00 | 1.00 | **0.165×** |

Recovery is near-geological: mean reversion is `w7 = 0.01` per review toward 4.93, so it takes
**390 consecutive successful reviews** to get `D` back within 0.1 of 4.93. One bad practice session
on a Tuesday suppresses that move's interval growth sixfold for the rest of the user's life with the app.

**Expected:** §C.7 — difficulty frozen during rapid re-review, so an intra-session burst behaves as one
learning event.
**Actual:** difficulty ratchets on every rapid failure; stability does not.

---

### C2 — Decision D015's `hintUsed` / `multipleAttempts` rule is unreachable in production. **(High, spec fidelity)**

**Where:** `chess_fsrs_scheduler.dart:202-206`.

Three independent facts, each verified:

1. The `Scheduler` interface (`scheduler.dart:20-24`) declares `schedule({previous, result, now})` — **no** `hintUsed`/`multipleAttempts`. The extra parameters exist only on the concrete class, so they are invisible through the interface.
2. `grep -rn "scheduler.schedule(" lib/` returns **exactly one** hit: `graph_aware_review_coordinator.dart:191`, which holds the scheduler as the abstract `Scheduler` type (`:148`) and passes only three arguments. It *cannot* pass the flags.
3. `grep -rni hint lib/` finds no hint feature in `lib/src/domain/review/`, `lib/src/review/`, or `lib/src/view/review/` — only `hintText` on design-system text fields and this scheduler's own doc comment.

**The concrete deviation.** D015 defines `Again` as *"incorrect move, hint used, or corrected
false-start attempt."* Trace what a corrected false-start actually produces:

- User plays a wrong move → `submitMove` incorrect branch → lapse recorded (`Again`), decision re-queued.
- User then answers correctly when it comes back round → `submitMove` correct branch → **`Good`**, so `repetitionCount += 1` (`:267-269`) and `stability ×= 1.02`.

Net effect of one corrected false-start: **two** events (`Again` then `Good`), not one `Again`, and the
item's success counter goes *up*. (Note `retryMove` at `review_session.dart:437-478` takes the other
route — it writes no SRS state at all, so *that* path does end as a single `Again`. Two UI paths through
the same user action, with different scheduling outcomes.)

**Expected:** one `Again`; `repetitionCount` unchanged.
**Actual:** `Again` + `Good`; `repetitionCount` incremented; stability nudged back up 2%.

This is precisely what the unreachable `multipleAttempts` flag was built to express. Today it is
exercised only by `chess_fsrs_scheduler_test.dart:113-121`, which constructs the scheduler directly —
so the test passes while the production behaviour differs from what it asserts.

---

### C3 — `fsrsIntervalProgressionPreview` diverges from `schedule()` once the interval cap binds. **(Low–Medium)**

**Where:** `chess_fsrs_scheduler.dart:291-308`. The loop never applies
`clamp(minIntervalDays, maxIntervalDays)` (`:246`) or the stability clamp (`:247`).

| step | preview (d) | `schedule()` (d) |
|---|---|---|
| 0–5 | 2.7, 10.6, 35.9, 107.9, 293.5, 732.8 | identical (0.000000 drift) |
| 6 | 1697.4 | **1095.0** |
| 9 | 14724.7 | **1095.0** |

At step 9 the preview over-promises by **13.4×**.

Severity is currently Low because `grep -rn fsrsIntervalProgressionPreview lib/` finds no caller
outside its own declaration — it is only used by the test. It is a trap for whoever wires it to a
settings screen, which is the obvious next step given §C.9's "Target Retention slider".

---

### C4 — Switching `schedulerType` silently reinterprets `ReviewState.stability`. **(Medium)**

**Where:** `review_service.dart:26-28` selects among three schedulers from a user setting;
`study_preferences.dart:177` defaults to `SchedulerType.simple`;
`srs_settings_screen.dart:211-214` exposes FSRS/Simple/EaseScaling as a segmented control.

All three write different semantics into the same `ReviewState.stability` field with no unit tag and no
migration:

| scheduler | writes (`scheduler.dart:94,180`; `chess_fsrs_scheduler.dart:271`) | reads it back as |
|---|---|---|
| `SimpleScheduler` | current interval, ms | current interval, ms (`:82`) |
| `EaseScalingScheduler` | current interval, ms | current interval, ms (`:170`) |
| `ChessFsrsScheduler` | days-to-90%-retention, ms | stability, days (`:227`) |

**Traced example:** an item that `SimpleScheduler` had at a 30-day interval (`stability = 2592000000`,
`repetitionCount = 4`, due now). Flip the setting to FSRS and answer correctly:

- `isColdStart` = `false` (`:217`), so it is treated as mature memory.
- `difficulty = 0.0` → falls back to `D0(good) = 4.93` (`:229-231`).
- FSRS computes `S' = 79.47 d` → **next interval 98.69 days**, where Simple would have given 60.

A 30-day item silently disappears for three months because the user tapped a different algorithm name.
The reverse direction (FSRS→Simple) reads a 30-day stability as a 30-day interval and emits 60 d,
where FSRS-correct would be 37.3 d.

**Compounding factor:** `review_state.dart:12` documents the field as *"current interval in **days** for
`SimpleScheduler`"* — but all three schedulers write **milliseconds**. The doc is wrong, which is
exactly the kind of thing that lets a unit collision survive review. `position_knowledge_state.dart:74`
gets it right ("Memory stability in milliseconds"), so the two state classes document the same shared
field two different ways.

---

### C5 — A lapse can *increase* stability; the invariant is assumed but not enforced. **(Low)**

**Where:** `fsrsNextStabilityLapse`, `:167-171`. `w11 · D^-w12 · ((S+1)^w13 − 1) · e^((1−R)w14)` has no
monotonic clamp against `S`.

126 of 210 sampled `(S, D, R)` combinations raise stability. The in-app reachable path:

- Cold-start `Again` → `S = w0 = 0.35 d`, `D = 6.81`, due in 10.4 h.
- Come back **5 days** later and fail again → `S = 0.350 → 0.371 d` (**+5.9%**), `R = 0.479`.
- Come back **30 days** later → `S = 0.350 → 0.516 d` (**+47%**), `R = 0.218`.

Failing an item makes it *stickier* and pushes its due date out. This is shared with canonical FSRS
(which also does not clamp), so it is arguably inherited rather than introduced — but the function's own
doc says *"Calculates **regressed** stability after a lapse"* and
`chess_fsrs_scheduler_test.dart:95` asserts `lessThan(s1.stability)`. The invariant is documented and
tested in the common case only. Absolute values are small, hence Low.

---

### C6 — `isColdStart` never re-arms; a failed first attempt permanently demotes the item. **(Low)**

**Where:** `:217` — `previous.repetitionCount == 0 && previous.stability <= 0`.

After a failed cold start, `repetitionCount` stays `0` (`:268`) but `stability` becomes
`0.35 d > 0`, so the guard is false forever. Every later review takes the full DSR path treating
`S = 0.35 d` as *earned* memory.

**Traced:** next correct answer gives `S = 1.254 d`, versus `8.536 d` for a clean cold start — a
**6.8× gap that never closes**.

Mitigating: since `hintUsed` is unreachable (C2), only a genuine first-attempt `incorrect` triggers
this today, which is arguably intended. It becomes a live bug the moment C2 is fixed.

---

### C7 — `difficulty` has three disagreeing sources of truth. **(Low)**

| source | value |
|---|---|
| `review_state.dart:26` (`ReviewState` default) | `0.0` |
| `srs_schema.dart:101` (`srs_review_state` column `DEFAULT`) | `5.0` |
| `sqlite_study_repository.dart:710` and `:975` (NULL fallback) | `5.0` |
| `chess_fsrs_scheduler.dart:229-231` (fallback when `<= 0`) | `4.93` (`D0(good)`) |

A cold item built in memory gets `D = 4.93`; one read from a default-constructed row gets `D = 5.0`.
Impact is small but real and permanent: `(11−D)` is `6.070` vs `6.000`, a **−1.15%** growth-rate
difference that compounds over the item's whole life. Note `position_knowledge_state`'s column
(`srs_schema.dart:82`) defaults to `0.0` while the review-state column defaults to `5.0` — the two
tables holding the same logical field disagree with each other too.

---

## 3. Design concerns

**D1 — `(11 − d)` is unguarded in a public function.** `fsrsNextStabilitySuccess` (`:159`) is a public
top-level function with no clamp on `d`. At `d > 11` the factor goes negative and the function returns
*negative stability*. `schedule()` is saved only by the `clamp(minStabilityDays, maxStabilityDays)` at
`:247`; any future caller of the raw function must re-clamp. The other public helpers
(`fsrsRetrievability`, `fsrsInitialDifficulty`, `fsrsNextDifficulty`) do guard their inputs.

**D2 — `steps` is unvalidated.** `fsrsIntervalProgressionPreview` (`:293`) accepts any `int`; `steps = 0`
and `-1` both return `[]` silently, and the loop is O(steps) with no upper bound. Fine for a test, a
hang if it is ever bound to a text field.

**D3 — ~~O(k) sequential awaited inserts per review answer.~~ RETRACTED — see correction below.**
`sqlite_study_repository.dart:513-538`: `savePositionKnowledgeState` issues one **awaited, unbatched**
`saveReviewState` per decision matching the canonical id, plus one more per row in a loop. For a
position that transposes across many chapters this is k sequential round-trips on the review hot path.
A batched variant exists 60 lines below (`:596-618`), so the single-item path is the outlier, not the
house style.

> **Correction (added 2026-10-08, after grepping for callers).** The premise — "on the review hot
> path" — is false, and with it the severity. `savePositionKnowledgeState` has **zero production
> callers**; the only references outside its own definition are the interface declaration at
> `study_repository.dart:77` and five call sites in tests. `savePositionKnowledgeStates` (the batched
> variant) has **no callers at all**, production or test.
>
> The path that actually runs on a review answer is `saveAnswerBatch`, called from
> `review_service.dart:317` and `:355`. It already uses `_db.batch()` and mirrors to
> `kTableSrsReviewState` with a single `INSERT … SELECT … WHERE canonicalStateId = ?` rather than a
> per-decision loop — i.e. it already does what this entry recommended.
>
> What remains is not a performance issue but a **dead-code** one: two public repository methods and
> their five test call sites exist solely to be tested. The unbatched loop in the singular method is
> still a latent trap for whoever first wires it up in production, since it would reintroduce the O(k)
> round-trips on the very path `saveAnswerBatch` was written to avoid. Either wire the singular method
> through the batch, or delete both and let `saveAnswerBatch` be the only writer. **Improvement 7 below
> is void as originally written.**


**D4 — Timestamps are persisted as offset-less local time.**
`sqlite_study_repository.dart:517-519` write `toIso8601String()` on local `DateTime`s (no `Z`, no
offset), and `:704-706` read them back with `DateTime.parse`, which yields local. Round-trips are
consistent *within* a timezone; a device timezone change reinterprets every stored `nextDueAt` as
wall-clock in the new zone, shifting all due dates by the offset delta. For an SRS app whose entire
output is a due date, this deserves a deliberate decision.

**D5 — `repetitionCount` means different things per scheduler, but `isLearned` reads it uniformly.**
FSRS never resets it on lapse (`:267-269`); `SimpleScheduler` and `EaseScalingScheduler` both reset to
`0` (`scheduler.dart:102,186`). Meanwhile `ReviewState.isLearned` (`:60`) is just `repetitionCount > 0`
for all of them, and combined with C6 an item can be **neither** `isNew` (`:59`) **nor** `isLearned`
after a failed first attempt. The field doc concedes "semantics depend on scheduler" — which is an
acknowledgement that the derived predicates built on it cannot be trusted.

**D6 — "FSRS-5" in the name, FSRS-4.5 in the math.** The class doc (`:172-176`) says
*"Domain-adapted FSRS-5"*. §C.3 and the code implement
`clip(w7·w4 + (1−w7)(D − w6(g−3)), 1, 10)` — the FSRS-4.5 difficulty form, without the linear damping
FSRS-5 added. Separately, §C.8's parameter table still lists `w15` (Hard penalty) and `w16` (Easy bonus)
that the binary `ChessFsrsParams` does not carry at all. The spec table predates Decision D015 and was
never reconciled. Cosmetic, but it will mislead anyone trying to port FSRS's published optimizer onto
this — which §C.8 explicitly proposes doing.

**D7 — `maxStabilityDays` and `maxIntervalDays` are unlinked.** `1825 d` vs `1095 d` (`:43`, `:180`).
Once the interval cap binds, `I(1825, 0.88) = 2266.6 d` is clamped to `1095 d`, so the item is actually
reviewed at `R = 0.93628` rather than the 0.88 target. That inflated `R` is then fed back into
`fsrsNextStabilitySuccess`, systematically under-rewarding the most mature items. Self-consistent, but
the target-retention contract quietly stops holding for exactly the items the user has mastered best.
(Symmetrically, `minIntervalDays = 1/1440` can never bind: `minStabilityDays = 0.02 d` already implies a
minimum interval of 35.77 min.)

---

## 4. Suggested improvements (priority order)

Each is scoped to be reviewable on its own.

1. **Gate difficulty on the same-day guard (C1).** Move `:234` inside the `else` of the same-day branch
   at `:236`, so `newDifficulty = prevDifficulty` when `elapsedDays < sameDayThresholdDays`. ~5 lines,
   brings the code in line with §C.7 as written. Add a regression test: 3 intra-session failures must
   leave `D` at its pre-session value. *Highest value-to-risk ratio in this file.*
2. **Resolve the D015 gap (C2).** Either (a) widen the `Scheduler.schedule` contract to carry
   `hintUsed`/`multipleAttempts` and pass them from `graph_aware_review_coordinator.dart:191`, or
   (b) delete the dead parameters and record a corrected false-start as a single `Again` — which means
   making the `submitMove` correct branch aware that this decision already lapsed this session. Option
   (b) also fixes the two-paths-one-action inconsistency between `submitMove` and `retryMove`.
3. **Tag the state with its producing scheduler (C4).** Add a `schedulerKind` (or `stabilityUnit`)
   field to `ReviewState`, persist it, and on mismatch either migrate or reset to cold-start. Cheapest
   immediate win: fix the `review_state.dart:12` doc comment, which currently states the wrong unit.
4. **Make the preview honest (C3).** Route it through the same clamps as `schedule()`, or delete it
   until something calls it. It has no caller today, so deletion is free.
5. **Decide the lapse-monotonicity question (C5).** Either add `math.min(newS, S)` to
   `:170`, or document that non-monotonicity is intentional FSRS inheritance and add a test pinning the
   `S=0.35, 5 d overdue` case so a future weight retune cannot silently make it worse.
6. **Collapse the difficulty defaults to one named constant (C7).** Export
   `kDefaultDifficulty = 4.93` (or `0.0` + universal fallback) and use it in the schema, both row
   mappers, and `:229`.
7. ~~**Batch the per-decision writes (D3).**~~ **Void — see the D3 retraction.** The production write
   path (`saveAnswerBatch`, `review_service.dart:317`/`:355`) is already batched. The real finding is
   that `savePositionKnowledgeState` / `savePositionKnowledgeStates` are **dead code** reachable only
   from tests, and the singular one still contains the unbatched loop. Decide between routing it
   through the batch and deleting both.
8. **Store timestamps as UTC or epoch-ms (D4).** Mechanical, but it is a schema change, so it wants its
   own migration and should not be bundled with anything above.

Items 1, 4, 6 are localised and low-risk. Items 2, 3, 8 touch persisted data or the public
`Scheduler` contract and want a design note first.

---

## 5. Not reviewed here

Deferred to the remaining three passes, though several surfaced incidentally above and are flagged so
they are not lost:

- **Auto-traversal exposure credit compounds without any recall test.**
  `graph_aware_review_coordinator.dart:235` multiplies stability by `1.08` once per calendar day, with
  only a same-day throttle and a "not already due" guard (`:224`). An item merely *passed over* while
  drilling other lines can reach `1.08^30 = 10.06×` stability in a month, never having been actively
  recalled. Needs a proper look in pass #2.
- **Repeated failures re-fire graph side-effects.** Each `incorrect` re-triggers lapse contagion and
  sibling coupling (`:196-203`), so C1's three-failure session also applies contagion three times.
  Pass #2.
- **`review_session.dart` state machine** (970 LOC) — the `submitMove`/`retryMove` divergence in C2 is a
  symptom of something larger there. Pass #3.
- **`review_service.dart` / `review_controller.dart`** (688 + 1508 LOC) — idempotency, double-scheduling,
  and clock injection under concurrency. Pass #4.

---

## 6. Resolution log

Every item above has now been dispositioned. This is the audit trail for why each one was fixed,
documented, or dropped, so a later reader does not have to re-derive the reasoning.

| # | Finding | Disposition | Why |
|---|---|---|---|
| C1 | Difficulty mutated during rapid re-review | **Fixed** `18dde77` | Contradicted §C.7 and changed scheduling output. Two regression tests, one with fail-to-pass evidence against base. |
| C2 | Corrected false-start graded twice | **Fixed** `604d5a1` | Same human action had two outcomes depending on which button ended the turn. Fixed at the session layer; one test removed with an `Ack-G08:` trailer. |
| C3 | Interval preview ignored the scheduler's clamps | **Fixed** `5ccb7ba` | Advertised 1697 d where the scheduler emits 1095 d. Preview now clamps in the same order; tolerance measured, not guessed. |
| C4 | Cross-scheduler `stability` reinterpretation | **Deferred, documented** | See note below. Every available remedy mutates user memory. |
| C5 | Lapse formula not monotone in S | **Documented + pinned** `cbf3194` | Matches canonical FSRS and §C.6; adding `min(result, s)` would be a spec change. Numbers pinned so a weight retune cannot silently widen the window. |
| C6 | `isColdStart` never re-arms | **Open** | Genuine 6.8× gap but needs a product answer on what "forgotten" means. Low blast radius in practice. |
| C7 | Three disagreeing difficulty defaults | **Dropped** | Both columns are `NOT NULL` and the repository always writes explicitly, so the `?? 5.0` fallbacks are unreachable. Dead magic numbers, not a live bug. |
| D1 | `steps` unvalidated | **Fixed** `5ccb7ba` | Folded into the C3 fix. |
| D2 | `stability` doc said "days" | **Fixed** `5ccb7ba` | The comment is what let C4 survive review. Now states milliseconds and names each scheduler's meaning. |
| D3 | Sequential per-decision writes | **Retracted** | Premise false — no production callers; the real path is already batched. Real finding is dead code. See the D3 correction. |
| D4 | Offset-less local timestamps | **Open** | Real portability bug, but it is a schema migration with data risk and deserves its own PR. |
| D5–D7 | Semantics / naming / cap-linking | **Open** | Recorded; none is a live defect today. |

### Why C4 was deferred rather than fixed

The collision is real and demonstrable: a 30-day interval written by `SimpleScheduler` and later read
by `ChessFsrsScheduler` yields 98.69 d instead of the expected 60 d, because the two schedulers store
different quantities in the same column. A fix requires a schema migration to record which scheduler
produced a row — that part is mechanical (`database.dart` is at `version: 15` with an `onUpgrade`
handler) — and then a policy decision about what happens to memory already on disk when someone
changes the algorithm setting:

1. **Reset to cold start.** Honest and simple, but destroys every accumulated interval the moment a
   user taps a different algorithm name.
2. **Convert.** A principled mapping exists (`I(S, 0.88) = S × 1.242`, so `S = interval / 1.242`), but
   it is approximate: `SimpleScheduler`'s ladder was not produced by the FSRS curve, so the conversion
   invents a stability the user never earned.
3. **Warn and require confirmation.** Least destructive; leaves the data intact but makes the
   reinterpretation the user's informed choice.

All three mutate or expose user memory differently, and the choice is a product decision rather than
an engineering one. Option 1 is the only one that can be ruled out on technical grounds, since it
punishes curiosity with irreversible data loss. **Recommendation: option 3 now, option 2 later if
switching turns out to be common.** Until then the gap is documented in `review_state.dart` at the
field that causes it, which is where a future reader will look.

### Note on process

Two of the corrections above (D3 retracted, C7 dropped) were found by checking the *callers* of the
code the review described, not the code itself. Both original findings read the implementation
correctly and still reached a wrong conclusion about impact, because neither asked whether the path
was reachable in production. Passes #2–#4 should check reachability before assigning severity.
