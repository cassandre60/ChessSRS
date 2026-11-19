# Chess & SRS Domain Audit

**Date:** 2026-11-17  
**Scope:** SRS algorithm correctness, review engine logic, position identity,
PGN handling, review traversal, opening classification, edge cases.  
**Files audited:** `chess_fsrs_scheduler.dart`, `scheduler.dart`,
`graph_aware_review_coordinator.dart`, `review_session.dart`,
`review_engine.dart`, `position_knowledge_state.dart`, `pgn_importer.dart`,
`pgn_exporter.dart`, `opening_name.dart`, `openings_database.dart`,
`review_state.dart`, `review_order.dart`, `review_continuity.dart`,
`review_prompt.dart`, `due_status.dart`, `clock.dart`, `repertoire_node.dart`,
`repertoire_move.dart`.

---

## 1. SRS Algorithm Correctness

### 1.1 FSRS Math Verification

The implementation (`chess_fsrs_scheduler.dart`) is an **FSRS-4.5-style binary
adaptation**, correctly self-identified in the class doc (line 197). It is **not
FSRS-5**: the code uses the FSRS-4.5 difficulty form `D' = w7·D₀ + (1-w7)(D -
w6·(g-3))` rather than FSRS-5's exponential initial difficulty
`D₀(G) = w₄ - e^(w₅·(G-1)) + 1` and same-day formula
`S' = S·e^(w₁₇·(G-3+w₁₈))`.

| Formula | Reference (FSRS-4.5) | Implementation | ✅/⚠️ |
|---------|---------------------|----------------|-------|
| Retrievability R(t,S) | `(1 + F·t/S)^C` where C=-0.5, F=19/81 | Lines 142-146 | ✅ Correct |
| Interval I(S,r) | `S/F·(r^(1/C)−1)` | Lines 149-153 | ✅ Correct |
| Initial difficulty D₀(g) | `clip(w₄−(g−3)·w₅, 1, 10)` | Lines 156-159 | ✅ Correct (FSRS-4.5 linear form) |
| Next difficulty D'(D,g) | `clip(w₇·w₄+(1−w₇)·(D−w₆·(g−3)), 1, 10)` | Lines 162-167 | ✅ Correct (mean reversion toward D₀, FSRS-4.5) |
| Initial stability S₀ | `w₀` for Again, `w₂` for Good | Lines 170-171 | ✅ Correct (binary only, w₁/w₃ absent) |
| Success stability S' | `S·(1+e^w₈·(11−D)·S^(−w₉)·(e^((1−R)·w₁₀)−1))` | Lines 174-178 | ✅ Correct |
| Lapse stability S' | `w₁₁·D^(−w₁₂)·((S+1)^w₁₃−1)·e^((1−R)·w₁₄)` | Lines 189-191 | ✅ Correct |
| Factor F | `0.9^(1/C)−1 = 19/81 ≈ 0.2346` | Lines 129-130 | ✅ Correct |

> [!IMPORTANT]
> **Finding SRS-01** (Informational/Low): The lapse formula (`(S+1)^w₁₃ − 1`)
> can produce a value **larger than S** for sufficiently overdue, low-stability
> items. This is **documented in the codebase** (lines 183-188) and matches the
> FSRS reference implementation's behavior. The scheduling architecture doc §C.6
> explicitly states this. No fix needed — adding `min(result, s)` would be a
> spec change.

### 1.2 Retention Target Clamping

The `clamp(0.70, 0.99)` appears 3 times:

| Location | Context | Correct? |
|----------|---------|----------|
| `fsrsIntervalForTarget` L150 | Clamping target retention before interval computation | ✅ |
| `ChessFsrsScheduler.schedule` L277 | Clamping before computing the actual interval | ✅ |
| `fsrsIntervalProgressionPreview` L334 | Preview uses same clamp chain | ✅ |

> [!TIP]
> **Finding SRS-02** (Low): The triple clamp is correct and necessary — each
> call site may receive unclamped values. The 70-99% range is reasonable for
> chess repertoire use. Standard FSRS Anki implementations also use similar
> bounds. The preview function mirrors the scheduler's clamp-then-interval
> chain, preventing the preview from advertising intervals the scheduler would
> never emit (line 321 doc comment confirms this).

