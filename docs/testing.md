# Testing and Quality Gates

> **Authoritative Specification:** See the repo root [TEST_STRATEGY.md](../TEST_STRATEGY.md),
> [GATES.md](../GATES.md), and [SPEC.md](../SPEC.md).
> Per [AGENTS.md §1](../AGENTS.md#1-authority-and-conflicts), those root documents own verification
> budgets, gate definitions, and per-invariant oracles; this file is an early initial brief preserved
> for historical context only.

## Goal

Prevent chess correctness bugs, import corruption, SRS regressions, and latency regressions.

## Unit tests

Required for domain-critical logic:

- legal move application
- position identity
- PGN normalization
- variation tree construction
- multiple chapter import
- repertoire-answer matching
- branch selection
- due-item selection
- automatic traversal
- SRS state transitions

## Import fixtures

Maintain real-world PGN fixtures covering:

- one chapter
- many chapters
- nested variations
- comments/NAGs
- FEN starts
- promotions
- castling
- en-passant
- malformed input
- large study

## Review tests

At minimum verify:

- correct repertoire move is accepted
- unrelated legal move is rejected
- opponent inaccuracies remain valid content
- multiple accepted branches work
- learned item can be auto-traversed
- auto-traversed item becomes a question again when due
- review state survives restart

## SRS tests

Tests must use fixed timestamps / clock abstraction. Avoid tests that depend on wall-clock time.

Verify that intervals can become long and that due items return after long periods.

## UI/integration tests

Cover:

- first launch with zero studies
- import -> Review transition
- study selector changes Review scope
- board interaction on mobile dimensions
- keyboard interaction on web where supported
- no required end-of-session flow

## Performance tests

Use representative large studies and measure the critical path:

`input -> move accepted/rejected -> next state`

No network should be involved.

## Regression rule

A bug in chess rules, PGN parsing, branch semantics, or SRS scheduling requires a regression test before fixing the implementation where practical.

## Definition of done

For every feature:

1. relevant unit/integration tests exist;
2. critical path remains local;
3. behaviour matches product scope;
4. docs are updated if a contract changed.
