# Product Definition

## 1. Vision & Core Value

**Chess Repertoire SRS** is a focused, local-first chess learning application for **memorizing and retaining opening and middlegame repertoires through active spaced repetition**.

The core premise:
> **Show the player a position from their own repertoire and ask them to play what they have learned.**

The application is not a general tactics trainer, an engine analysis cockpit, or a social network. Its purpose is to turn a player's curated repertoire material into **instant, reliable, retrievable memory**.

---

## 2. Target Users

- **Tournament and competitive chess players** preparing structured opening repertoires.
- **Club players and students** who study PGN files or coach-provided material and need to remember lines under game conditions.
- **Players tired of feature bloat** who want a minimal, zero-latency review utility that opens directly into active practice.

---

## 3. Core User Journeys

### Journey 1: Daily Repertoire Review (Default)
1. User opens the application.
2. The app immediately presents the chessboard on the first due position across all active imported studies.
3. User recalls and makes their prepared move on the board. (Crucial: move comments and annotations are strictly hidden during recall to prevent move spoilers).
4. If correct: subtle positive feedback, automatic traversal through already-learned opponent/user continuations, and stopping at the next due decision. Any explanatory move comment is revealed post-move.
5. If incorrect: non-blocking feedback indicating the expected repertoire continuation with an on-board arrow, recording a lapse, and keeping the board interactive so the user can immediately reguess and play the correct move.
6. User reviews as long as they wish; when all items are up to date, a calm idle state is displayed with options to explore moves or start pre-match rehearsal.

### Journey 2: First Launch & PGN Import
1. User opens the app for the very first time (zero studies exist).
2. The app presents a clean, focused import interface.
3. User supplies a PGN file containing one or many games/chapters with variations, comments, and annotations.
4. The system validates chess legality, preserves full variation trees, normalizes chapters, and derives scheduled decision points.
5. User is immediately transitioned into Review of the newly imported material (active scope automatically switches to the new study).

### Journey 3: Constrained Review Scope & Opening Hubs
1. User is preparing for a specific opening (e.g. against 1.e4) and wants to focus on their Sicilian repertoire.
2. User opens the lightweight study/opening filter drawer.
3. User selects a target study or an Opening Hub (e.g. "Sicilian Defense" which aggregates lines across multiple studies automatically classified by standard opening name/ECO/FEN).
4. The Review scene updates its active pool to only test due positions matching that filter.

### Journey 4: Pre-Match Rehearsal / Cram Mode (Custom Review)
1. User has an upcoming tournament or match in 20 minutes and wants to rehearse lines in a specific repertoire.
2. The system indicates 0 positions are due for review.
3. User enters Rehearsal Mode for the chosen repertoire.
4. The app actively tests the user on the board through the lines, giving feedback and reguess opportunities.
5. Invariant: Rehearsal Mode is non-destructive — it does not update SRS intervals, increment repetitions, or record lapses in the SRS database.

### Journey 5: Active Review Pool Focus (Deck Suspension)
1. User maintains multiple repertoires over time (e.g. alternate defenses against 1.e4 or experimental openings).
2. User toggles specific studies active or inactive in their daily review pool.
3. The "All Studies" review queue and due count only pull from active repertoires, preventing review fatigue from sidelines not currently in play.
4. Inactive studies remain fully accessible for individual review, explore mode, or cram mode at any time.

---

## 4. Functional Requirements

1. **PGN Pipeline**:
   - Accept standard and non-standard PGNs with single or multiple games/chapters.
   - Preserve recursive annotation variations (RAVs) as first-class branching trees.
   - Support arbitrary starting FEN positions.
   - Extract move comments and NAGs without corrupting tree structure.

2. **Repertoire Training Model**:
   - Training evaluates whether the player remembered **their repertoire**, not whether the move is engine-optimal.
   - Opponent mistakes and prepared punishments are first-class repertoire content.
   - Player decision points are derived for the user's perspective.
   - Move comments and annotations are strictly hidden during recall to prevent giving away the move, and revealed post-guess or during explore mode.
   - Mistakes allow immediate reguess on the board without modal locking.

3. **Spaced Repetition System (SRS) & Review Modes**:
   - Every repertoire decision maintains its own SRS state (repetition count, lapse count, stability/interval, next due timestamp).
   - Non-due (already learned) positions are automatically traversed during review so the user is only tested on what is currently due.
   - Previously learned moves return as active testable questions once their interval elapses.
   - Scheduler algorithm is replaceable behind an abstract contract.
   - Dual review modes: Standard SRS mode (updates intervals and logs recall events) and Pre-Match Rehearsal mode (trains positions on the board without altering SRS intervals or history).
   - Studies can be toggled active or inactive in the daily review pool.

4. **Opening Hubs & Classification**:
   - Openings are automatically classified from standard PGN headers (Event, ECO, Opening) or position FEN.
   - Openings form lightweight virtual review scopes aggregating lines across multiple studies without data duplication.

4. **Offline & Performance**:
   - The entire review and move-validation loop is 100% local and requires zero network access.
   - Perceived interaction latency must be effectively zero (<16ms on mobile and desktop).

---

## 5. Visual Identity

ChessSRS ships its own visual identity ("Diagram"), independent of Lichess Mobile's look. The full
specification lives in `design/`:
`design/docs/01-identity.md` (principles and voice), `design/docs/02-tokens.md` (colour, type, motion),
`design/docs/03-components.md` (component specs), `design/docs/04-screens-and-flows.md` (screens and states).
The visual identity is intentionally decoupled from Lichess Mobile's theme — see decision D016.

Lichess Mobile remains the **technical** foundation only (board rendering via chessground, chess rules via
dartchess, the Riverpod/domain architecture). See `CUT_PROPOSALS.md` for what technical foundation is kept.

- **The Product is Review**: The chessboard is the primary and dominant interface element.
- **Quiet & Fast Feedback**: Move confirmation is immediate with subtle tactile/audio feedback cues; incorrect moves reveal the expected line without modals.
- **No Mandatory Session Boundary**: Review is an ongoing utility. Users can stop anytime without penalty.
- **Restrained Visual Aesthetic**: Subtle typography, generous negative space, high-contrast board pieces, no gamer aesthetics.

---

## 6. Non-Goals (Explicit Exclusions)

- No tactics puzzle generator or arbitrary position solver.
- No real-time chess engine judging review moves (engine evaluation does not dictate repertoire correctness).
- No multiplayer, matchmaking, or social leaderboards.
- No mandatory daily gamification streaks or XP badges.
- No cloud dependency for core move validation.

---

## 7. Future Horizons (Post-MVP)

- **Lichess Integration**: Authenticate and directly import/sync user's Lichess studies.
- **Full Local Backup & Restore**: Export all studies (PGN) plus all SRS data, and re-import it (see P-EXPORT-ALL). Local file/share only; no cloud dependency.
- **Cross-Device Async Sync**: Background synchronization of study content and SRS review history across mobile, web, and desktop.
- **Advisory Import Health Check**: Optional asynchronous one-time engine pass warning users of severe evaluation collapses in their own lines (advisory only, never blocking).
- **Cross-Study Opening Categorization**: Aggregate repertoire positions by opening family across separate study files.
