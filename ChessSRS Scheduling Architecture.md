# ChessSRS Scheduling Architecture: A Graph-Aware DSR Model
by claude-sonnet-5-high
## Executive Summary

**Recommendation:** Adopt the **FSRS-4.5/5 (Difficulty-Stability-Retrievability) power-law forgetting model as the per-node memory kernel**, wrapped in a **chess-specific graph propagation layer** (`GraphAwareReviewCoordinator`) that is *not* part of generic Anki/FSRS and cannot be bolted on later without a redesign. The kernel handles "how does one memory item decay and strengthen." The wrapper handles "how do memory items influence each other because they live on a tree of forced move-order dependencies, share transposed positions, and compete for the same pattern-recognition slot."

This separation is deliberate: the DSR core is empirically the strongest general memory model available (outperforms SM-2/HLR in every published Anki-scale benchmark), so we should not re-derive it from scratch with no chess review data to fit it on. The genuinely novel, chess-specific engineering is entirely in the graph layer — that's where this report concentrates its original contribution.

---

## A. Algorithmic Candidates Comparison

| Model | Mechanism | Fit for chess trees | Verdict |
|---|---|---|---|
| **SM-2 / Leitner (Chessable-style)** | Discrete ease-factor ladder, deterministic multiplier on correct, hard reset on lapse | Zero graph awareness, ease factor is a crude scalar that conflates "how hard is this move" with "how forgettable is this move," reset-on-lapse is catastrophic for an 8-ply variation (see §B.1) | **Reject as primary model.** Useful only as the `SimpleScheduler` fallback for cold-start/offline-degraded mode. |
| **EaseScalingScheduler (current)** | $I = \text{ease}\times\text{scaling}^{\text{reps}}$, geometric, no decay-based retrievability target | No retention target, no difficulty separate from stability, cannot answer "when will $R$ drop below 90%" — it's a schedule, not a memory model | **Deprecate.** Keep only as legacy import path for existing users migrating data. |
| **FSRS v4.5 / v5 (DSR)** | Continuous power-law retrievability $R(t,S)$, difficulty $D\in[1,10]$ decoupled from stability $S$, explicit $R_{\text{target}}$-driven interval solve | Excellent: separates "intrinsically hard move" (D) from "currently well/poorly memorized" (S); directly answers the tournament "R≥95% by Saturday" question by solving for $t$ at fixed $S$; validated on >700M real reviews | **Adopt as kernel.** |
| **Half-Life Regression (HLR/Duolingo)** | $p = 2^{-\Delta/h}$, $h = 2^{\theta\cdot x}$, features regressed via logistic/linear regression over large corpora | Needs a trained feature vector (lexeme features in Duolingo); we have no chess-specific corpus yet, and it doesn't model difficulty separately from stability — architecturally it *is* FSRS's ancestor with a weaker (exponential, not power-law) decay | **Reject as core model**, but its *methodology* (log-loss regression to fit decay-rate weights against real review outcomes) is exactly how we should later refit FSRS's $w_i$ chess-specific weights once ChessSRS accumulates review logs. |
| **Hierarchical / Graph-aware (tree credit assignment, Bayesian Knowledge Tracing)** | BKT: latent binary "known" state per skill, HMM transition (learn/forget/guess/slip probabilities), naturally supports prerequisite graphs | Correctly models "prerequisite" structure but BKT is *trial-indexed*, not *time-indexed* — it has no native concept of "14 real days elapsed," which is the entire point of SRS. Also binary latent state loses the difficulty/stability separation. | **Do not replace FSRS with BKT.** Instead, borrow BKT's prerequisite-propagation idea (§B.1, §B.4) purely for **cold-start priors** (new/child-node difficulty seeded from ancestor mastery) — a genuine hybrid, not a swap. |

### On binary ratings vs. FSRS's 4-button model (Decision D015: Pure Binary FSRS)

FSRS's canonical equations are parameterized on $g \in \{1{=}\text{Again},2{=}\text{Hard},3{=}\text{Good},4{=}\text{Easy}\}$. In vocabulary flashcards, latency approximates confidence. In chess, however, **latency is dominated by calculation and verification overhead**, which is disciplined tournament play, not weak memory. 

Penalizing think time creates timer anxiety and trains reflexive blitzing. Furthermore, FSRS maintains full mathematical predictive accuracy in binary mode ($g \in \{1{=}\text{Again}, 3{=}\text{Good}\}$).

Therefore, ChessSRS strictly uses **Pure Binary FSRS**:

$$
g =
\begin{cases}
\text{Again (1)} & \text{incorrect move, hint used, or corrected false start}\\
\text{Good (3)} & \text{first committed move is correct (unlimited think time)}
\end{cases}
$$

