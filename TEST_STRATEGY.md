# Verification & Testing Strategy

Authority: verification workflow and methods. `SPEC.md` owns the per-invariant
oracle/covering-file list; `GATES.md` owns gate definitions and change-class
evidence. See `docs/documentation-map.md`.

## 1. What each kind of evidence proves

- Deterministic domain tests: fixed Clock and seeded Random exercise schedule,
  queue, branch and graph behavior without a widget tree.
- Import/export tests: tree structure, legal adapters, quarantine and round trips.
- Persistence tests: real sqflite-FFI database, close/reopen durability, upgrade
  fixtures, write-scope/argument-count assertions, failure rollback.
- Provider/service tests: actual orchestration over repository/HTTP boundaries.
  Follow the HTTP-mocking and board-helper patterns in `CLAUDE.md`.
- Widget tests: rendered controls, board interaction, semantics and viewports;
  they cannot prove a physical speaker, haptic motor or production OAuth flow.
- Property/differential tests: laws and equivalence, not just happy examples.
  Mutation and fail-to-pass evidence assess whether tests detect wrong code.
- G05: invariant IDs are cited, **not** that the cited test proves the claim.
- Reachability tests walk the import/export graph from lib/main.dart and reject
  new unreachable source against their baseline. They run as part of G04;
  their source/baseline, not this document, defines the executable ratchet.

Legacy tests (`legacy/pre-reset`) are behavioral references only. Translate
useful contracts into the current architecture; do not restore legacy code.

### Enforcement navigation index (not a second contract)

The existing `test/reachability/enforcement_matrix_test.dart` reads this table,
checks named paths exist and rejects an emptied index. Retain it for navigation:
the authoritative requirements and exact oracle/covering lists remain in SPEC
or QUALITY; representative targets below do not promise exhaustive proof.

| Invariant / property | Authoritative contract | Representative enforcement target |
|---|---|---|
| Domain purity and I/O | SPEC INV-040/042 | `test/gates/domain_boundary_test.dart` |
| Single chess representation | QUALITY §1.2 | `test/import/pgn_importer_test.dart` (adapters); dependency review |
| Local-first review | QUALITY §1.3 | `test/review/review_service_test.dart` (local service path); architecture review |
| Variation preservation | SPEC INV-010 | `test/import/pgn_importer_test.dart` |
| Malformed input and starting positions | SPEC INV-011/012 | `test/import/pgn_importer_test.dart` |
| Chapter orientation | SPEC INV-013 | `test/import/chapter_orientation_test.dart` |
| Position identity and memory sharing | SPEC INV-015/016/017 | `test/domain/position_knowledge_state_test.dart` |
| Scheduling and time injection | SPEC INV-024/025/026/041 | `test/domain/scheduler_test.dart`, `test/domain/chess_fsrs_scheduler_test.dart` |
| Repertoire grading and lapse recovery | SPEC INV-020/021/033/065 | `test/review/review_engine_test.dart`, `test/review/review_transposition_test.dart` |
| Traversal and practice | SPEC INV-022/023 | `test/review/review_engine_test.dart` |
| Durability, incremental writes and upgrades | SPEC INV-001/002/005/069 | `test/persistence/sqlite_study_repository_test.dart`, `test/persistence/migration_fixtures_test.dart` |
| Move latency | QUALITY §4.1, SPEC INV-050; limits in §3 below | `test/review/move_latency_test.dart` |
| Review interaction, semantics and annotations | SPEC INV-060/062/063 | `test/view/review/review_screen_test.dart` |
| Invariant citation coverage | GATES G05 | `scripts/gates/spec_trace_check.py` |
| Source reachability | GATES G04; executable source/baseline | `test/reachability/reachability_test.dart` |

## 2. Local versus remote verification

### Local development (bounded)

- Iterate with one explicitly named test in the affected file:
  `fvm flutter test <file> --plain-name '<test name>' --concurrency=1`.
