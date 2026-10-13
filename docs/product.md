# Product Scope

> **Authoritative Specification:** See the repo root [PRODUCT.md](../PRODUCT.md).
> Per `AGENTS.md` §1 (Authority Hierarchy), root `PRODUCT.md` is the authoritative product document;
> this file is an early initial brief preserved for historical context.

## Product

A minimal, local-first chess repertoire trainer for openings and middlegame lines. Users import their own PGNs and repeatedly recall repertoire decisions using spaced repetition.

Product sentence:

> Import what you study. Recall it actively. Review it when due.

## Core experience

The app is fundamentally one experience: **Review**.

Default flow:

`open app -> Review`

If there are zero studies:

`open app -> Import PGN`

The user may temporarily constrain Review using lightweight selectors, especially:

- a specific study
- an opening across multiple studies

These are filters on Review, not separate product modes.

## MVP

Must support:

- PGN file import
- multiple chapters/games in one import
- PGN variations, including nested variations where parser support permits
- study/chapter identity
- repertoire tree / position graph
- active move recall on a chessboard
- immediate local correctness checking
- SRS state persistence
- automatic traversal of currently learned material
- return of previously learned material when it becomes due
- mobile and web from one Flutter codebase
- offline review after import

## Correctness model

The expected answer is the user's repertoire move, not the engine's best move.

Opponent mistakes are allowed and are part of the repertoire. A line may intentionally teach a punishment for an inaccurate opponent move.

MVP does not require engine evaluation during review.

## Future import warning

A future one-time import analysis may inspect moves belonging to the user's side of the repertoire and flag severe evaluation collapses, e.g. a line that turns a winning advantage into a losing position.

Rules:

- analysis is advisory only
- import remains allowed
- do not warn merely because an opponent move is inaccurate
- analysis occurs outside the latency-sensitive Review path

## Review selection

Default: all due material across all studies.

Optional study filter: due material from one study.

Future/early feature: opening filter, e.g. review all Sicilian material across multiple studies.

Do not build a large study-management workflow around these filters.

## No mandatory session boundary

There is no required end-of-session page. Review continues until the user stops.

If no items are due, show a minimal idle state.

## Explicit non-goals for MVP

- tactics training
- multiplayer
- social features
- leaderboards / XP / badges
- engine as review judge
- AI explanations
- Lichess OAuth/import
- cloud account or sync
- full study editor
- advanced analytics
- community study discovery
- opening database product

## Product language

Prefer:

- Review
- Study
- Chapter
- Opening
- Repertoire
- Due
- Remembered / Not remembered

Avoid exposing SRS terminology unless needed. SRS is implementation machinery, not the user's mental model.
