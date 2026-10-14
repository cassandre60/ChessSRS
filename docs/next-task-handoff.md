# Next Task Handoff — Session-Start & Review Path Performance

**Date:** 2026-10-14  
**Base:** `origin/main` @ `f9de28bfe`  
**Target:** Eliminate redundant database queries and object deserializations on the review screen critical path (`_loadAndPublish`, `getDueSummary`, and `startSession`).

---

## 1. Owner Mandate & Context

In `docs/open-questions.md` (Q1), the owner responded:
> *"it needs to be instant; everything in the app needs to be as fast as possible."*

Currently, opening the review screen or switching a scope on the owner's real database (~528 decisions, ~480 due) takes **37–39 ms**. 
While not a violation of `QUALITY.md §4.1` (which mandates <16 ms specifically for move validation and response time), session start and drawer scope transitions feel noticeably hesitant.

---

## 2. Profile Findings & The Redundant Work

Attribution measurements on the real library in `test/perf/due_summary_attribution_test.dart` and code audits revealed two major performance bottlenecks:

### Bottleneck A: Sequential Duplicate Database Fetching
In `lib/src/review/review_controller.dart`:
- `_loadAndPublish` (lines ~446–455):
  ```dart
  final summary = await _service.getDueSummary(...);
  final session = await _service.startSession(...);
  ```
- `deleteStudy` (lines ~773–778):
  ```dart
  final summary = await _service.getDueSummary(...);
  final newSession = await _service.startSession(...);
  ```

Both `getDueSummary` and `startSession` independently execute:
1. `repository.getAllDecisions()` (or `_getActiveDecisions` / `_getSideDecisions`)
2. `repository.getReviewStatesByIds(allQueryIds)`
3. `repository.getKnowledgeStatesByCanonicalIds(canonicalIds)`
4. Iteration converting `PositionKnowledgeState` to `ReviewState` (`toReviewState()`) and building the `reviewStates` map.

**They perform the exact same queries and Dart object mapping back-to-back.**
Passing the preloaded decisions and review states (or fetching once) cuts out an entire query and deserialization cycle.

### Bottleneck B: Heavy Domain Object Materialization in `getDueSummary`
`getDueSummary` materializes **772 full domain objects** (491 after merge) across `ReviewState` and `PositionKnowledgeState`:
- Each `ReviewState` parses ISO-8601 strings and populates 8 fields (including difficulty, stability, lapses, etc.).
- `getDueSummary` only actually reads:
  1. `isDueAt(now)` (i.e. `nextDueAt <= now`)
  2. `isLearned` / `repetitionCount > 0`
- `PERF-FIX-21` Option B already suggested projecting only `(id, nextDueAt, repetitionCount)` rather than deserializing full models for count aggregation.

---

## 3. Refuted Hypotheses (Do Not Waste Time On These)

Benchmarks on the real library (`docs/performance-handoff.md`) proved:
1. **The SQLite query execution is fast**: ~1.4 ms total across all SQL statements. Database indexes are clean; the delay is not database engine wait time.
2. **Date parsing is not the primary culprit**: `DateTime.parse` across all rows takes only ~1.9 ms.
3. **The `ReviewSession` constructor is not the bottleneck**: Takes only ~2 ms for the real library (~4 µs/decision). Chunking the constructor was measured and declined (`PERF-FIX-32`).

---

## 4. Benchmark Setup for Verification

Never use synthetic small fixtures to measure this; row-mapping overhead scales with library size.

```bash
# 1. Copy the real database and WAL/SHM sidecars
mkdir -p /tmp/perf
cp ~/.local/share/org.chesssrs.chess_srs/chess_srs.db* /tmp/perf/

# 2. Run the attribution benchmarks
export CHESS_SRS_PERF_DB=/tmp/perf/chess_srs.db
fvm flutter test test/perf/real_library_session_cost_test.dart
fvm flutter test test/perf/due_summary_attribution_test.dart
```

---

## 5. Implementation Strategy for Next Agent

1. **Contract-Preserving Deduplication in `ReviewService`**:
   - Allow `startSession` to accept an optional preloaded `ReviewStates` map and `decisions` list, OR provide a combined method `loadSessionAndSummary(...)` that fetches once and produces both.
   - Alternatively, keep `ReviewService` caching the active scope's decisions and review states during session startup.
2. **Safety & Invariants**:
   - Must preserve `INV-030` (scopes filter exactly).
   - Must preserve `INV-032` (stale generation session discard).
   - Must not break `test/review/review_controller_test.dart` or `test/review/review_service_test.dart`.
3. **Test & Gate Verification**:
   - Run `fvm flutter test test/review/review_controller_test.dart`
   - Run `fvm flutter test test/review/review_service_test.dart`
   - Run `fvm flutter analyze` on touched files.
   - Commit and run `./scripts/gates.sh t1`.