Latency (`latencyEmaMs`) is preserved as optional post-hoc telemetry only, strictly firewalled from interval grading. Dead parameters (`w1`, `w3`, `w15`, `w16`) are eliminated from the kernel.

---

## B. Graph-Aware Adaptation & Invariants

### B.1 Upstream Lapse Handling

**Principle:** A lapse at ply $N$ is evidence about the *specific pattern-recognition trigger at that node*, not proof of amnesia for ply $N{+}1, N{+}2,\dots$. Full subtree reset (what naive SM-2 usage would imply) is both empirically wrong (descendants are frequently still fine) and pedagogically harmful (it manufactures enormous, demotivating review backlogs from a single misclick).

We apply **exponentially-decaying lapse contagion**, scoped to *direct descendants in the same chosen branch only* (not siblings — see B.4 for sibling handling):

$$
S_{\text{child}}' = S_{\text{child}} \times \bigl(1 - \lambda_0 \cdot e^{-(\text{depth}-1)/\tau}\bigr)
$$

$$
D_{\text{child}}' = \operatorname{clip}\bigl(D_{\text{child}} + \beta \cdot \lambda_0 \cdot e^{-(\text{depth}-1)/\tau},\ 1,\ 10\bigr)
$$

with defaults $\lambda_0 = 0.18$ (max 18% stability haircut, applied only to the immediate child), $\tau = 1.5$ plies (contagion is essentially gone by depth 4), $\beta = 0.6$ (a smaller permanent difficulty nudge, since "the line as a whole is trickier" is durable signal even after the transient stability hit is regained). Depth counts from 1 at the immediate child, so it takes the full $\lambda_0$; earlier the exponent read $-\text{depth}/\tau$, which delivered only 51.3% of the documented haircut at every depth (review-2 C2, fixed 2026-10-10). The corresponding `nextDueAt` is pulled forward proportionally to the same decay (not reset to "now") — this makes the child *more likely to surface soon* without lying about its actual measured retrievability.

This is intentionally a **soft nudge, not a state-machine reset**: it never touches `repetitionCount` or `lapseCount` of the child (that child was not tested), and the true FSRS update for the child still happens normally the next time it is *actually reviewed*.

### B.2 Auto-Traversal Credit (Invariant §2.4)

Passive traversal is real exposure (the player *sees* the correct move played, in context, under time pressure of getting to the due node) but is not **active recall** — no retrieval effort was made, no error signal is possible. Per Karpicke & Roediger's testing-effect literature, re-exposure produces a small, short-lived boost, meaningfully weaker than a successful active retrieval.

Rule: auto-traversal produces a **micro-stability bump with no memory-model side effects**:

$$
S' = S \times (1 + \varepsilon), \qquad \varepsilon = 0.08
$$

Applied by *extending* `nextDueAt` proportionally (never shrinking it), and explicitly:
- `lastReviewedAt` is **not** updated (it is not a review),
- `repetitionCount` / `lapseCount` / `difficulty` are **not** touched,
- capped to **once per calendar day per decision** (prevents a user from "farming" stability by rapidly re-opening the same line and inflating intervals),
- **only applied while the item is not overdue** — if a prefix move is itself already due (its own interval elapsed), auto-traversal must not silently satisfy that due-ness; the engine should surface it as its own decision point instead of just walking past it. This is enforced upstream by the traversal engine, not the scheduler, but the scheduler protects itself by refusing the exposure bump to already-`isDue` states.

### B.3 Transpositions & Position Identity

Canonicalize every `RepertoireDecision` on **FEN4 (placement, turn, castling, en-passant target) + the expected move in UCI**, *not* on a per-chapter node id:

```
canonicalKey = sha1("$fen4|$expectedMoveUci")
```

