# Performance Contract

> **Authoritative Specification:** See the repo root [QUALITY.md §4](../QUALITY.md#4-performance-invariants),
> [SPEC.md §E](../SPEC.md#e-performance-budgets-t2), and [TEST_STRATEGY.md §3](../TEST_STRATEGY.md#3-performance-evidence-and-limits).
> For active profiling measurements and findings, see [performance-handoff.md](performance-handoff.md).
> Per [AGENTS.md §1](../AGENTS.md#1-authority-and-conflicts), this file is an early initial brief preserved
> for historical context only.

## Primary requirement

Review must feel instantaneous. Treat latency as a product correctness constraint, not cosmetic polish.

## Critical path

```text
input
 -> local move validation
 -> local repertoire lookup
 -> board state update
 -> feedback
 -> local review-state update
 -> next position
```

No network dependency is allowed in this path.

## Perceived zero-lag

Optimize for the user's perception of immediate response, not only benchmark numbers.

Do not wait for:

- cloud persistence
- analytics upload
- Lichess
- engine analysis
- remote configuration

before updating the board.

## Precomputation

It is acceptable to precompute/cache:

- normalized positions
- legal/expected move representations
- branch transitions
- due-item lists
- study indices

Precomputation is preferred over repeated expensive work during Review.

## Chess calculations

Use optimized/local chess logic. Avoid spawning heavyweight work for routine legal move validation if a lightweight local library can perform it.

## Engine analysis

Engine computation belongs outside the Review path. Import-time analysis may run asynchronously and persist results.

## Persistence

Local writes should be small and predictable. Avoid rewriting an entire study after every move.

Persist review changes incrementally.

## UI

Avoid unnecessary rebuilds of the entire application tree when one board state changes.

Keep board rendering and review state updates localized.

## Network

Network is optional for MVP. Future network operations must be asynchronous and failure-tolerant.

A sync failure must not prevent continued local Review.

## Performance testing

Test on real mobile hardware as well as desktop/web. Benchmark the interaction path with a realistic study containing many chapters and branches.

The performance target is qualitative: the user should be able to move as quickly as they think without perceivable application hesitation.
