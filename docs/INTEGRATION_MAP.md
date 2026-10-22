# Integration Map — Listudy & chessrs Extraction Plan

Authority: reference-source provenance and extraction boundaries. The phase
labels below describe the original sequence; integrations have shipped (see
IMPLEMENTATION_PLAN Phases 4–6), and MVP owns what remains in scope.

The reset directive is explicit: do not merge repositories. Extract behavior
and proven solutions into **isolated modules** inside our domain boundary.

```text
Lichess Mobile (UI/app foundation)
        |
        +-- application/product modules
        |
        +-- OUR domain boundary (contracts below)
        |        |
        |        +-- Listudy-derived training semantics  (module: repertoire training)
        |        +-- chessrs-derived SRS semantics        (module: srs scheduling)
        |
        +-- local persistence/import infrastructure (sqflite, PGN via dartchess)
```

## Licensing pointer

ARCHITECTURE §6 owns the binding licensing rules. The source inventory below
explains provenance, not a second policy:

| Source | License | Rule |
|---|---|---|
| lichess-org/mobile | GPL-3.0 | We are a fork: entire app is GPL-3.0. Preserve LICENSE, COPYING.md, notices. |
| ZackMurry/chessrs | GPL-3.0 | GPL-compatible: direct code reuse *permitted* if desired; still prefer clean reimplementation in Dart. Attribute. |
| ArneVogel/listudy | **AGPL-3.0** | AGPL ≠ GPL interchangeable. Do **not** copy code. Study behavior, reimplement independently. |

Consequence: from chessrs, *small, attributed* code adaptation is legally
possible; from listudy, only behavioral inspiration. Default posture for both:
**reimplement against our contracts**, cite the source file in the doc comment.

## From Listudy (Phase 4) — behavioral extractions

Source: `assets/js/study.js`, `assets/js/modules/tree_utils.js`,
`modules/tree_from_pgn.js`, `study_controller.ex` (concept only).

| Concept | Source | Our module | Notes |
|---|---|---|---|
| Training loop: validate user move against tree children; wrong → undo board, mark error, retrain all sibling replies to 0 | `study.js handle_move` | review session engine | our RepertoireDecision updates instead of node values |
| Opponent reply auto-play with weighted-random + anti-repetition (`tree_size_weighted_random_move`, value bump) | `study.js ai_move` | review session engine | keeps review varied across sessions |
| Per-node training value 0–5; value 5 = fully trained; auto-skip fully trained prefix moves (key moves) | `tree_utils.js update_node_value`, `study.js start_training` | ReviewState/SRS design input | maps to "auto-traverse non-due material" |
| Chapters = PGN games; `FEN` header support; chapter selector | `study.js setup_chapter_select` | repertoire module | matches our Study→Chapter model |
| Trees cached client-side keyed by PGN hash (regenerate on change) | `study.js setup_trees` | import pipeline | hashing invalidation pattern for local DB |
| Move comments + PGN arrow/circle shapes (`csl`/`cal`) rendered on board | `study.js get_pgn_shapes` | repertoire UI (optional) | only where useful; secondary |
| Hint arrows gated by training value (new/2×/5×/always) | `study.js display_arrows` | review settings (optional) | post-beta |
| Progress per chapter (`tree_progress`) | `tree_utils.js` | review stats (minimal) | only if it serves Review UX |

Explicitly NOT taken: Elixir backend, users/favorites/comments socially,
tactics/books/blog SEO pages, achievements & combos, Stockfish web worker,
chessclicker.

## From chessrs (Phase 5) — behavioral extractions

Source: `backend/src/main/kotlin/com/zackmurry/chessrs/` (entity, service),
`frontend/src/pages/practice/` + `store/boardSlice.ts`.

| Concept | Source | Our module | Notes |
|---|---|---|---|
| Review item = position + move: `fenBefore`, `san`, `uci`, `isWhite` | `entity/Move.kt` | RepertoireDecision | confirms our decision-unit model |
| SRS interval ladder: `ease × scaling^numReviews` (minutes), user-tunable ease/scaling | `service/SpacedRepetitionService.kt` | second `Scheduler` impl | complements our SimpleScheduler ladder |
| Fields: `lastReviewed`, `numReviews`, `due`, `timeCreated` | `entity/Move.kt` | ReviewState | subset of our state (we add lapses/stability for FSRS-upgrade path) |
| Review queue prefetching: fetch N due items, refill when 1 remains | `PracticeMainPanel.tsx` | review session engine | avoids per-item latency in UI |
| Wrong answer → show correct move on the board, pause ~3s, reset; correct → advance | `PracticeMainPanel.tsx`, `boardSlice` | review feedback UX reference | reference behavior only; our immediate reguess/re-test contract is INV-021, not a mandatory 3s lock |
| Per-move board perspective (isWhite flips board) | `PracticeMainPanel.tsx` | review scene | board orientation from repertoire side |
| `cleanFen` normalized position identity | `Move.kt` | position keys | matches QUALITY.md position identity invariant |
| `opening` string on moves for grouping | `Move.kt`, `OpeningService.kt` | Opening cross-study dimension | Phase 4/5+ |

Explicitly NOT taken: Kotlin/Spring backend, GraphQL API, PostgreSQL/JDBC,
OAuth/Lichess auth, accounts, engine service.

## Integration sequence

1. **Phase 2 (slice)** uses OUR contracts only (already encode most chessrs
   queue/feedback behavior — the old ReviewEngine's semantics survive as spec).
2. **Phase 4 (Listudy)**: opponent auto-reply + variation-aware training inside
   the review engine; chapter/FEN handling verified against import tests.
3. **Phase 5 (chessrs)**: alternate scheduler impl + queue prefetch tuning,
   behind the `Scheduler` contract, selected in settings.

Each integration is one isolated module + tests; no cross-cutting rewrites.

Reference concepts such as sibling reset, single-move scheduling keys, hints
or progress presentation are not authorization to override SPEC or expand MVP.
Graph effects/identity follow the current scheduling architecture and SPEC.