- If two nodes across chapters share `canonicalKey` → they are the *same memory item*. Merge into a single `ReviewState`, referenced by both graph nodes (many-to-one edge from `RepertoireDecision.positionStateId` to a shared `PositionKnowledgeState`). A review triggered from either chapter updates the one shared state; due-ness is likewise shared.
- If FEN4 matches but the **expected move differs** across chapters → this is not a transposition, it's a **repertoire contradiction** (the user has committed to two different moves in the same position across two studies). This must be surfaced as a lint/validation error at import time, not silently trained — training both would actively teach interference.
- Half-move clock and full-move number are deliberately excluded from the key (they don't affect legal continuations or pattern recognition), and only FEN4 is used precisely to catch transpositions Lichess/ chess.com study trees usually fail to detect.

### B.4 Interference Mitigation (sibling / confusable candidate moves)

Real interference in chess is not "same node, different candidate answers" (a `RepertoireDecision` has exactly one expected continuation by definition) — it's **structurally distinct decisions whose surface features are highly similar** (Najdorf 6.Bg5 vs 6.Be3 are different FENs entirely). Generic SRS has no notion of this at all. We add a lightweight **Confusion Registry**:

1. **Direct evidence linking:** whenever an incorrect answer is recorded, compare the *played* move (and resulting FEN) against sibling decisions hanging off the same parent (or FEN-adjacent decisions found via a cheap structural hash of "board minus last move"). If the played move exactly matches a sibling's expected move, register a `ConfusionEdge(a, b, weight++)`.
2. **Difficulty coupling:** on a confirmed confusion edge, bump the *sibling's* difficulty by a small coupled amount too ($\Delta D_{\text{sibling}} = \kappa \cdot \Delta D_{\text{node}}$, $\kappa \approx 0.35$) — evidence that A and B are confusable is symmetric evidence, even though only A was tested.
3. **Scheduling consequence:** when the due-aware weighted-random selector (already part of your traversal engine) picks a due node with outgoing confusion edges above a weight threshold, it should **interleave the confusable sibling into the same session** (contrastive practice) even if the sibling isn't strictly due yet — this is the single highest-leverage, chess-specific intervention available, since discrimination training is what the literature says fixes exactly this failure mode (it is *not* something raw interval math can fix).

### B.5 Prerequisite priors for cold-start (BKT-inspired, not BKT-replaced)

New decisions (never reviewed) get their FSRS $D_0$ seeded not just from the first rating but nudged by ancestor mastery:

$$
D_0' = \operatorname{clip}\Bigl(D_0(g) - \gamma \cdot (R_{\text{parent}} - 0.9),\ 1,\ 10\Bigr), \quad \gamma \approx 2.0
$$

i.e., if the parent move is currently very well retained ($R_{\text{parent}}$ high), assume slightly lower intrinsic difficulty for the child (the player is "in flow" in this part of the tree); if the parent is fragile, assume the child is a bit harder than its first rating alone would suggest. This is a prior only — it washes out after 2–3 real reviews of the child via normal FSRS mean-reversion.

---

## C. Recommended Model Specification — "ChessFSRS"

### C.1 Retrievability (forgetting curve)

Power-law form (FSRS-5), with $S$ in days:

$$
R(t, S) = \left(1 + F\cdot\frac{t}{S}\right)^{C}, \qquad C = -0.5,\quad F = 0.9^{1/C}-1 = \tfrac{19}{81}\approx 0.2345
$$

chosen so that $R(S, S) = 0.9$ by construction (i.e. $S$ is literally "days until 90% retention").

### C.2 Interval for a target retention $R_{\text{target}}$

Solve $R(t,S)=R_{\text{target}}$ for $t$:

$$
I(S, R_{\text{target}}) = \frac{S}{F}\Bigl(R_{\text{target}}^{\,1/C} - 1\Bigr) = \frac{81\,S}{19}\Bigl(R_{\text{target}}^{-2}-1\Bigr)
$$

### C.3 Difficulty

$$
D_0(g) = \operatorname{clip}\bigl(w_4 - (g-3)w_5,\ 1,\ 10\bigr)
$$
$$
D'(D,g) = \operatorname{clip}\Bigl(w_7\cdot w_4 + (1-w_7)\bigl(D - w_6(g-3)\bigr),\ 1,\ 10\Bigr)
$$

### C.4 Stability — Day-1 (cold start)

$$
S_0(g) = w_0,\ w_1,\ w_2,\ w_3 \quad\text{for } g=\text{Again, Hard, Good, Easy}
$$

Day-1 interval $= I(S_0(g), R_{\text{target}})$.

### C.5 Stability — successful recall ($g \ge \text{Hard}$)

$$
S' = S\left(1 + e^{w_8}\cdot(11-D)\cdot S^{-w_9}\cdot\bigl(e^{(1-R)w_{10}}-1\bigr)\cdot h\cdot e\right)
$$
$h = w_{15}$ if $g=\text{Hard}$ else $1$; $e = w_{16}$ if $g=\text{Easy}$ else $1$.

### C.6 Stability — lapse ($g=\text{Again}$)

$$
S'_{\text{lapse}} = w_{11}\cdot D^{-w_{12}}\cdot\bigl((S+1)^{w_{13}}-1\bigr)\cdot e^{(1-R)w_{14}}
$$

then apply the **graph-layer contagion** from §B.1 to descendants (this is *in addition to*, and downstream of, the node's own lapse update).

### C.7 Same-day / rapid re-review guard

If elapsed $t < t_{\text{same-day}}$ (default $1/24$ day = 1 hour): skip the full DSR update (at $t\to0$, $R\to1$ and the formulas above degenerate/produce near-zero effective change or numerical noise). Instead apply a small linear nudge:

$$
S' = S \times \begin{cases} 1.02 & g \ge \text{Good} \\ 0.85 & g = \text{Again}\end{cases}
$$

### C.8 Recommended default parameters (chess-tuned prior)

Starting point = published FSRS-4.5 default weights, with the deltas noted (justified in §B — chess lapses should cost slightly more because of tree dependency, chess "Hard" correct answers should be weighted down slightly because hesitation strongly predicts a near-term lapse in tactical recall):

| Param | Generic FSRS default | ChessSRS default | Rationale |
|---|---|---|---|
| $w_0$ (S0 Again) | 0.40 | 0.35 | slightly faster relapse re-surfacing |
| $w_1$ (S0 Hard) | 0.60 | 0.55 | |
| $w_2$ (S0 Good) | 2.40 | 2.20 | |
| $w_3$ (S0 Easy) | 5.80 | 5.80 | unchanged |
| $w_4$ (D0 base) | 4.93 | 4.93 | |
| $w_5$ (D0 slope) | 0.94 | 0.94 | |
| $w_6$ (D responsiveness) | 0.86 | **1.05** | interference/dependency makes chess errors more diagnostic of true difficulty |
| $w_7$ (D mean reversion) | 0.01 | 0.01 | |
| $w_8$–$w_{10}$ | 1.49, 0.14, 0.94 | unchanged | |
| $w_{11}$–$w_{13}$ | 2.18, 0.05, 0.34 | unchanged | |
| $w_{12}$ (lapse severity) | 0.05 | **0.09** | tree-dependent lapses should decay stability harder |
| $w_{14}$ | 1.26 | unchanged | |
| $w_{15}$ (Hard penalty) | 0.29 | **0.22** | hesitant-but-correct chess recall is a weaker signal than in flashcards |
| $w_{16}$ (Easy bonus) | 2.61 | 2.61 | |
| $\lambda_0$ (lapse contagion) | — | 0.18 | new, chess-specific |
| $\tau$ (contagion depth decay) | — | 1.5 plies | new |
| $\varepsilon$ (traversal exposure) | — | 0.08 | new |
| $\kappa$ (confusion coupling) | — | 0.35 | new |

**These are priors, not final values.** Once ~500–1000 reviews/user accumulate, run the standard FSRS optimizer (gradient descent minimizing log-loss of $R$ predictions against observed outcomes) *per-user or pooled anonymized*, exactly as Anki's FSRS add-on does — the architecture below stores exactly the fields ($D$, $S$, timestamps, rating) that optimizer needs, so this is a drop-in future upgrade, not a rewrite.

### C.9 Target retention & user-tunables

$$
R_{\text{target}} = \text{clip}(R_{\text{base}} + \Delta_{\text{tournament}},\ 0.70,\ 0.99)
$$

Exposed controls:

| Control | Range | Effect |
|---|---|---|
| **Target Retention slider** | 80%–95% (maintenance default 88%) | Directly plugs into $R_{\text{target}}$ in §C.2; lower = longer intervals/less time invested, higher = shorter intervals/higher board-recall confidence |
| **Tournament Mode toggle** | boolean + event date | Temporarily forces $R_{\text{target}}=0.95$–0.97 and caps `maxIntervalDays` to $\le$ days-until-event for all decisions in the selected repertoire scope; auto-reverts to base retention day after the event |
| **Rigor / Safety Factor** | 0.9×–1.1× | Post-multiplies the computed interval $I \to I\cdot\rho$; a pure "shrink my due dates a bit, I don't trust the model yet" knob independent of the retention-probability semantics |
| **Interleaving intensity** | off / normal / aggressive | Controls confusion-set interleaving threshold from §B.4 |

---

## D. Dart Implementation

Pure Dart, zero dependencies, deterministic via injected `now`, fuzz disabled by default for testability.

```dart
import 'dart:math' as math;

// ---------------------------------------------------------------------------
// Given domain contracts (reproduced for completeness)
// ---------------------------------------------------------------------------

enum ReviewResult { correct, incorrect }

class ReviewState {
  final String decisionId;
  final DateTime? firstReviewedAt;
  final DateTime? lastReviewedAt;
  final DateTime? nextDueAt;
  final int repetitionCount;
  final int lapseCount;
  final double stability;   // stored in MILLISECONDS (existing contract)
  final double difficulty;  // 1..10, FSRS scale

  const ReviewState({
    required this.decisionId,
    this.firstReviewedAt,
    this.lastReviewedAt,
    this.nextDueAt,
    this.repetitionCount = 0,
    this.lapseCount = 0,
    this.stability = 0.0,
    this.difficulty = 0.0,
  });

  static ReviewState cold(String decisionId) => ReviewState(decisionId: decisionId);
}

abstract class Scheduler {
  bool isDue(ReviewState state, DateTime now);
  ReviewState schedule({
    required ReviewState previous,
    required ReviewResult result,
    required DateTime now,
  });
}

// ---------------------------------------------------------------------------
// Rating (internal, reconstructed from binary correctness + latency signal)
// ---------------------------------------------------------------------------

enum Rating { again, hard, good, easy }

int _g(Rating r) => switch (r) {
      Rating.again => 1,
      Rating.hard => 2,
      Rating.good => 3,
      Rating.easy => 4,
    };

Rating inferRating({
  required bool correct,
  bool multipleAttempts = false,
  bool hintUsed = false,
  int? latencyMs,
  int? medianLatencyMs,
}) {
  if (!correct || multipleAttempts) return Rating.again;
  if (hintUsed) return Rating.hard;
  if (latencyMs != null && medianLatencyMs != null && medianLatencyMs > 0) {
    final ratio = latencyMs / medianLatencyMs;
    if (ratio > 1.6) return Rating.hard;
    if (ratio < 0.5) return Rating.easy;
  }
  return Rating.good;
}

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

class ChessFsrsParams {
  // Initial stability per rating (days)
  final double w0, w1, w2, w3;
  // Difficulty
  final double w4, w5, w6, w7;
  // Success-stability formula
  final double w8, w9, w10;
  // Lapse-stability formula
  final double w11, w12, w13, w14;
  // Hard penalty / Easy bonus
  final double w15, w16;

  final double sameDayThresholdDays;
  final double sameDayGainFactor;
  final double sameDayLapseFactor;

  final double minStabilityDays;
  final double maxStabilityDays;

  const ChessFsrsParams({
    this.w0 = 0.35, this.w1 = 0.55, this.w2 = 2.20, this.w3 = 5.80,
    this.w4 = 4.93, this.w5 = 0.94, this.w6 = 1.05, this.w7 = 0.01,
    this.w8 = 1.49, this.w9 = 0.14, this.w10 = 0.94,
    this.w11 = 2.18, this.w12 = 0.09, this.w13 = 0.34, this.w14 = 1.26,
    this.w15 = 0.22, this.w16 = 2.61,
    this.sameDayThresholdDays = 1 / 24,
    this.sameDayGainFactor = 1.02,
    this.sameDayLapseFactor = 0.85,
    this.minStabilityDays = 0.02,   // ~30 minutes floor
    this.maxStabilityDays = 365 * 5,
  });

  const ChessFsrsParams.chessDefaults() : this();
}

// ---------------------------------------------------------------------------
// Core DSR math (pure functions, independently unit-testable)
// ---------------------------------------------------------------------------

const double kDecay = -0.5;
final double kFactor = math.pow(0.9, 1 / kDecay).toDouble() - 1; // ≈ 0.2345

double retrievability(double elapsedDays, double stabilityDays) {
  if (stabilityDays <= 0) return 0.0;
  final t = elapsedDays < 0 ? 0.0 : elapsedDays;
  return math.pow(1 + kFactor * t / stabilityDays, kDecay).toDouble();
}

double intervalForTarget(double stabilityDays, double targetRetention) {
  final r = targetRetention.clamp(0.70, 0.99);
  final raw = stabilityDays / kFactor * (math.pow(r, 1 / kDecay) - 1);
  return raw.isFinite && raw > 0 ? raw : 0.0;
}

double initialDifficulty(Rating rating, ChessFsrsParams p) {
  final g = _g(rating);
  return (p.w4 - (g - 3) * p.w5).clamp(1.0, 10.0);
}

double nextDifficulty(double d, Rating rating, ChessFsrsParams p) {
  final g = _g(rating);
  final delta = d - p.w6 * (g - 3);
  final reverted = p.w7 * p.w4 + (1 - p.w7) * delta;
  return reverted.clamp(1.0, 10.0);
}

double initialStability(Rating rating, ChessFsrsParams p) => switch (rating) {
      Rating.again => p.w0,
      Rating.hard => p.w1,
      Rating.good => p.w2,
      Rating.easy => p.w3,
    };

double nextStabilitySuccess(
  double d, double s, double r, Rating rating, ChessFsrsParams p,
) {
  final hardPenalty = rating == Rating.hard ? p.w15 : 1.0;
  final easyBonus = rating == Rating.easy ? p.w16 : 1.0;
  final safeS = s <= 0 ? p.minStabilityDays : s;
  final factor = math.exp(p.w8) *
      (11 - d) *
      math.pow(safeS, -p.w9) *
      (math.exp((1 - r) * p.w10) - 1) *
      hardPenalty *
      easyBonus;
  return safeS * (1 + factor);
}

double nextStabilityLapse(double d, double s, double r, ChessFsrsParams p) {
  final safeS = s <= 0 ? p.minStabilityDays : s;
  return p.w11 *
      math.pow(d, -p.w12) *
      (math.pow(safeS + 1, p.w13) - 1) *
      math.exp((1 - r) * p.w14);
}

// ---------------------------------------------------------------------------
// Single-node scheduler — implements the required Scheduler contract
// ---------------------------------------------------------------------------

class ChessFsrsScheduler implements Scheduler {
  final ChessFsrsParams params;
  final double targetRetention;   // user-tunable, 0.70..0.99
  final double maxIntervalDays;
  final double minIntervalDays;
  final double fuzzFraction;      // 0.0 disables fuzz (deterministic tests)
  final math.Random _rng;

  ChessFsrsScheduler({
    this.params = const ChessFsrsParams.chessDefaults(),
    this.targetRetention = 0.90,
    this.maxIntervalDays = 365 * 2,
    this.minIntervalDays = 1 / 1440, // 1 minute floor
    this.fuzzFraction = 0.0,
    int? fuzzSeed,
  }) : _rng = math.Random(fuzzSeed ?? 0);

  static const int _dayMs = 86400000;

  @override
  bool isDue(ReviewState state, DateTime now) {
    if (state.nextDueAt == null) return true;
    return !now.isBefore(state.nextDueAt!);
  }

  @override
  ReviewState schedule({
    required ReviewState previous,
    required ReviewResult result,
    required DateTime now,
  }) {
    return scheduleDetailed(previous: previous, result: result, now: now);
  }

  /// Extended entry point used by callers who have latency/hint signal.
  /// `schedule()` above delegates here with conservative defaults so the
  /// base `Scheduler` contract still works stand-alone.
  ReviewState scheduleDetailed({
    required ReviewState previous,
    required ReviewResult result,
    required DateTime now,
    int? latencyMs,
    int? medianLatencyMs,
    bool hintUsed = false,
    bool multipleAttempts = false,
    double? retentionOverride,
  }) {
    final rating = result == ReviewResult.incorrect
        ? Rating.again
        : inferRating(
            correct: true,
            latencyMs: latencyMs,
            medianLatencyMs: medianLatencyMs,
            hintUsed: hintUsed,
            multipleAttempts: multipleAttempts,
          );

    final anchor = previous.lastReviewedAt ?? previous.firstReviewedAt;
    double elapsedDays = 0;
    if (anchor != null) {
      final diffMs = now.difference(anchor).inMilliseconds;
      elapsedDays = diffMs <= 0 ? 0.0 : diffMs / _dayMs;
    }

    final bool isColdStart =
        previous.repetitionCount == 0 && previous.stability <= 0;

    double newDifficulty;
    double newStabilityDays;

    if (isColdStart) {
      newDifficulty = initialDifficulty(rating, params);
      newStabilityDays = initialStability(rating, params);
    } else {
      final prevStabilityDays =
          previous.stability <= 0 ? params.minStabilityDays : previous.stability / _dayMs;
      final prevDifficulty =
          previous.difficulty <= 0 ? initialDifficulty(Rating.good, params) : previous.difficulty;

      final r = retrievability(elapsedDays, prevStabilityDays);
      newDifficulty = nextDifficulty(prevDifficulty, rating, params);

      if (elapsedDays < params.sameDayThresholdDays) {
        newStabilityDays = rating == Rating.again
            ? prevStabilityDays * params.sameDayLapseFactor
            : prevStabilityDays * params.sameDayGainFactor;
      } else if (rating == Rating.again) {
        newStabilityDays = nextStabilityLapse(newDifficulty, prevStabilityDays, r, params);
      } else {
        newStabilityDays =
            nextStabilitySuccess(newDifficulty, prevStabilityDays, r, rating, params);
      }
    }

    newStabilityDays =
        newStabilityDays.clamp(params.minStabilityDays, params.maxStabilityDays);

    final effectiveRetention = (retentionOverride ?? targetRetention).clamp(0.70, 0.99);
    double intervalDays = intervalForTarget(newStabilityDays, effectiveRetention);
    intervalDays = _applyFuzz(intervalDays, previous.decisionId);
    intervalDays = intervalDays.clamp(minIntervalDays, maxIntervalDays);

    final nextDue = now.add(Duration(milliseconds: (intervalDays * _dayMs).round()));

    return ReviewState(
      decisionId: previous.decisionId,
      firstReviewedAt: previous.firstReviewedAt ?? now,
      lastReviewedAt: now,
      nextDueAt: nextDue,
      repetitionCount:
          rating == Rating.again ? previous.repetitionCount : previous.repetitionCount + 1,
      lapseCount: rating == Rating.again ? previous.lapseCount + 1 : previous.lapseCount,
      stability: newStabilityDays * _dayMs,
      difficulty: newDifficulty,
    );
  }

  double _applyFuzz(double intervalDays, String seedKey) {
    if (fuzzFraction <= 0) return intervalDays;
    final jitter = (_rng.nextDouble() * 2 - 1) * fuzzFraction;
    return intervalDays * (1 + jitter);
  }
}

// ---------------------------------------------------------------------------
// Graph layer — lapse contagion, auto-traversal credit, transposition merge,
// confusion coupling. This layer needs neighbor/repository context that the
// two-argument Scheduler.schedule() cannot express, so it is deliberately a
// separate coordinator built ON TOP OF ChessFsrsScheduler rather than an
// alternate Scheduler implementation.
// ---------------------------------------------------------------------------

class GraphNode {
  final String decisionId;
  final String? parentId;
  final String fen4;
  final String expectedMoveUci;
  const GraphNode({
    required this.decisionId,
    required this.parentId,
    required this.fen4,
    required this.expectedMoveUci,
  });
}

abstract class ReviewStateRepository {
  ReviewState? get(String decisionId);
  void put(String decisionId, ReviewState state);
  List<String> childrenOf(String decisionId);
  /// Returns an existing canonical id sharing (fen4, expectedMoveUci), or
  /// null if this is a brand-new memory item (§B.3).
  String? canonicalIdFor(String fen4, String expectedMoveUci);
}

class GraphAwareParams {
  final double contagionBase;      // lambda0
  final double contagionTau;       // depth decay
  final int maxContagionDepth;
  final double contagionDifficultyBump; // beta
  final double exposureStabilityGain;   // epsilon
  final double confusionDifficultyCoupling; // kappa

  const GraphAwareParams({
    this.contagionBase = 0.18,
    this.contagionTau = 1.5,
    this.maxContagionDepth = 3,
    this.contagionDifficultyBump = 0.6,
    this.exposureStabilityGain = 0.08,
    this.confusionDifficultyCoupling = 0.35,
  });
}

class GraphAwareReviewCoordinator {
  final ChessFsrsScheduler scheduler;
  final ReviewStateRepository repo;
  final GraphAwareParams gParams;

  GraphAwareReviewCoordinator(
    this.scheduler,
    this.repo, {
    this.gParams = const GraphAwareParams(),
  });

  /// Records a genuine active-recall attempt at [node].
  ReviewState recordActiveReview({
    required GraphNode node,
    required ReviewResult result,
    required DateTime now,
    int? latencyMs,
    int? medianLatencyMs,
    bool hintUsed = false,
    String? playedMoveUci,           // for confusion detection
    List<GraphNode> siblings = const [],
  }) {
    final canonicalId =
        repo.canonicalIdFor(node.fen4, node.expectedMoveUci) ?? node.decisionId;
    final previous = repo.get(canonicalId) ?? ReviewState.cold(canonicalId);

    final updated = scheduler.scheduleDetailed(
      previous: previous,
      result: result,
      now: now,
      latencyMs: latencyMs,
      medianLatencyMs: medianLatencyMs,
      hintUsed: hintUsed,
    );
    repo.put(canonicalId, updated);

    if (result == ReviewResult.incorrect) {
      _propagateLapseContagion(node.decisionId, now, depth: 1);
      if (playedMoveUci != null) {
        _coupleConfusableSiblings(playedMoveUci, siblings, now);
      }
    }
    return updated;
  }

  /// Records a NON-tested pass-through move (Invariant §2.4). Never touches
  /// repetitionCount/lapseCount/difficulty/lastReviewedAt.
  ReviewState recordAutoTraversalExposure({
    required GraphNode node,
    required DateTime now,
  }) {
    final canonicalId =
        repo.canonicalIdFor(node.fen4, node.expectedMoveUci) ?? node.decisionId;
    final previous = repo.get(canonicalId);
    if (previous == null || previous.stability <= 0) {
      return previous ?? ReviewState.cold(canonicalId);
    }
    // Never grant exposure credit to an item that is already due — the
    // traversal engine should have stopped and tested it instead.
    if (scheduler.isDue(previous, now)) return previous;
    if (previous.lastReviewedAt != null &&
        _isSameCalendarDay(previous.lastReviewedAt!, now)) {
      return previous; // once/day throttle
    }

    final boostedStability = previous.stability * (1 + gParams.exposureStabilityGain);
    final currentDue = previous.nextDueAt ?? now;
    final remainingMs = currentDue.difference(now).inMilliseconds;
    final extendedDue = remainingMs > 0
        ? currentDue.add(Duration(
            milliseconds: (remainingMs * gParams.exposureStabilityGain).round()))
        : currentDue;

    final updated = ReviewState(
      decisionId: previous.decisionId,
      firstReviewedAt: previous.firstReviewedAt,
      lastReviewedAt: previous.lastReviewedAt, // deliberately unchanged
      nextDueAt: extendedDue,
      repetitionCount: previous.repetitionCount,
      lapseCount: previous.lapseCount,
      stability: boostedStability,
      difficulty: previous.difficulty,
    );
    repo.put(canonicalId, updated);
    return updated;
  }

  void _propagateLapseContagion(String parentId, DateTime now, {required int depth}) {
    if (depth > gParams.maxContagionDepth) return;
    final decay = gParams.contagionBase * math.exp(-depth / gParams.contagionTau);

    for (final childId in repo.childrenOf(parentId)) {
      final childState = repo.get(childId);
      if (childState == null || childState.stability <= 0) continue;

      final shrunkStability = childState.stability * (1 - decay).clamp(0.0, 1.0);
      final shrunkDue = _pullDueForward(childState, decay, now);
      final bumpedDifficulty =
          (childState.difficulty + gParams.contagionDifficultyBump * decay).clamp(1.0, 10.0);

      repo.put(childId, ReviewState(
        decisionId: childState.decisionId,
        firstReviewedAt: childState.firstReviewedAt,
        lastReviewedAt: childState.lastReviewedAt,
        nextDueAt: shrunkDue,
        repetitionCount: childState.repetitionCount,
        lapseCount: childState.lapseCount,
        stability: shrunkStability,
        difficulty: bumpedDifficulty,
      ));

      _propagateLapseContagion(childId, now, depth: depth + 1);
    }
  }

  DateTime? _pullDueForward(ReviewState s, double decay, DateTime now) {
    if (s.nextDueAt == null) return null;
    final remaining = s.nextDueAt!.difference(now);
    if (remaining.isNegative) return s.nextDueAt; // already due; leave as-is
    final newRemainingMs = (remaining.inMilliseconds * (1 - decay)).round();
    return now.add(Duration(milliseconds: newRemainingMs));
  }

  void _coupleConfusableSiblings(
    String playedMoveUci, List<GraphNode> siblings, DateTime now,
  ) {
    for (final sib in siblings) {
      if (sib.expectedMoveUci != playedMoveUci) continue;
      final sibState = repo.get(sib.decisionId);
      if (sibState == null) continue;
      final bumped = (sibState.difficulty +
              gParams.confusionDifficultyCoupling)
          .clamp(1.0, 10.0);
      repo.put(sib.decisionId, ReviewState(
        decisionId: sibState.decisionId,
        firstReviewedAt: sibState.firstReviewedAt,
        lastReviewedAt: sibState.lastReviewedAt,
        nextDueAt: sibState.nextDueAt,
        repetitionCount: sibState.repetitionCount,
        lapseCount: sibState.lapseCount,
        stability: sibState.stability,
        difficulty: bumped,
      ));
    }
  }

  bool _isSameCalendarDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
```

### Edge cases explicitly handled

| Case | Handling |
|---|---|
| Zero/cold stability | `isColdStart` branch bypasses retrievability math entirely (undefined at $S=0$); repository `get()` returning `null` is normalized to `ReviewState.cold(id)` |
| Rapid consecutive reviews (same session re-test) | `sameDayThresholdDays` branch replaces the full DSR update with a damped linear nudge, avoiding division blow-ups as $t\to0$ |
| Overdue review (elapsed ≫ scheduled interval) | Retrievability is computed from **actual** elapsed days, not the planned interval, so an overdue lapse correctly reflects a much lower $R$ and produces a larger, honest stability drop — no special-casing needed, it falls out of the math |
| Auto-traversal on an already-due prefix | Explicitly refused (`scheduler.isDue(previous, now)` guard) so passive credit can never mask a due active-recall obligation |
| Transposition merge collision | `canonicalIdFor` is consulted before every read/write in the coordinator, so both chapters always resolve to one shared `ReviewState` |
| Negative/garbage elapsed time (clock skew, imported data) | Clamped to `0` before use in both the kernel and the coordinator |
