# Findings index (top 13, all verified in this session)

Format: file:line — grade/diagnosis — action. The full per-test detail lives in
the chapter files. Counts beyond these 13 are in the chapter digests.

| # | Where | Finding | Action |
|---|---|---|---|
| 1 | review_controller_test.dart:2194 | prewarm "INV-050" smoke: deleting the prewarm body keeps it green (asserts only `step!.isCorrect, isTrue`) | replace with a real observable from the prewarm path, or retitle honestly as a smoke; issue opened |
| 2 | design/srs_settings_screen_test.dart:40 | "updates preferences" smoke: every tap asserts only `takeException, isNull`; no persisted/provider/UI echo | same |
| 3 | design/srs_page_head_test.dart:37 | title promises trailing hidden + back disabled; asserts neither mechanism | add the two missing asserts |
| 4 | design/srs_toast_test.dart:138 | tone loop iterates `SnackBarType.values` but never passes `type:` — 3 identical iterations, grade 0 | pass the loop value or delete the loop |
| 5 | domain/scheduler_test.dart:94/228 | lapse branch sets `stability` (`scheduler.dart:107`/:205) — never asserted; ledger Stream-1 survivor family | fix PR opened (adds the assertion, mutant-named) |
| 6 | domain/scheduler_test.dart:278 | SimpleScheduler stability-zero fallback (`scheduler.dart:85-87`) untested — EaseScaling twin covered | port the fallback test |
| 7 | domain/scheduler_test.dart:136/254 | interval caps assert `<=` only; too-tight clamp passes (no exact-value boundary) | assert exact clamp value at boundary |
| 8 | persistence/sqlite_study_repository_test.dart:233 | >800 id chunking: only one row seeded (index 42); chunk 2 loss invisible | seed one row in the second chunk |
| 9 | import/pgn_importer_test.dart:49 | whitespace-only import: only `chapters.isEmpty` — silent success (zero errors) passes, contradicting :41 | assert `errors.isNotEmpty` |
| 10 | test/utils/rate_limit_test.dart | 18 wall-clock sleeps in debounce/throttle boundaries exactly where it asserts; ~2s pure sleep per run | fakeAsync/poll table; issue |
| 11 | network/socket_test.dart + connectivity + engine_providers | 8/6/5 fixed sleeps; engine_providers sleeps the full 2s dispose delay 4x (~6s runtime) | fakeAsync/clock elapse; issue |
| 12 | model/common/service/sound_service_test.dart:63 | sound "coverage" is 2 `completes` on Future.value fake; `_RecordingSoundService` exists in 1 file only; `test/sound/` missing | recording-service pattern repo-wide; issue |
| 13 | .gates/ratchet-baseline.json | test_declarations floor 1509 vs actual 1858; baseline drift discipline | re-baseline in a gates PR (referee, owner decision) |

## dedup notes

- 2026-10-16 spec-conformance audit findings F2 (tree-rewrite invisibility),
  F4 (chunk ceiling under ~32k param limit), F3 (migration fixtures v6-v11,
  v14-v15), F5 (117 orphan rows), F6 notes — stay theirs; not re-opened here.
- Stream-1 ledger row for scheduler.dart (10 mutants, 6 killed, 4 survived)
  predicted findings 5 and 6; the mutation outputs are uncommitted
  (`scripts/autonomous/` untracked) — evidence unreproducible until committed.
