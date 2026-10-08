# Technical Architecture

> **Foundation reset**: this application is built on a fork of
> [lichess-org/mobile](https://github.com/lichess-org/mobile) (GPL-3.0).
> The previous standalone Flutter implementation is archived at git tag
> `legacy/pre-reset`. It is reference material only — the product and domain
> knowledge lives in the Markdown specifications, not in the old code.

## 1. What this application is

**A local-first chess repertoire + spaced-repetition trainer** built on the
Lichess Mobile application foundation. It is *not* "Lichess with modifications":
Lichess Mobile provides the technical/UI foundation (board, theme, navigation,
state management, persistence patterns); our product provides the domain
(repertoire, review, SRS).

```text
Lichess Mobile foundation (GPL-3.0 fork)
        |
        +-- application/product modules (Riverpod providers)
        |
        +-- OUR domain boundary (pure Dart: repertoire, review, SRS)
        |       |
        |       +-- Listudy-derived training semantics
        |       +-- chessrs-derived SRS/review semantics
        |
        +-- local persistence / import infrastructure (sqflite, dartchess PGN)
```

## 2. Layer boundaries

```text
┌────────────────────────────────────────────────────────────┐
│ Presentation — Lichess Mobile shell (Flutter + Riverpod)    │
│   Review scene (primary) · Repertoire selector · Import ·  │
│   Settings (Lichess settings framework)                    │
└──────────────────────────┬─────────────────────────────────┘
                           │ talks only to application providers
┌──────────────────────────▼─────────────────────────────────┐
│ Application — Riverpod providers/services orchestrating    │
│   use-cases (import study, start review, submit move)      │
└──────────────────────────┬─────────────────────────────────┘
                           │ repository interfaces only
┌──────────────────────────▼─────────────────────────────────┐
│ DOMAIN (ours) — pure Dart, no Flutter/chessground imports   │
│   Study · Chapter · repertoire tree · RepertoireDecision   │
│   ReviewSession engine · ReviewState · Scheduler contract  │
└──────────────────────────┬─────────────────────────────────┘
                           │ adapters only
┌──────────────────────────▼─────────────────────────────────┐
│ Infrastructure — Lichess-derived:                          │
│   dartchess (rules, FEN, SAN, PGN) · chessground widgets   │
│   sqflite local DB · settings/preferences · file import   │
│   (no network on any critical path)                        │
└────────────────────────────────────────────────────────────┘
```

### Boundary invariants

1. **Pure domain**: our domain code (`lib/src/domain/` or a dedicated package)
   contains pure Dart logic and entities. Zero imports of
   `package:flutter/...` widgets, chessground, or sqflite. Testable without a
   widget tree.
2. **One chess representation**: `dartchess` is *the* chess rules engine.
   Do not introduce a second chess library or reimplement move generation.
   Domain code may consume dartchess core types (`Position`, `Move`, `San`)
   through thin adapters; UI consumes chessground. Never create competing
   representations of moves/positions/games.
3. **Lichess UI is not our domain model**: Lichess `model/` classes for online
   features are presentation/application concerns of the foundation, not
   domain entities of our product. Our entities live in our domain module.
4. **Local-first critical path**: user move → legality (dartchess) → repertoire
   lookup → SRS update → board update runs entirely in memory, locally.
   Network access is never on this path.
5. **Isolated integrations**: Listudy-derived and chessrs-derived behavior
   live in isolated domain modules behind our contracts (see
   `docs/INTEGRATION_MAP.md`). No cross-cutting merges.
6. **Imported repertoires vs. online studies**: Repertoires imported into
   ChessSRS (from PGN or Lichess) are pure, local-first snapshots stored in
   SQLite. They have no live socket connection and never auto-sync with
   remote changes. Remote Lichess study browsing (`StudyScreen`/`StudyController`)
   operates strictly in-memory over WebSockets for live viewing; it never
   writes to the local database.

## 3. Component responsibilities

### Domain (ours)

- **`Study` / `Chapter`**: repertoire content containers (source PGN file →
  study; PGN game → chapter, honoring FEN headers).
- **Repertoire tree**: branching move tree of positions. Reuses the
  Lichess `Node`/`Branch` tree *pattern* where practical, but decision
  semantics are ours.
- **`RepertoireDecision`**: THE scheduled unit — a position (from the player's
  perspective) plus the expected repertoire move(s). Every branch the player
  must recall is a decision; opponent moves are not scheduled independently.
- **`ReviewState` / `ReviewEvent`**: SRS tracking — first/last review, next
  due, repetition count, lapses, stability — plus immutable review log.
- **`Scheduler`** (contract): interval computation. Replaceable
  (SimpleScheduler ladder → chessrs-style ease/scaling → FSRS later) without
  redesigning anything else.
- **`ReviewSession` engine**: due-decision selection, move validation against
  *repertoire* (not engine truth), auto-traversal of non-due material,
  opponent-reply auto-play, correct/incorrect feedback semantics.
- **`Clock`** abstraction: deterministic time in tests.

### Infrastructure (Lichess-derived)

- **dartchess**: legality, SAN/UCI, FEN, and PGN parsing (`PgnParser`) —
  used by the import pipeline; PGN is an *input format*, never the domain model.
- **chessground**: board rendering, drag & drop, animation — presentation only.
- **sqflite (`db/`)**: local persistence for studies, trees, decisions, review
  states, events. Incremental writes; full study tree never rewritten per move.
- **settings/preferences**: board theme, piece set, sound — Lichess framework.
- **import**: PGN file import (multi-game, RAV variations, comments, NAGs,
  starting FENs) with graceful, structured degradation — never silent corruption.

### Presentation (Lichess-derived)

- App shell, tab navigation (reduced to: **Review** primary, settings in More),
  theming (`styles/`), reusable `widgets/`.
- **Review scene**: board-dominant screen; the board is the product.
- **Review modes**:
  - `ReviewMode.srs`: standard spaced-repetition training updating review states and logging events.
  - `ReviewMode.practice`: non-destructive rehearsal (cram mode) allowing active board testing without altering SRS intervals.
- **Review scopes**:
  - `ReviewScope.all()`: all active studies in the review pool.
  - `ReviewScope.study(id)`: specific study.
  - `ReviewScope.opening(name)`: virtual cross-study opening hub.

## 4. Review state machine (preserved product semantics)

```text
                ┌───────────────┐
                │ Select Scope  │  (all active / one study / one opening)
                └───────┬───────┘
                        ▼
                ┌───────────────┐
                │ Due Decision? ├─── No ──► calm idle state (option: Explore / Practice)
                └───────┬───────┘
                        │ Yes
                        ▼
                ┌───────────────┐
                │ Show Position │  (board oriented; move comments strictly hidden)
                └───────┬───────┘
                        ▼
                  User plays move
                        │
          ┌─────────────┴─────────────┐
          ▼                           ▼
    [Repertoire move]           [Other move]
          │                           │
   • record success (if SRS)   • record lapse (if SRS)
   • reveal move comment       • reveal expected move & comment
   • auto-traverse non-due     • keep board interactive for reguess
   • opponent auto-reply       • re-queue failed item
          │                           │
          └─────────────┬─────────────┘
                        ▼
                Next Due Decision      (until nothing due)
```

Key semantics (from PRODUCT/QUALITY + reference projects):
- Any valid repertoire branch is accepted; the played branch is followed.
- Auto-traversal is **never permanent exclusion** — learned moves return when due.
- No session-complete screen; review is an ongoing utility.
- Move comments are withheld during recall to prevent spoilers, then displayed post-move.
- Wrong-move feedback leaves the board interactive so the user can immediately reguess.
- Practice mode traverses lines identically to SRS mode but performs zero database writes.

## 5. Identity & determinism

- Entities use stable unique IDs (sync-ready).
- Position identity = normalized 4-field FEN (placement, side to move,
  castling, en-passant) — the "clean FEN" concept.
- All time-dependent logic takes an abstract `Clock` for deterministic tests.

## 6. Licensing constraints (binding)

- The whole application remains **GPL-3.0** as a fork of Lichess Mobile.
  Preserve `LICENSE`, `COPYING.md`, and copyright notices verbatim when
  trimming code.
- chessrs (GPL-3.0): adaptation permitted with attribution; default is
  reimplementation.
- listudy (AGPL-3.0): **no code copying**; behavioral reference only.
- See `docs/INTEGRATION_MAP.md` for the extraction rules.

## 7. Related documents

- `PRODUCT.md` — product definition (authoritative)
- `MVP.md` — current scope
- `QUALITY.md` — invariants
- `TEST_STRATEGY.md` — how invariants are proven
- `CUT_PROPOSALS.md` — Lichess foundation trim map & status
- `docs/INTEGRATION_MAP.md` — Listudy/chessrs extraction plan
- `docs/decisions.md` — durable decision log
- `Chess_Repertoire_SRS_Product_Blueprint.md` — deep product philosophy (consult on demand)
