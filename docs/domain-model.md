# Domain Model

> **Authoritative Specification:** See the repo root [ARCHITECTURE.md §§3–7](../ARCHITECTURE.md#3-components-and-entry-points)
> and [SPEC.md](../SPEC.md).
> Per [AGENTS.md §1](../AGENTS.md#1-authority-and-conflicts), `ARCHITECTURE.md` and `SPEC.md` own the
> live domain entities, canonical identity (`canonicalKeyForPosition`), and persistence schema; this file
> is an early pre-implementation sketch preserved for historical context only.

## Core entities

### Study

A user-owned collection imported from one source. Contains one or more Chapters.

Suggested fields:

- id
- title
- source metadata
- created/updated timestamps
- chapters

### Chapter

A logical unit from the source PGN, commonly a game or named study chapter.

Suggested fields:

- id
- studyId
- title
- source order
- root position/node
- metadata

### PositionNode

A node in the repertoire tree representing a chess position and its move relationships.

Suggested concepts:

- id
- position key / FEN-equivalent state
- parent node
- incoming move
- child nodes
- source chapter references
- annotations/comments if preserved

A tree node should not be assumed to be a review item.

### RepertoireDecision

A decision the user may be asked to recall.

Conceptually:

```text
position + user-side expected repertoire move(s) + review identity
```

Multiple study branches may refer to the same chess position. Do not merge them automatically unless the product explicitly defines compatible repertoire semantics.

### ReviewState

Current SRS state for one review item.

Must support at least:

- first review
- last review
- next due
- repetitions / recall history summary
- difficulty/stability data needed by scheduler

### ReviewEvent

Immutable-ish historical record of a review outcome. Keep enough information to reconstruct/debug scheduling behaviour.

### Opening

A future cross-study classification/grouping concept. It should be orthogonal to Study and Chapter.

## Relationships

```text
Study
  -> many Chapters
Chapter
  -> root PositionNode
PositionNode
  -> child PositionNodes
PositionNode
  -> zero or more RepertoireDecisions
RepertoireDecision
  -> one ReviewState
ReviewState
  -> many ReviewEvents
```

## Important distinction

A PGN move tree is content.

A RepertoireDecision is a learning unit.

A ReviewState is scheduling data.

Keep these concepts separate.

## Position identity

A position identity must be deterministic and must account for all chess state relevant to legal moves and repetition semantics. FEN is a useful interchange representation; an internal normalized key may be better for persistence.

Do not identify a position only by its piece placement if side-to-move, castling rights, or en-passant state can affect legal moves.

## Repertoire branches

A position may have multiple valid repertoire continuations because the PGN contains branches. Review should know which move(s) are accepted for the active study/scope.

Do not infer that every legal chess move is a repertoire answer.

## Future sync identity

Entities that may sync across devices need stable IDs generated independently of the local database implementation. Do not rely on auto-increment database IDs as cross-device identity.
