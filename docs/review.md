# Review Engine and SRS

## Purpose

Turn repertoire content into an immediate active-recall loop.

The engine must answer:

1. What should be shown next?
2. Which repertoire move(s) are expected?
3. Is the submitted move accepted?
4. What happens next?
5. How does the result update SRS?

## Review loop

```text
select scope
 -> select due/reviewable decision
 -> show position
 -> user plays move
 -> local legality + repertoire check
 -> immediate feedback
 -> update review state
 -> traverse known continuation
 -> next due decision
```

## Correctness

A move is correct when it matches an accepted repertoire continuation for the active Review scope,
or when it reaches a position that exists elsewhere in the active scope's tree (transposed
acceptance — see Transpositions below).

Do not use engine evaluation to decide Review correctness in MVP.

Opponent moves are content. They are not required to be engine-best.

## Automatic traversal

If a decision is currently not due, the engine may traverse it automatically for either side as appropriate.

Automatic traversal means:

`not currently tested`

not:

`never test again`

A previously auto-played decision must become testable again when its SRS state becomes due, even after a very long interval.

## Opponent Variation Selection (Due-Aware & Anti-Repetition)

In a chess repertoire, the opponent frequently has multiple branching responses at a given position.

### The Problem with Static Selection (`children.first`)
Consider a repertoire for White where after **`1. e4`**, Black has three branches in the study tree:
- Branch A: **`1... c5`** (Sicilian Defense)
- Branch B: **`1... e5`** (Open Game)
- Branch C: **`1... e6`** (French Defense)

If the review engine naively selects `activeNode.children.first`:
- The opponent will **always** play `1... c5`.
- The user will never face `1... e5` or `1... e6` during the auto-traversal loop.
- Even if the user has 5 decisions due today in the French Defense (`1... e6`), Black would still stubbornly play the Sicilian, starving the due French variations of practice.

### The Due-Aware Algorithm
When the opponent must choose an auto-reply among multiple child nodes:

1. **Subtree Due Detection**: The engine calculates how many due decisions exist in the subtree of each candidate opponent branch.
2. **Prioritize Due Branches**:
   - If one or more branches have due material, branches with 0 due material are filtered out.
   - If exactly one branch has due material (e.g., only `1... e6` has reviews due), the opponent plays that branch to guide the user to the due cards.
   - If multiple branches have due material (e.g., both `1... c5` and `1... e6` have reviews due), the engine selects between them with weighted randomness proportional to due density, ensuring anti-repetition across sessions.
3. **Practice / Cram Fallback**:
   - In `ReviewMode.practice` (where all cards are drillable regardless of due date) or if no branch has due material, the engine selects among all candidate branches with anti-repetition so all variations get practiced evenly.

## Due selection and presentation order

Default scope: all studies.

The due *set* never depends on presentation order: urgency filtering and the
daily quota cut (most overdue first) always apply first. Only consecutive
presentation order is switchable (`Review order` setting, default By line):

- **Due date**: most overdue first, wherever the positions fall. Same cards,
  scattershot order across unrelated lines.
- **By line**: the same urgency-selected set presented walking study, then
  chapter source order, then tree order. Ties keep due-date order, so equally
  placed cards stay most-overdue-first. Practice mode is unaffected (it already
  walks tree order with no due filtering).

Scheduling math never sees presentation order.

## Transpositions: shared positions across lines

One position reached by two move orders (two chapters, or two branches) is
the same drill, and the app treats it as one in three places:

1. **Shared memory.** The same position-plus-move shares a single scheduling
   memory across every line that contains it. Learn it once and all lines
   know it; it is never drilled twice, and multi-study queues deduplicate it.
2. **Tolerant grading (INV-065).** A legal move that matches no expected
   continuation here is still graded correct when the position it reaches
   exists in the active scope's tree; review jumps to the transposed line and
   continues. Targets outside the scope, and illegal moves, stay incorrect
   exactly as before. The drilled decision is graded; only the continuation
   moves. The `Accept transposed moves` setting (Review & SRS, default on)
   turns this off, restoring strict expected-line grading.
3. **Presentation order.** By-line order walks each line in tree order, so a
   transposed position's lines surface near each other instead of scattered
   by due date.

Deliberately not built: end-of-line continuation. When a short line ends at
a position where a longer in-scope line passes through and continues, the
session does NOT flow into the continuation today — it advances to the next
due decision per the presentation order above. Flowing through shared
positions at line ends (only into due continuations, never adding cards) is
a coherent future option, currently on hold pending owner conviction that it
is a good idea.

## Multiple repertoire answers

If a node contains multiple accepted repertoire branches, Review may accept any branch marked as active for the current scope.

The system must know which branch the user entered so subsequent traversal follows the corresponding continuation.

