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

Markdown-only PRs **do trigger both workflows** under their current filters;
the full remote suite is the accepted cost of reporting required checks. Read
the live workflow paths rather than assuming every push triggers both lanes.
Required check names and evidence/approval policy are in `GATES.md`.
Run the fast gates on the committed branch as required there; do not interpret
an empty committed diff as proof of an uncommitted change.

## 3. Performance evidence and limits

`test/review/move_latency_test.dart` times awaited service submissions including
incremental persistence on a small seeded path. It asserts median **<16 ms** and
prints p90/max. It is neither a pinned-device frame measurement nor a tail
latency guarantee. QUALITY §4.1 and INV-050 retain their requirements; their
scope mismatch is recorded as Q8 in `docs/open-questions.md`.

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
