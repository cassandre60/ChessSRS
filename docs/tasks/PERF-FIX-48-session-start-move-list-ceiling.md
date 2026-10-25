# PERF-FIX-48 — Session-start move-list ceiling (the lazy-expectedMoves direction)

**Status: closed 2026-10-24 — refuted by measurement. Evidence in
`docs/performance-handoff.md` §11; the decision it leaves open is
open-questions Q15.**

## Premise (re-runnable)

The option-3 handoff proposed making `RepertoireDecision.expectedMoves` lazy,
on the premise that "the queue build never reads `expectedMoves`". Check the
premise against the tree before working on it:

```bash
git grep -n "expectedMoves" -- lib/src/domain/review/review_session.dart
```

The queue bucketing itself never reads it — but `_indexChapter`
(`review_session.dart:373`) iterates `d.expectedMoves` for every decision in
every indexed chapter to build `_canonicalByFenMove`, and `neededChapterIds`
(`review_session.dart:218`) is derived from the final trimmed queue, which at
the 2026-10-24 shape covers nearly the whole library. A lazy field would
relocate the parse from `getAllDecisions` into the constructor, not remove it.
It would also de-const `RepertoireDecision` (~150 const test fixtures).

## What would make this brief wrong (i.e. revive the direction)

- A constructor path that stops iterating decision move lists — the
  fen-key-on-rows or two-phase redesigns offered in open-questions Q15.
- A library shape where queued decisions concentrate in a few chapters, so
  most decisions' moves are never read at session start.

## Measurement

`test/perf/session_start_move_list_ceiling_test.dart` on the real DB copy
(31,182 decisions; median of 15 after 3 warmups, interleaved rotated rounds
agreeing):

| Measurement | Median |
|---|---|
| `getAllDecisions` (full mapping) | 145 ms |
| decision rows, no move decode | 93 ms |
| session build, real move lists | 552 ms |
| session build, empty move lists | 521 ms |

Move-content-dependent constructor work: **~30 ms**. Move decode inside
`getAllDecisions`: **~52 ms** — consumed by the constructor regardless. The
handoff's "the 162 ms" double-counted query and row-map construction.
Separately: 98.6% of rows carry `canonicalStateId`, so `_canonicalByFenMove`
is read only for pre-v10 legacy nodes; not building it on migrated libraries
is a semantic decision (Q15), not a laziness win.