### 1.3 Stability and Interval Bounds

| Bound | Value | Purpose | Assessment |
|-------|-------|---------|------------|
| `minStabilityDays` | 0.02 (~30 min) | Prevents stability from reaching 0 | ✅ Sensible |
| `maxStabilityDays` | 1825 (5 years) | Caps accumulated stability | ✅ Sensible |
| `maxIntervalDays` | 1095 (3 years) | Caps scheduled interval | ✅ Sensible (< maxStability) |
| `minIntervalDays` | 1/1440 (~1 min) | Floor for rapid re-review | ✅ Sensible |

### 1.4 Rapid Re-Review Guard (§C.7)

Lines 255-272: When elapsed time < `sameDayThresholdDays` (1 hour), the full
DSR update is skipped. Difficulty **freezes** and stability gets a small
multiplicative nudge (1.02 for success, 0.85 for lapse).

> [!TIP]
> **Finding SRS-03** (Informational): This is a **good design decision**. Without
> this guard, 3 intra-session misses could ratchet difficulty to 10.0 (shrinking
> the `(11−D)` growth term from ~6.07 to 1.00), taking ~390 successful reviews
> to unwind (line 259 comment). The FSRS-5 reference handles same-day reviews
> with `S' = S·e^(w₁₇·(G−3+w₁₈))`, which is a different but analogous approach.

### 1.5 Three Schedulers

| Scheduler | Mechanism | INV-025 Compliance | Assessment |
|-----------|-----------|-------------------|------------|
| `SimpleScheduler` | Geometric ladder: 1d → 2d → 2x | ✅ Success grows, lapse resets to rep=0 | ✅ Sound |
| `EaseScalingScheduler` | 1d → 2.5d → 1.5x | ✅ Success grows, lapse resets to rep=0 | ✅ Sound |
| `ChessFsrsScheduler` | DSR power-law FSRS | ✅ Keeps repCount on success, lapses increment lapseCount | ⚠️ See SRS-04 |

> [!WARNING]
> **Finding SRS-04** (Medium): The FSRS scheduler does **not** reset
> `repetitionCount` on lapse (line 295-298: `repetitionCount` stays unchanged on
> Again). The ladder schedulers reset it to 0. SPEC INV-025 says "lapses restart
> [the interval]", which the FSRS scheduler does (new lapse stability is
> computed). But INV-025 also says "resets the streak", which FSRS does not do
> explicitly — it just keeps repCount. This is **documented as a known conflict**
> tracked in `docs/open-questions.md` Q9. No action needed beyond tracking.

### 1.6 Binary Grading (Decision D015)

Lines 229-230: `ReviewResult.incorrect → FsrsRating.again (g=1)`,
`ReviewResult.correct → FsrsRating.good (g=3)`. No Hard/Easy, no latency
inference. This is correct per the scheduling architecture §A.

### 1.7 Cold Start Detection

Line 239: `isColdStart = previous.repetitionCount == 0 && previous.stability <= 0`.
This is sound — a fresh state has zero reps and zero stability. After any review
(even a lapse), stability becomes positive.

### 1.8 Stability Storage Units

Stability is stored in **milliseconds** in `ReviewState` (line 14-16 of
review_state.dart). The FSRS scheduler converts to/from days at its boundary
(line 248-250: `previous.stability / _dayMs`, line 299:
`newStabilityDays * _dayMs`). Ladder schedulers store the interval duration in
milliseconds directly. The dual semantics of the `stability` field are
**documented as a known gap** (review_state.dart line 15-17).

---

## 2. Review Engine Logic

### 2.1 Board-Only FEN Truth (INV-020)

The `_resolvePlayedMove` method (review_session.dart L1476-1525) correctly
implements board-only truth:

1. First checks the prompted decision's expected moves (direct match)
2. If transposition scope is on, checks all in-scope decisions at the same
   4-field FEN (`_decisionsByFenKey[prompt.fenKey]`)
