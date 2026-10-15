# MVP Scope & Specifications

## 1. MVP Goal

Deliver a functional, local-first Flutter application (built on the Lichess
Mobile foundation) that executes the complete loop:

**PGN Import → Normalized Repertoire Tree → Active Review Scene → Local SRS Persistence**.

---

## 2. Included Capabilities

| Capability | Description | Status |
|---|---|---|
| **Local PGN Import** | Multi-game, multi-chapter PGN import (via dartchess `PgnParser`) supporting recursive variations (RAVs), comments, NAGs, and starting FENs. | Phase 2 |
| **Repertoire Normalization** | Converts PGN trees into domain `Study` → `Chapter` → repertoire tree graphs with deterministic FEN keys. | Phase 2 |
| **Decision Point Derivation** | Derives `RepertoireDecision` units for positions requiring user recall (player's perspective). | Phase 2 |
| **Active Recall Review** | Lichess-quality interactive board scene where users input moves to answer due repertoire positions. | Phase 2 |
| **Move Validation** | Immediate local validation against expected repertoire continuation moves (any valid branch accepted). | Phase 2 |
| **Automatic Traversal** | Automated traversal through opponent replies and already-learned user moves until the next due decision (never a permanent exclusion). | Phase 2 |
| **Replaceable SRS Scheduler** | `Scheduler` contract + `SimpleScheduler` exponential interval ladder with lapse recovery and deterministic testing support. | Phase 2 |
| **Local Persistence** | sqflite-backed repository storing studies, decisions, review states, and review events. | Phase 2 |
| **Lichess-derived UX foundation** | Lichess Mobile theme, board (chessground/dartchess), navigation, settings. | Phase 1 |

## 3. Excluded Capabilities (unchanged)

```text
PRODUCT SCOPE
├── Local PGN Import               [MVP / Phase 2]
├── Recursive Variation Trees      [MVP / Phase 2]
├── Review-First Active Recall     [MVP / Phase 2]
├── Automatic Traversal            [MVP / Phase 2]
├── Replaceable SRS Engine         [MVP / Phase 2]
├── Local Persistence              [MVP / Phase 2]
├── Listudy training behaviors     [Phase 4 — isolated module]
├── chessrs scheduler behaviors    [Phase 5 — isolated module]
├── Advisory Engine Health Check   [later, isolated at import]
├── Cross-Study Opening Filter     [later]
├── Lichess study import/sync      [EXCLUDED for MVP]
├── Cloud sync / accounts / social [EXCLUDED]
└── Tactics / Social / Gamify      [EXCLUDED]
```

## 4. Acceptance Criteria (unchanged product requirements)

1. **Clean Import**: Importing a PGN containing multiple chapters and nested
   variations produces a fully intact hierarchy where no variation branch is
   discarded.
2. **Deterministic Correctness**: Playing a move that matches an active
   repertoire branch is accepted immediately; playing any other move (even
   legal chess moves) is marked incorrect.
3. **SRS Interval Progression**:
   - A position is due only after it has been presented. New items are
     **not** due; they are introduced gradually, after due work, and
     only then enter the SRS ladder (SPEC INV-068).
   - Successful recalls increase the interval (1 day → 2 days → 4 days → ...).
   - Failed recalls reset the repetition streak and schedule a
     short-interval retry.
4. **Zero-Lag Interaction**: Move legality and repertoire lookup happen
   synchronously in memory without blocking UI rendering.
5. **No Modal Interruptions**: Incorrect moves reveal the expected line and
   allow progression without requiring modal dismissals.
6. **Persistence Durability**: Review states and study structures survive
   application restarts.
7. **Runtime-Verified UX**: The review scene must look and feel like a
   coherent Lichess-derived mobile application (runtime validation, not just
   tests).

## 5. Known Limitations (MVP)

- Default player orientation heuristic is White unless specified in chapter
  metadata or custom FEN; per-chapter orientation from PGN metadata follows
  in refinement.
- Import sources are local PGN files only (Lichess import is an explicit
  future horizon, never a dependency).
