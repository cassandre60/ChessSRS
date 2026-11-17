# Roadmap and Scope Boundaries

> **Authoritative Specification:** See the repo root [MVP.md](../MVP.md) and
> [IMPLEMENTATION_PLAN.md](../IMPLEMENTATION_PLAN.md).
> Per [AGENTS.md §1](../AGENTS.md#1-authority-and-conflicts), `MVP.md` owns current included/deferred
> beta scope and `IMPLEMENTATION_PLAN.md` owns delivery status and evidence; this file is an early
> Phase 1–4 outline preserved for historical context only.

## Phase 1 — MVP

- Flutter mobile + web
- local-first storage
- PGN import
- multiple chapters
- variations
- repertoire tree
- Review
- active recall
- automatic traversal of non-due material
- SRS persistence
- minimal study selection

## Phase 2 — Refinement

Potential candidates, not commitments:

- stronger PGN compatibility
- improved SRS
- opening cross-study selection
- import-time repertoire warnings
- small UX/performance refinements

Do not add Phase 2 work before the core Review loop is reliable.

## Phase 3 — Lichess

- Lichess authentication
- browse/select user's studies
- import studies directly
- optionally synchronize selected studies

The imported representation must remain identical to PGN-derived studies.

## Phase 4 — Cross-device sync

Synchronize:

- studies
- study metadata
- repertoire content as needed
- SRS state
- review history if needed

Local state remains immediately usable while sync occurs asynchronously.

## Possible later features

These are intentionally undecided:

- deeper engine-assisted import analysis
- richer opening classification
- study editing
- advanced review controls
- notifications
- advanced analytics
- engine-assisted explanations

Do not assume these belong in the product merely because they are technically possible.

## Rejected/avoid unless explicitly reconsidered

- tactics-first product direction
- social feed
- XP economy
- leaderboards
- mandatory sessions
- engine as the definition of Review correctness
- network-dependent Review