3. Falls back to computing the destination FEN from the played move and looking
   for any in-scope node at that position

This is correct per INV-020 and INV-065.

### 2.2 Transposition Acceptance (INV-065)

Three-level scope: `TransposeScope.off`, `.withinStudy`, `.inScope`. The
`_findTransposedNode` method (L1529-1596) correctly:
- Computes the resulting position via dartchess
- Looks up nodes at the destination FEN key
- Respects scope constraints
- Prefers nodes reached by the same move, falls back to any node at that FEN

> [!NOTE]
> **Finding REV-01** (Low): The transposition lookup uses `_nodesByFenKey` which
> requires chapter tree decoding. For chapters not yet indexed, it triggers
> synchronous decoding (`_ensureAllChaptersIndexed()` at L1560). With large
> repertoires (many chapters), this could cause a one-time latency spike on the
> first transposition within an un-indexed chapter. This is mitigated by the
> background indexing pass and the flat `nodeIndex` fast path (L1558).

### 2.3 Fresh Introduction Caps (INV-068)

The session correctly:
1. Separates fresh (never-presented) from due items at build time (L140-163)
2. Puts due items first, then fresh (L202-204)
3. Caps fresh introductions via `remainingNewQuota` (L189-196)
4. Tracks admitted fresh IDs in `_admittedFreshIds` (L200)
5. Blocks held-back fresh positions from being introduced during line walks
   (L1079-1100)

This is a well-designed gating mechanism.

### 2.4 Prompt Selection Algorithm

The session uses a **due-aware weighted selection** strategy for opponent replies:

- `_selectOpponentChild` (L1615-1641): Weights branches by due-decision count
  below them. If nothing is due, random uniform draw.
- `_selectUserContinuation` (L1647-1666): Deterministic: branch with most due
  decisions below, ties broken by list order (mainline first).

> [!TIP]
> **Finding REV-02** (Informational/Optimization): The opponent selection uses
> random weighted, while user continuation uses deterministic max-due. This
> asymmetry is intentional: the opponent path injects variety (the user doesn't
> control it), while the user continuation is auto-played and should
> deterministically reach the most urgent material. This is a good design.

### 2.5 Corrected False-Start Grading

Lines 795-796: When a lapsed decision is re-tested correctly, the success is
**not** graded again (no double-write). The `_lapsedThisSession` set tracks
this. `_pendingRetest` tracks lapsed decisions that must be re-tested before
session completion. This correctly implements D015's "corrected false-start"
semantics.

### 2.6 Session Checkpoint/Restore

The checkpoint mechanism (L670-717) captures all mutable state including:
review states, both queue buffers, completed/lapsed/pending sets, current
prompt, exposure throttle, unlocked IDs, and admitted fresh IDs. Restore clears
and re-fills each. This is complete and correct for rollback on persistence
failure.

---

## 3. Position Identity

### 3.1 Canonical Key Computation

Two functions exist in `position_knowledge_state.dart`:

| Function | Format | Use |
|----------|--------|-----|
| `canonicalKey(fenKey, moveUci)` | `sha1("fenKey\|moveUci")` | Legacy compatibility (single-move) |
| `canonicalKeyForPosition(fenKey, moves, side)` | `sha1("side\|fenKey\|sortedUci1\|sortedUci2\|...")` | Current complete-set identity |

The current format matches ARCHITECTURE.md §5:
`sha1("<repertoireSide.name>|<fenKey>|<sorted uci>|<sorted uci>|...")`.

> [!NOTE]
> **Finding POS-01** (Informational): The sorting of accepted move UCIs
> (L44: `toList()..sort()`) ensures two PGNs with the same repertoire in
> different variation order converge on the same canonical key. This is correct.

### 3.2 Four-Field FEN Identity (INV-015)

`positionIdentity()` in `model/common/chess.dart` (L427-431) splits on spaces
and takes the first 4 fields: placement, turn, castling, en-passant. This is
correct — half-move clock and full-move number are excluded.

### 3.3 En Passant Edge Cases