- Run the affected full file once at the end, with `--concurrency=1`.
  A base-code fail-check counts as the second file run; then stop. Prefer an
  isolated scratch copy over altering another checkout's work.
- Format touched hand-written Dart files and run one targeted
  `fvm flutter analyze <touched paths>` after the last edit.
- Do not run adjacent files, whole directories, a full suite, `./verify`,
  multi-worker tests or watch-mode tests locally. No offline/pre-push exception:
  report full verification pending when CI is unavailable.
- Run heavy commands serially. Skip Flutter dependency/codegen/build work for
  Markdown-only changes; validate diff, paths, contracts and fast gates instead.
- Release builds run on GitHub runners only, never on the developer's machine.

### CI and fast gates

The `Tests` job in `.github/workflows/test.yml` runs code generation, format,
analyze, full Flutter tests and release/nightly script checks. `verify` is a
full-suite convenience wrapper, not literally the command CI calls.
The `T1 fast gates` job in `.github/workflows/gates.yml` uses trusted-base
scripts/config for referee checks, traceability and ratchets; the local wrapper
uses checkout copies, so its result is not independent review.

Markdown-only PRs **do trigger both workflows** under their current filters,
because a required check that never reports blocks the merge permanently. Read
the live workflow paths rather than assuming every push triggers both lanes.
Since 2026-10-23 a diff that is *only* Markdown under `docs/**` takes the
`Tests` job's docs-only fast lane (classifier `.github/scripts/ci-docs-only.sh`,
unit-tested on every PR): the job still runs and still reports `Tests`, it
simply skips the Flutter steps, because no step reads those files. Root
Markdown is deliberately excluded — `test/reachability/enforcement_matrix_test.dart`
parses `TEST_STRATEGY.md`, so an edit to it (or to SPEC/GATES/QUALITY/AGENTS), a
`docs/screenshots` golden, or any code path still runs the full suite. The
`T1 fast gates` lane is unchanged and cheap. Merges are direct: `strict`
requires the branch to contain the latest `main` and both required checks to be
green on that exact head, and a behind branch is synced by hand
(`allow_update_branch` makes it a UI click). No merge queue is offered for this
repository (verified 2026-10-23), though both workflows already trigger on
`merge_group` if one ever is.
Required check names and evidence/approval policy are in `GATES.md`.
Run the fast gates on the committed branch as required there; do not interpret
an empty committed diff as proof of an uncommitted change.

## 3. Performance evidence and limits

`test/review/move_latency_test.dart` times awaited service submissions including
incremental persistence on a small seeded path. It asserts median **<16 ms** and
prints p90/max. It is neither a pinned-device frame measurement nor a tail
latency guarantee. QUALITY §4.1 and INV-050 retain their requirements; their
scope mismatch is recorded as Q12 in `docs/open-questions.md`.

For performance changes, report dataset, mode, warmups, sample spread and
harness; prove equivalence. Read `docs/performance-handoff.md` and the linked
measurement brief before relying on earlier timings. Do not optimize from a
single noisy median or treat session-start timing as move-response timing.
Planned pinned-runner budgets live in GATES_PLAN, not as already-running gates.

## 4. Runtime acceptance (user-visible work)

1. Confirm CI evidence for the change's current SHA, not the latest unrelated run.
2. Launch the real app (`fvm flutter run -d linux` or attached device), exercise
   the affected flow, and quit. A widget capture is not this walkthrough.
3. For visual changes capture the affected screens at phone, tablet and desktop
   widths in light/dark themes; compare against `design/reference/index.html` at
   matching sizes/themes.
4. Record date, commit, actions and result with the delivery entry in
   IMPLEMENTATION_PLAN. Record uncovered physical/device checks in
   `docs/manual-test-log.md` in the shipping PR. Mark unperformed checks
   unverified, not completed. Product decisions belong in `docs/open-questions.md`.

Wait for remote runs with
`gh run watch <id> -R cassandre60/ChessSRS --exit-status`, not polling loops.
