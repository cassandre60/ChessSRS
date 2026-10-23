# ChessSRS Scheduling Architecture: A Graph-Aware DSR Model

Authority: scheduling equations and graph mechanism. SPEC owns observable
invariants; ARCHITECTURE §5 owns identity/storage arrangement; MVP owns scope;
IMPLEMENTATION_PLAN owns delivery status. See `docs/documentation-map.md`.

The earlier recommendation report and illustrative Dart implementation are
preserved in git history. They mixed four-button/latency grading, single-move
identity and speculative features with accepted binary behavior. They are not
an implementation recipe. The descriptions below were checked against source;
this is not a new empirical calibration or runtime-validation claim.

## A. Scheduler choice and ratings

Scheduler is a replaceable per-question kernel wrapped by
GraphAwareReviewCoordinator. The coordinator accepts **any** Scheduler, not
only FSRS. All three algorithms remain selectable; there is no approved
deprecation or network/offline fallback policy:

- SimpleScheduler: first/base interval, then geometric growth; lapse resets
  streak/interval; maximum interval clamp.
- EaseScalingScheduler: first interval, ease multiplier on second success,
  then geometric scaling; lapse resets streak/interval; maximum clamp.
- ChessFsrsScheduler: binary Difficulty–Stability–Retrievability (DSR).

Defaults and exact parameter values live in `domain/scheduler.dart`,
`domain/chess_fsrs_scheduler.dart` and `model/study/study_preferences.dart`.
The default selection is Simple; FSRS's default target retention is 0.88.

Decision D015 excludes thinking time from grading: Good (3) for independent
correct recall, Again (1) for failed/assisted recall. ReviewSession settles
independence upstream; the kernel receives only ReviewResult. No Hard/Easy
buttons, latency inference, interval fuzz, or latency-based penalties exist in
the kernel. Stored latency fields are compatibility/diagnostic data, not inputs.

## B. Graph layer

### B.1 Lapse contagion

On a lapse, learned descendants in the branch topology receive a soft adjustment,
not a subtree reset (INV-027). Depth starts at 1 for an immediate descendant:

```text
decay(depth) = lambda0 * exp(-(depth - 1) / tau)
S' = S * (1 - decay)
D' = clip(D + beta * decay, 1, 10)
```

Remaining time to due is shortened by the same factor; already-due timestamps
stay due. Descendant review timestamps/repetition/lapse counts do not change.
Cold/non-positive-stability states are skipped. GraphAwareParams supplies
lambda0, tau, beta and the depth cap; invalid tau/decay is guarded in source.

### B.2 Auto-traversal exposure

For a stored positive-stability, non-due state (INV-028):

```text
S' = S * (1 + epsilon)
remaining time to due is extended by epsilon
```

Difficulty, lastReviewedAt, repetitions and lapses stay unchanged. Credit is
throttled per canonical memory per local calendar day, including across
restarts via lastExposedAt. A same-day active review also blocks credit.
Unknown states receive no materialized row. Due work cannot be satisfied by
passive traversal. Practice has no persisted credit (INV-023).

### B.3 Transpositions & identity

Use ARCHITECTURE §5 and INV-015/016/017/030. The key includes the trained side
and **complete accepted-answer set**, not one representative move. Different
reply sets are independent questions, not an import error. A GraphNode carrying
a complete canonical identity keeps it; only legacy occurrence IDs fall back
to the single-move adjacency map. Review-time transposition acceptance is a
separate grading contract (INV-065), not automatic memory-key merging.

### B.4 Confusable siblings

On actual confusion evidence, a played wrong move matching a supplied sibling's
expected move adds the configured difficulty coupling, clipped to [1,10]
(INV-029). The caller supplies played move and sibling context together. There
is no persisted ConfusionEdge registry, structural similarity search or
not-yet-due contrastive queue insertion in the implemented coordinator.

### B.5 Prerequisite priors (proposal only)

Ancestor-based cold-start difficulty priors have not been adopted. They require
separate scope/contract approval; their appearance in the earlier report was
not authorization to implement them.

## C. Binary ChessFSRS kernel

This is domain-adapted **FSRS-4.5-style** difficulty math, not a drop-in FSRS-5
optimizer target. The chess-specific weights are uncalibrated priors. No
chess dataset here demonstrates empirical superiority or guaranteed retention.

### C.1 Retrievability

With elapsed time t and stability S in days:

```text
C = -0.5; F = 0.9^(1/C) - 1 = 19/81
R(t,S) = (1 + F*t/S)^C
```

Thus R(S,S)=0.9. Negative elapsed time clamps to zero; non-positive stability
returns zero retrievability. Stored ReviewState stability is **milliseconds**;
the kernel converts to/from days at its boundary.

### C.2 Target interval

```text
I(S,r) = S/F * (r^(1/C) - 1)
```

Target r is clamped, then stability and interval use their configured bounds
(INV-026). The preview follows the same clamps in the same order.

### C.3 Difficulty

For g in {1,3}:

```text
D0(g) = clip(w4 - (g - 3)*w5, 1, 10)
D'(D,g) = clip(w7*w4 + (1-w7)*(D - w6*(g-3)), 1, 10)
```

### C.4 Cold start

S0(Again)=w0; S0(Good)=w2. Only binary weights exist; w1/w3/w15/w16 are
absent. Cold start bypasses the normal retrievability update.

### C.5 Successful recall

```text
S' = S * (1 + exp(w8)*(11-D)*S^(-w9)*(exp((1-R)*w10)-1))
```

The kernel uses updated D. Configured stability/interval ceilings still apply.

### C.6 Lapse

```text
S' = w11 * D^(-w12) * ((S+1)^w13 - 1) * exp((1-R)*w14)
```

This formula is not a promise of monotone stability reduction for arbitrarily
overdue low-stability items. FSRS retains repetitionCount and increments lapses;
the ladder schedulers reset repetitionCount. SPEC INV-025 currently generalizes
the ladder rule to all schedulers: Q9 in `docs/open-questions.md` is unresolved.
Do not change either the implementation or tests to hide this disagreement.

### C.7 Rapid re-review

Below the configured elapsed threshold, skip the full DSR update: difficulty
freezes and stability takes a small multiplicative success/lapse nudge. This
does not apply to cold start. The older pseudocode updated difficulty anyway;
that was fixed, not a current alternative implementation.

### C.8 Parameters and calibration

ChessFsrsParams and GraphAwareParams are the single source for current numeric
defaults. Altering persisted semantics/identity or accepted scheduling behavior
requires the SPEC/approval process. Personal or pooled weight fitting is future
research, not a drop-in capability already present.

### C.9 User controls versus proposals

Implemented controls live in StudyPrefs/SrsSettingsScreen. Tournament event
dates/auto-reversion, a separate rigor factor and confusion interleaving controls
from the recommendation report are **proposals only**, excluded from current
scope. Setting high target retention manually is not a shipped Tournament Mode.

## D. Implementation and proof pointers

- Kernel: `lib/src/domain/chess_fsrs_scheduler.dart`.
- Ladder kernels/contract: `lib/src/domain/scheduler.dart`.
- Graph layer: `lib/src/domain/graph_aware_review_coordinator.dart`.
- Session/application wiring: `lib/src/domain/review/review_session.dart`,
  `lib/src/review/review_service.dart`.
- SPEC INV-024–029 names the oracles; TEST_STRATEGY owns how to run them.
- Fresh versus due: INV-068; the null-date legacy edge awaits Q10. Do not use
  a cold-state helper in isolation to redefine the application's due figures.

No copied executable pseudocode is maintained here: use the actual source and
tests so documentation cannot offer a second, drifting implementation.
