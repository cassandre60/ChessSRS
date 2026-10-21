# Quality & Engineering Constraints

Authority: engineering constraints not already specified by a numbered invariant.
`SPEC.md` owns exact behavioral invariants and their test links;
`ARCHITECTURE.md` owns module arrangement. See `docs/documentation-map.md`.

The section numbers below are retained for older references. A pointer here is
not a second definition: follow its normative home.

## 1. Architectural Invariants

1. **Layer independence**: presentation may consume domain value types but
   orchestrates use cases through application providers. It must not directly
   access database tables, persistence repositories or raw storage blobs.
   Domain purity and I/O restrictions: SPEC INV-040/042.
2. **Single chess representation**: dartchess is the sole rules engine and
   move/position representation; chessground renders it. Do not introduce a
   competing chess library or reimplement move generation.
3. **Local-first review**: no network call is permitted on move submission,
   grading, SRS update or board rendering. Pure computation is in memory;
   local incremental persistence is asynchronous and must meet the durability
   contract (SPEC INV-001/002). "Local" does not mean "no SQLite writes".
4. **Advisory engine isolation**: engine work is asynchronous and outside the
   review loop. An optional import-time assessment may warn but never veto or
   block an import. Repertoire grading: SPEC INV-020/065.

## 2. Domain & Chess Invariants

1. Repertoire correctness: SPEC INV-020, including the configurable
   transposition exception INV-065.
2. Variation preservation: SPEC INV-010.
3. Position identity and shared memory: SPEC INV-015/016/017/030;
   storage/key composition is described in ARCHITECTURE §5.
4. Long-term retrieval (no permanent exclusion): SPEC INV-022.

## 3. Reliability & Error Invariants

1. Malformed-input quarantine: SPEC INV-011/012.
2. Scheduling/review time comes through Clock: SPEC INV-024/041. This does
   not claim that entity-construction timestamps throughout the entire domain
   are already injected; review/scheduling paths are the guarded boundary.

## 4. Performance Invariants

1. **Move response time**: local legality validation and repertoire lookup must
   complete in **<16 ms**. SPEC INV-050 additionally describes a graded answer
   including persistence on its reference path. The current oracle measures
   a batch median, not every frame on every device (TEST_STRATEGY §3).
   This is not a session-start/import budget. The conflicting scope of these
   claims awaits a decision in `docs/open-questions.md` Q8; neither bound is
   relaxed by this documentation change.
2. Incremental state writes: SPEC INV-002.