The 4-field FEN **includes** the en-passant square from dartchess, which
normalizes it: dartchess only sets the EP square when a pawn can actually
capture (a legal EP is available). Two positions that differ only in a
"phantom" EP square (where no capture is possible) will have the same
normalized FEN from dartchess.

> [!NOTE]
> **Finding POS-02** (Informational): dartchess's EP normalization is correct per
> FIDE rules. The `computePgnHash` function (pgn_importer.dart L40-48) also
> normalizes starting FENs through dartchess before hashing, ensuring consistent
> identity.

### 3.4 Castling Rights

Castling rights are part of the 4-field FEN and correctly participate in
position identity. The `RepertoireMove.matches()` method (repertoire_move.dart
L35-55) handles castling notation equivalence:

```dart
static const _kingTakesRookCastles = {
  'e1c1': 'e1a1', 'e1g1': 'e1h1',
  'e8c8': 'e8a8', 'e8g8': 'e8h8',
};
```

This maps standard UCI castling to king-takes-rook form, so `e1g1` (O-O as
standard) matches `e1h1` (king-takes-rook). This satisfies INV-033.

> [!WARNING]
> **Finding POS-03** (Medium): The castling normalization in `matches()` maps
> standard UCI to king-takes-rook for **comparison**, but the **canonical key**
> includes the raw UCI string from the repertoire tree. If two PGN files encode
> the same O-O castling as `e1g1` vs `e1h1`, they would produce **different**
> canonical keys (since the sorted UCI list differs), leading to separate SRS
> memory for what is the same question. In practice, dartchess consistently
> produces one form (standard UCI), so this is unlikely to trigger. But it's a
> theoretical inconsistency between grading (which normalizes) and identity
> (which doesn't).

---

## 4. PGN Handling

### 4.1 Tree Construction (pgn_importer.dart)

The `_buildChildren` function (L667-751) recursively processes the dartchess
PGN AST:
- Each `PgnNode` child becomes a `RepertoireNode` child
- Illegal/unparseable moves produce `ImportError` and skip the continuation
- Comments are concatenated from both pre-move and post-move positions (L727)
- NAGs are preserved (L734)
- Drop moves (Crazyhouse) are silently skipped (L716-719)
- Unsupported variants are refused with a typed error (L303-317)

> [!TIP]
> **Finding PGN-01** (Informational): The `_buildChildren` approach is correct
> for RAV handling. Each PGN child becomes a sibling in the RepertoireNode
> tree, so `1. e4 e5 (1... c5) (1... e6)` creates a root with three children.
> Deeply nested RAVs work because the recursion follows the PGN AST naturally.

### 4.2 Round-Trip Fidelity

The exporter (`pgn_exporter.dart`) preserves:
- **Chapter titles** via `[Chapter]` and `[Study]` tags (L52-54)
- **Orientation** via `[Orientation]` tag (L47)
- **Opening** via `[Opening]` tag (L58-59)
- **Custom starting FEN** via `[SetUp]` and `[FEN]` (L62-65)
- **Variations** as parenthesized RAVs (L138-157)
- **Comments** (L131-133, L150-152)
- **NAGs** (L103-107)

> [!NOTE]
> **Finding PGN-02** (Low): The exporter correctly handles PGN tag value
> escaping via `_tagValue()` (L218-221), which escapes `\` and `"` and strips
> newlines. This prevents malformed PGN from titles containing quotes (documented
> as a past bug).

### 4.3 Custom Starting FEN

Lines 319-334: The importer uses `PgnGame.startingPosition(headers)` from
dartchess, which handles `[SetUp "1"][FEN "..."]` headers. Invalid FENs
produce a structured error and skip the chapter (not the whole study).

### 4.4 Comment Handling

Lines 727: Both `startingComments` (before the move) and `comments` (after the
move) are concatenated with a space separator. This handles the common PGN
pattern `{before} 1. e4 {after}` where studies carry both pre- and post-move
annotations.

> [!WARNING]
> **Finding PGN-03** (Low): Comments are joined with a single space. If the
> original PGN had distinct pre-move and post-move comments, the boundary
> between them is lost on import. After export → re-import, the joined comment
> would be in the post-move position only (since the exporter writes only
> post-move comments at L131-133). This is a **minor fidelity loss** but
> acceptable for the repertoire use case where comments are typically post-move.

### 4.5 PGN Hash Stability

`computePgnHash` (L27-67) strips volatile headers and hashes only the move
tree structure. `computeRepertoireTreeHash` (L90-103) produces the same hash
from stored domain trees. Starting FENs are normalized through dartchess before
hashing (L40-48), which prevents EP/castling normalization differences.

---

## 5. Review Traversal

### 5.1 Due-Only vs Full-Line Continuity

| Mode | Behavior | Assessment |
|------|----------|------------|
| `dueOnly` | Quiz only due positions; auto-play learned moves | ✅ Correct |
| `fullLine` | Quiz every position along the line in tree order | ✅ Correct |

In `fullLine` mode:
- Opponent selection follows tree order (mainline first, L1625-1627)
- User continuation follows tree order (L1652-1655)
- Already-answered positions are re-answered as practice (no double SRS write,
  L743-746, L801-803)
- Line starts are opened once per session (L1299-1336)

### 5.2 Order Modes (INV-066)

| Order | Implementation | Assessment |
|-------|---------------|------------|
| `dueDate` | Most overdue first (L176-185) | ✅ Correct |
| `byLine` | Study → chapter → tree order within buckets (L250-274) | ✅ Correct |
| `random` | Shuffled within buckets using session Random (L279-290) | ✅ Correct |

> [!IMPORTANT]
> **Finding TRV-01** (Informational): All three orders operate **within**
> the due-then-fresh bucket structure. Fresh positions are always after due
> ones in SRS mode (L202-204), and each order reshuffles only within its
> bucket (L235-247). This correctly prevents fresh material from overtaking
> recall work (INV-068 compliance).

### 5.3 Due-Date Sorting of Fresh Items

Lines 180-184: Fresh items have `nextDueAt == null`. In the due-date sort,
null dates sort **first** (L182: `if (dueA == null) return -1`). But this
only applies within the due bucket itself. Fresh items are in a separate
bucket (L202-204), so this null handling only affects items within the due
bucket that happen to have null dates (edge case: legacy items).

---

## 6. Graph-Aware Coordinator

### 6.1 Lapse Contagion (§B.1)

`_propagateLapseContagion` (L232-271):
- Depth counts from 1 at the immediate child (L239-241 comment)
- Decay formula: `decay = λ₀ · e^(-(depth-1)/τ)`, clamped to [0,1] (L249-250)
- Stability: `S' = S·(1−decay)` (L256)
- Due date pulled forward by the same factor (L257, L273-279)
- Difficulty bumped: `D' = clip(D + β·decay, 1, 10)` (L258-259)
- Guards: tau ≤ 0 → decay set to 1.0 (safe fallback, L249)
- Cold/zero-stability states skipped (L254)
- Max depth capped at 3 (L238)

> [!NOTE]
> **Finding GAR-01** (Informational): The contagion correctly walks the
> chapter subtree only (not cross-chapter/cross-study). The
> `_SessionReviewStateRepository.childrenOf()` method (L1729-1749) finds
> children within the decision's chapter tree, which is correct per §B.1.

### 6.2 Auto-Traversal Exposure (§B.2)

`recordAutoTraversalExposure` (L196-230):
- Returns null for unknown nodes (no phantom row creation, L201)
- Skips zero/negative stability (L203)
- Skips already-due items (L206)
- Throttled: once per calendar day, checking both `lastReviewedAt` and
  `_lastExposedAt` (L209-215)
- Stability bump: `S' = S·(1 + ε)` where ε=0.08 (L217)
- Due date extended proportionally (L219-224)

✅ All correct per §B.2 and INV-028.

### 6.3 Confusion Sibling Coupling (§B.4)

`_coupleConfusableSiblings` (L281-297):
- Only runs when the played move matches a sibling's expected move (L287)
- Difficulty bumped by `confusionDifficultyCoupling` (0.35), clamped to [1,10]
  (L292-293)
- No persistence of confusion edges — purely transient difficulty bump

✅ Correct per §B.4 and INV-029.

---

## 7. Opening Classification

### 7.1 Classification Accuracy

`extractOpeningFamily` (opening_name.dart L256-296) uses a 5-level fallback:

1. Direct `[Opening]` header → simplified (unless it merely mentions a family)
2. `[Event]` header → simplified (must pass `isLikelyOpeningFamily`)
3. ECO code → `ecoToOpeningFamily` mapping
4. Move-tree inspection → `detectOpeningFamilyFromMoves`
5. FEN piece-placement inspection → `detectOpeningFamilyFromFen`

> [!WARNING]
> **Finding OPN-01** (Medium): The move-tree detection
> (`detectOpeningFamilyFromMoves`, L111-191) uses mainline-only inspection (up
> to 8 moves). This means:
> - A study titled "Sicilian Defense" with a custom FEN starting from a Sicilian
>   tabia won't be detected by moves (since the mainline starts from the
>   tabia, not 1. e4 c5). It **will** be caught by the FEN fallback if the
>   piece placement matches.
> - **Transpositions** like 1. d4 Nf6 2. c4 g6 3. Nc3 d5 (Grünfeld) are
>   detected correctly (L168), but 1. Nf3 d5 2. d4 Nf6 3. c4 g6 (reaching the
>   same position via a different move order) would reach the "Queen's Pawn
>   Game" at L181-184, not Grünfeld, because Nf3 hits the Réti branch first.