## Failure behaviour

On an incorrect move:

- respond immediately
- reveal or demonstrate the expected move according to the visual design
- record a failed recall
- continue the line without requiring modal dismissal

Exact feedback animation belongs in `docs/design.md`.

## SRS abstraction

Use a replaceable scheduler contract conceptually equivalent to:

```text
schedule(previousState, reviewResult, timestamp) -> newState
```

Do not embed scheduling formulas inside UI code or database queries.

## MVP scheduler

A simple scheduler is acceptable initially. It must support intervals long enough for items to disappear from daily review and later return.

The implementation should not bake in a maximum interval that prevents long-term return.

## Future scheduler

A more sophisticated algorithm such as FSRS may be introduced later. Migration must be possible without changing the Review UI or repertoire tree model.

## No session completion

Review has no mandatory session boundary. Users can stop at any time.

## Reference behavior (chessrs + Listudy)

Proven behaviors translated into our contracts (see `docs/INTEGRATION_MAP.md`
for extraction rules and licensing):

- **chessrs practice queue**: prefetch a queue of due items; refill when one
  remains; wrong answer → display the correct move on the board, brief pause,
  reset; per-item board orientation from the repertoire side.
- **Listudy training loop**: a correct user move is followed by an
  auto-played opponent reply (weighted-random with anti-repetition); a wrong
  move resets training for *all sibling replies*, not just the played one.
- **Listudy key moves**: fully-learned prefix moves (training value 5) are
  auto-played at line start — our equivalent is auto-traversal of non-due
  decisions.

## Review state durability

After a move result, persist the state locally before the item can be lost due to app closure where practical. Do not block the visible move interaction on network sync.

## ChessFSRS Memory Kernel (Binary DSR Model)

ChessSRS uses a domain-adapted FSRS-5 (Difficulty-Stability-Retrievability) power-law forgetting curve for move scheduling:

$$R(t, S) = \left(1 + F \cdot \frac{t}{S}\right)^C, \qquad C = -0.5, \quad F \approx 0.2345$$

### Pure Binary Grading (Decision D015)

Unlike generic flashcards where response speed approximates confidence, chess is a domain of deliberate calculation, candidate move evaluation, and tactical verification:
- Thinking for 15–20 seconds to double-check candidate moves before playing the prepared line is disciplined, tournament-ready chess.
- Penalizing calculation latency creates timer panic and trains destructive reflexive blitzing habits.
- Therefore, ChessSRS strictly uses **Pure Binary FSRS**:
  - `Rating.good`: First committed move on the board is correct, regardless of think time. Interval advances using target retention ($R_{\text{target}}$).
  - `Rating.again`: Incorrect move, hint used, or a corrected false start. Lapse recorded; stability regresses.
- Move latency is preserved purely as optional telemetry (`latencyEmaMs`), firewalled from interval calculations.

## Graph-Aware Memory Propagation (`GraphAwareReviewCoordinator`)

While the FSRS kernel manages single-node decay and stability updates, chess decisions exist in a structured graph of forced move orders, branching variations, and shared transpositions. `GraphAwareReviewCoordinator` wraps the scheduler with domain-specific graph effects:

1. **Lapse Contagion (§B.1)**:
   - When an error occurs at a decision point, child decisions in that line are not completely reset (avoiding demotivating full-subtree amnesia from a single misclick).
   - Instead, exponentially decaying stability reduction is applied to direct descendants:
     $$S_{\text{child}}' = S_{\text{child}} \times (1 - \lambda_0 \cdot e^{-\text{depth}/\tau}), \quad \lambda_0 = 0.18, \, \tau = 1.5$$
   - Descendant difficulty is nudged ($\Delta D = \beta \cdot \text{decay}, \beta = 0.6$) and due dates are pulled forward proportionally.
   - Child repetition streaks and lapse counters remain untouched.

2. **Auto-Traversal Exposure Credit (§B.2)**:
   - When non-due (already learned) decisions are auto-traversed during review, seeing the move played provides passive recall reinforcement.
   - The decision receives a bounded micro-stability bump:
     $$S' = S \times (1 + \varepsilon), \quad \varepsilon = 0.08$$
   - Extended due date: $\text{nextDueAt}' = \text{nextDueAt} + \text{remaining} \times \varepsilon$.
   - Throttled to once per calendar day to prevent farming, and strictly refused if the item is already due.

3. **Confusable Sibling Coupling (§B.4)**:
   - When a user plays an alternative legal continuation matching a sibling decision at the same position, the coordinator detects candidate interference.
   - Sibling decision difficulty is coupled:
     $$D_{\text{sibling}}' = \operatorname{clip}(D_{\text{sibling}} + \kappa, 1.0, 10.0), \quad \kappa = 0.35$$
