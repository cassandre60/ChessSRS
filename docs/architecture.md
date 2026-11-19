# Architecture

> **Authoritative Specification:** See the repo root [ARCHITECTURE.md](../ARCHITECTURE.md).
> Per [AGENTS.md §1](../AGENTS.md#1-authority-and-conflicts), root `ARCHITECTURE.md` is the authoritative
> home for module boundaries, data flow, persistence arrangement, and licensing; this file is an early
> pre-reset sketch preserved for historical context only.

## Goal

Build a local-first Flutter application whose critical Review path is fully local, deterministic, and fast. Keep the domain independent from UI, persistence, PGN syntax, and future network providers.

## Logical layers

```text
Flutter UI
  -> application/review orchestration
      -> domain
          -> chess
          -> repertoire tree
          -> SRS
      -> repositories/interfaces
          -> local persistence
          -> importers
          -> optional future sync
```

A practical repository shape can evolve, but responsibilities should remain recognizable:

```text
lib/
  core/
  domain/
  application/
  chess/
  import/
  persistence/
  ui/
```

Do not create empty abstractions solely for theoretical purity. Boundaries should protect real change points.

## Domain layer

Owns:

- Study
- Chapter
- Position/node relationships
- Repertoire decisions
- Review state/history
- scheduler interface
- review sequencing rules
- opening classification value if introduced

Must not depend on Flutter widgets or database APIs.

## Chess layer

Owns:

- legal move validation
- position representation
- move application
- SAN/UCI/FEN conversions as required
- PGN semantic processing if parser implementation lives here

Board rendering is separate from chess correctness.

## Import layer

Input adapters convert external sources into the internal Study model.

MVP source:

`PGN file`

Future source:

`Lichess study`

Do not make Lichess types part of the core Study domain.

## Persistence layer

Local database stores studies, tree data, review state/history, and import metadata.

Use repository interfaces so the domain does not know the database implementation.

Local writes should complete synchronously enough for the next Review decision; cloud sync later must be asynchronous.

## Application layer

Coordinates user intent:

- choose Review scope
- fetch due items
- create/advance a review sequence
- validate a submitted move
- update SRS state
- traverse known positions
- persist review events

UI should call application services rather than directly manipulating database rows.

## Future synchronization

Design for:

```text
local change -> immediate local state -> async sync queue -> cloud
```

Never make sync a prerequisite for move acceptance or board rendering.

Cloud should eventually synchronize both:

- studies/PGN-derived data
- SRS state/history

## Future engine analysis

Engine analysis is an import-time service, not a Review dependency.

```text
PGN import -> normalize -> optional analysis -> warnings -> persist study
```

Do not run an engine search in the ordinary move-validation loop unless a future product decision explicitly requires it.

## Dependencies

Keep package-specific code behind narrow adapters when practical. In particular, chess rules/PGN and database packages should not leak package types through the entire domain.

Choose packages based on web + mobile support, correctness, maintenance, and latency rather than popularity alone.

## Change rule

If a change alters a boundary, persistence model, review contract, or future sync assumption, update `docs/decisions.md`.