> [!NOTE]
> **Finding OPN-02** (Low): The ECO mapping (L299-327) has gaps. For example:
> - `A00-A09` (unusual openings) → no mapping
> - `A45-A79` (various d4 systems) → no mapping
> - `B00-B09` returns "Scandinavian / Alekhine" which conflates two openings
> - `E10-E19` (Queen's Indian, etc.) → no mapping
> - `C20-C59` all return "Open Game" (losing Giuoco Piano, Four Knights, etc.)
>
> These are acceptable for a family-level classification. The bundled
> `chess_openings.db` (from lichess-org/chess-openings) provides more granular
> lookup but isn't used for SRS classification — it's for the analysis board.

### 7.2 Hub Name Validation (INV-067)

`isLikelyOpeningFamily()` (L67-72) correctly requires the name to either:
- Start with a known family keyword, OR
- End with a category noun (defense, gambit, attack, system, opening)

`mentionsOpeningButIsNotFamily()` (L82-87) detects names that mention a family
without being one (e.g., "White vs French"). This prevents spurious opening
hubs.

---

## 8. Edge Cases and Correctness Risks

### 8.1 Empty / Minimal Studies

| Scenario | Behavior | Assessment |
|----------|----------|------------|
| Empty PGN | Returns ImportResult with error, no chapters | ✅ Correct (L266-281) |
| PGN with 0 moves | Root node created, no decisions derived | ✅ Correct (L647-648) |
| Single-move study | 1 decision for the repertoire side | ✅ Correct |
| No moves for selected side | Error: "No repertoire positions found" (L405-414) | ✅ Correct |

### 8.2 Very Large Studies

| Concern | Mitigation | Assessment |
|---------|-----------|------------|
| 10MB+ PGN | `kMaxPgnInputBytes = 10MB` guard (L185, L232-237) | ✅ |
| Many chapters | Background indexing with `kSynchronousIndexingChapterBudget = 8` (L303-313) | ✅ |
| Deep variation nesting | No explicit depth limit, but bounded by PGN parse depth and stack | ⚠️ See below |
| Huge number of decisions | Prefetch batching with `kDefaultPrefetchBatchSize = 25` (L597-606) | ✅ |

> [!WARNING]
> **Finding EDGE-01** (Low): Very deeply nested RAVs (e.g., 1000+ levels) could
> cause a stack overflow in `_buildChildren` (recursive) and `_indexNodes`
> (recursive). In practice, chess repertoires rarely exceed 40 ply depth and a
> few hundred variations, so this is unlikely. If paranoid, an explicit depth
> guard could be added (stack-safe iterative traversal).

### 8.3 Chess960 / FRC

No explicit Chess960 support exists. The `_supportedVariantTags` set (L194)
includes `'standard'`, `'chess'`, and `'from position'`, but not `'chess960'`
or `'fischerandom'`. Chess960 PGN with a `[Variant "Chess960"]` tag would be
**refused** at import (L304-317).

A Chess960 PGN without a Variant tag would import, but castling moves may
be incorrect since dartchess may interpret king-takes-rook moves differently
in a standard Chess context.

> [!NOTE]
> **Finding EDGE-02** (Low): Chess960 is not in scope (MVP.md §3 defers it).
> The refusal is correct behavior — importing would silently produce wrong trees.

### 8.4 Promotion Handling

Promotions are handled correctly throughout:
- `RepertoireMove` stores `promotion` as a char (`q/r/b/n`) (L26)
- `normalmoveToRepertoireMove` converts dartchess NormalMove's promotion role
  to the char (pgn_importer.dart L204-212)
- The review session's `_resolvePlayedMove` builds a NormalMove with the
  promotion role for FEN computation (review_session.dart L1538-1549)
- `matches()` compares promotion fields (repertoire_move.dart L48)

### 8.5 FEN Normalization

The `fenKey()` function delegates to `positionIdentity()` which takes the
first 4 space-delimited fields. dartchess normalizes FENs on parsing:
- Castling rights in canonical order
- EP square only when capturable
- Piece placement is piece-by-piece faithful

> [!NOTE]
> **Finding EDGE-03** (Informational): An edge case exists where a FEN has fewer
> than 4 space-delimited parts. `positionIdentity` returns the raw string
> as-is in that case (L429). This is defensive but means malformed FENs would
> get unique identities, which is acceptable (they'd fail import anyway).

### 8.6 ReviewState.copyWith Nullable Fields

The `copyWith` method uses `??` for all fields, meaning you **cannot** set
nullable fields (like `nextDueAt`, `firstReviewedAt`) back to `null` once
they're set. This is a standard Dart pattern limitation.

> [!WARNING]
> **Finding EDGE-04** (Medium): `PositionKnowledgeState.copyWith` has the same
> limitation. If the domain ever needs to "unset" a nullable DateTime field
> (e.g., clearing `nextDueAt`), the current `copyWith` cannot do it. This would
> require a sentinel value pattern or a wrapper. Currently no call site needs
> this — `nextDueAt` is always set to a future time, never cleared.

---

## 9. Comparison with State-of-Art SRS Implementations

### 9.1 ChessSRS vs Standard FSRS-5

| Feature | FSRS-5 (Anki) | ChessSRS FSRS | Notes |
|---------|--------------|---------------|-------|
| Rating scale | 4 buttons (Again/Hard/Good/Easy) | Binary (Again/Good) | Chess D015: thinking time ≠ weak memory |
| Difficulty init | Exponential: `w₄ − e^(w₅·(G−1)) + 1` | Linear: `w₄ − (g−3)·w₅` | FSRS-4.5 form, documented |
| Difficulty update | Same as ChessSRS (mean reversion) | Same | ✅ |
| Same-day formula | `S·e^(w₁₇·(G−3+w₁₈))` | Multiplicative: `S·factor` | Different but analogous |
| Weight count | 19 (w₀-w₁₈) | 15 (w₀,w₂,w₄-w₁₄) | Binary removes w₁,w₃,w₁₅,w₁₆ |
| Weight optimization | Dataset-fitted (RMSE) | Uncalibrated priors | Acknowledged limitation |
| Interval fuzz | Yes (randomized ±days) | No | Repertoire review is position-based |
| Learning steps | Yes (1m, 10m) | No explicit steps | Rapid re-review guard serves similar purpose |

### 9.2 ChessSRS vs Anki/SM-2

| Feature | SM-2 (Anki legacy) | ChessSRS | Notes |
|---------|-------------------|----------|-------|
| Ease factor | Mutable ease factor (2.5 default, min 1.3) | FSRS difficulty or ladder multiplier | FSRS avoids "ease hell" via mean reversion |
| Interval growth | `I·EF` | FSRS power-law or geometric ladder | Power law is more mathematically grounded |
| New card steps | 1m → 10m | None (immediate scheduling) | Rapid re-review guard handles this |
| Relearning | Lapse → 1m → 10m steps | Lapse → requeue for re-test same session | Simpler, works for chess where sessions are focused |

### 9.3 ChessSRS vs Chess-Specific SRS (Listudy, chessrs)

| Feature | Listudy | chessrs | ChessSRS | Notes |
|---------|---------|---------|----------|-------|
| Scheduler | Custom | Geometric ladder | FSRS + 2 ladders | Most options |
| Graph effects | None | None | Lapse contagion, exposure credit, confusion coupling | Unique |
| Transposition handling | None | None | Canonical key sharing + review-time acceptance | Unique, well-designed |
| Binary grading | Yes | Yes | Yes | All chess-specific SRS use binary |
| Line-walking | Yes (auto-play to due position) | Yes | Yes + due-aware branch selection | Most sophisticated |

---

## 10. Summary of Findings

### Critical: None

### High Priority

None — the FSRS math is correct, the review engine is well-designed, and
invariants are properly enforced.

### Medium Priority

| ID | Finding | Description |
|----|---------|-------------|
| SRS-04 | FSRS repCount on lapse | FSRS doesn't reset repetitionCount on lapse (tracked in Q9) |
| POS-03 | Castling in canonical key | UCI castling form inconsistency between grading and identity |
| EDGE-04 | copyWith nullable fields | Cannot clear nullable DateTime fields back to null |

### Low / Informational

| ID | Finding | Description |
|----|---------|-------------|
| SRS-01 | Lapse stability non-monotone | Documented, matches FSRS reference |
| SRS-02 | Triple retention clamp | Correct and necessary |
| SRS-03 | Rapid re-review guard | Good design decision |
| REV-01 | Transposition lookup latency | Mitigated by background indexing |
| REV-02 | Opponent vs user selection asymmetry | Intentional design |
| POS-01 | Sorted accepted moves | Correct convergence behavior |
| POS-02 | EP normalization | dartchess handles correctly |
| PGN-01 | RAV handling | Correct recursive implementation |
| PGN-02 | Tag value escaping | Properly handled |
| PGN-03 | Pre/post comment merge | Minor fidelity loss, acceptable |
| TRV-01 | Order within bucket structure | Correctly prevents fresh overtaking due |
| GAR-01 | Contagion scope | Correctly walks chapter subtree only |
| OPN-01 | Move-order dependent detection | Some transpositions may be misclassified |
| OPN-02 | ECO mapping gaps | Acceptable for family-level classification |
| EDGE-01 | Deep recursion | Unlikely in practice |
| EDGE-02 | Chess960 refusal | Correct per scope |
| EDGE-03 | Malformed FEN passthrough | Defensive and acceptable |

### Optimization Opportunities

| Area | Opportunity | Effort |
|------|-------------|--------|
| Canonical key castling | Normalize castling UCI before computing canonical key | Low |
| Weight calibration | Fit FSRS weights to actual user review data | Major research |
| ECO mapping | Extend to cover A00-A09, A45-A79, E10-E19 gaps | Low |
| Move detection transpositions | Use FEN-based detection as primary (instead of move-order) | Medium |
| Deep recursion guard | Add iterative traversal or depth limit for extreme PGNs | Low |

---

## 11. Overall Assessment

The ChessSRS SRS and domain logic is **well-engineered** and **mathematically
sound**. The FSRS implementation faithfully reproduces the FSRS-4.5 binary
adaptation with appropriate chess-specific modifications. The graph-aware
coordinator adds genuinely novel value (lapse contagion, exposure credit,
confusion coupling) that no other chess SRS implements. The review session's
queue management, transposition handling, and fresh/due separation are
sophisticated and correctly implement the SPEC invariants.

The main areas for future improvement are weight calibration (empirical rather
than priors) and minor FEN/castling normalization consistency in canonical keys.
