# SPEC enforcement and test-strength audit — 2026-10-21

Audited snapshot: `8c2d9b67871fbef355e7beb847cfe385e08790c5`.

Follow-up changes are tracked in [spec-audit-fix-status.md](spec-audit-fix-status.md).
The findings below describe the audited snapshot, not a claim that later fixes
are missing from every subsequent branch.

## Outcome

All **45 rules** have identifiable implementation paths and test citations.
That does **not** mean all 45 contracts are enforced. The matrix below identifies
missing enforcement on particular paths, missing clause-level tests, tests that
cannot detect their claimed failure, and intentional behavior that contradicts
the written rule.

No rule is wholly without code or a test reference. The gaps are at the
**enforcement/claim level**, not merely missing files. Quick index:

- **Non-detecting named oracles:** INV-016, INV-023, INV-051, INV-062 (F1–F4).
- **Missing enforcement on an identified path/boundary:** INV-005 (derived event
  history), INV-006, INV-007, INV-008, INV-016, INV-017, INV-026, INV-028,
  INV-030, INV-031, INV-032, INV-051, INV-065, INV-068 (F5–F9, F12).
- **Intentional/contradictory contract oracles:** INV-013, INV-021, INV-025,
  INV-060, INV-066, and INV-068's null-date exception.
- **Incomplete proof rather than an established product defect:** see the
  clause-specific matrix, including durability/write scope, scheduler replay,
  castling callers, latency, rendered contrast, reconnect URLs, and boundary
  scans. A missing example is not treated as a test that cannot fail at all.

The clearest checkbox tests are:

- **INV-016:** the imported-transposition assertion compares two empty sets.
- **INV-062:** three no-overflow assertions use a harness that discards the very
  overflow error they claim to detect.
- **INV-023:** the controller's practice-persistence test submits no practice
  answer and inspects no persisted review outcome.
- **INV-051:** returned-row assertions and a repository-method spy do not detect
  unbounded SQL hidden inside a scoped repository method.

No production code, existing tests, specifications, or gate definitions were
changed by the audit phase itself. Subsequent code/test repairs are isolated on
the branches listed in the follow-up status document.

## Evidence and limits

This is a source-level audit of every invariant, including searches beyond
SPEC's listed test files and independent challenge reviews. A citation was not
accepted as evidence without reading the corresponding test body and its
harness. For each rule, the question was: what specific violation can this
assertion observe, and what violation can still pass?

Unless explicitly marked **executed**, failure/survival statements are static
predictions. They are not mutation scores, observed production incidents, or a
claim that the whole suite passes with a mutant installed.

Executed evidence:

1. `gh run list -R cassandre60/ChessSRS --commit 8c2d9b67871fbef355e7beb847cfe385e08790c5`
   showed the baseline **Tests** run
   [39671539985](https://github.com/cassandre60/ChessSRS/actions/runs/39671539985)
   completed successfully. This is baseline CI, not negative-control evidence.
2. `BASE_REF=8c2d9b67871fbef355e7beb847cfe385e08790c5 ./scripts/gates.sh t1`
   reported `t1 ok` and **45 invariants / 45 referenced by tests** on the unchanged
   snapshot. G07/G08 had an empty diff; this is not evidence of test strength.
3. The actual `spec_trace_check.py` accepted an external scratch test directory
   containing **45 comments and no executable tests**, reporting **45/45** and
   exiting 0.
4. The actual G03 checker rejected a scratch single-quoted Flutter import
   (exit 1), but accepted socket I/O, a new scheduler's direct clock read,
   `[DateTime.now].single` in a clock-ruled file, and a Flutter re-export
   (exit 0). These are **G03 checker escapes**, not proven full-CI escapes.
5. A focused pure-Dart check called the actual `canonicalKeyForPosition` with
   `['e2e4']` and `['e2e4', 'e2e4']`. It printed
   `same accepted set produces same key: false` and failed with
   `Duplicate accepted reply changes canonical memory identity` (exit 255).
   This is an executed contract counterexample, not an existing-test run.
6. `fvm flutter pub get` succeeded. The only attempted Flutter test command was
   `fvm flutter test test/gates/domain_boundary_test.dart --concurrency=1 --reporter=expanded`.
   It timed out at 120 seconds in the SQLite native-assets hook, before test
   assertions ran. No Flutter test passed or failed on an assertion in this
   session. No codegen, full-suite run, release build, or application walkthrough
   was performed.

The scratch checker inputs and pure-Dart probe were outside the repository, under
`/tmp/opencode/`. There are no retained product mutants.

## Findings: tests that cannot detect the claimed failure

### F1 — INV-016: empty-set equality masquerades as imported transposition proof

`test/import/pgn_importer_test.dart:575`, **a transposition of the same position
converges on one id**, imports both lines with the default White orientation,
then selects decisions offering Black's `b8c6` reply at line 585. Neither list
contains that scheduled reply. The assertion at lines 589–593 is `{ } == { }`.

Giving every imported decision a different occurrence-specific identity would
still satisfy this particular assertion. Other shared-memory tests are useful,
but mostly hand-wire the shared canonical ID; they do not rescue this empty
import oracle. Moreover, the two positions *before* the selected `Nc6` moves are
not the same position. Select a genuinely shared player decision, assert that
each selection is nonempty, and then compare its identity and persisted progress.

### F2 — INV-062: the overflow oracle discards its own failure signal

`test/test_provider_scope.dart:224–242` installs `ignoreOverflowErrors` as
`FlutterError.onError`. Errors containing `A RenderFlex overflowed by` are not
forwarded to the test handler.

These tests assert only `tester.takeException() == null`:

- `test/design/top_bar_narrow_test.dart:70`: **the bar fits the narrowest
  permitted window without clipping**.
- `test/design/top_bar_narrow_test.dart:76`: **the bar still fits when the due
  count is widest**.
- `test/design/practice_exit_test.dart:88`: **the taller target does not overflow
  the top bar row**.

They cannot reject that RenderFlex failure. This does not mean the bar currently
overflows or that all layout tests are useless: target measurements, actual taps,
sheet scrolling, and independent geometry tests elsewhere are substantive.

### F3 — INV-051: result correctness is not a batching or bounded-loading oracle

`test/persistence/sqlite_study_repository_test.dart:2489` supplies exactly 400 IDs
and verifies a returned state. It never observes multiple query chunks or their
binding counts. A 1,000-item chunk size or whole-table read followed by filtering
can return the same result.

The >800-ID test at line 390 checks one matching row per table and expressly
exercises the full-scan implementation. The service test at
`test/review/review_service_test.dart:419` asserts that `getAllReviewStates` was not
called, but its spy at lines 2199–2208 cannot see a whole-table SQL query inside
`getReviewStatesByIds`.

The older prefetch test at `test/review/review_engine_test.dart:683` checks eventual
card appearance and totals. Disabling the in-memory buffer while preserving the
same sequence can satisfy it. Newer wiring/refill tests catch real regressions,
but do not prove bounded database loading.

### F4 — INV-023: entering practice is not evidence that practice answers write nothing

`test/review/review_controller_test.dart:1169`, **startPracticeMode trains study
without updating SRS review states**, enters and exits practice but does not
submit a practice answer or compare persisted states/events. Removing the
service's no-write guard is outside that test's observation.

Engine tests do grade actual practice moves and assert unchanged selected fields
and null events. They still cannot see redundant repository writes of unchanged
state. Exercise correct, wrong, retry, and traversal paths through the actual
service with a storage write recorder.

## Findings: missing enforcement or missing clause-level proof

### F5 — INV-006: redacting the URL field does not redact attached errors

The request URL is correctly redacted at `lib/src/network/http.dart:205`.
However, the client catch blocks attach the original exception to log records at
lines 523 and 673. `lib/src/model/log/app_log_storage.dart:94–101` copies
`record.error.toString()` without redaction, and
`lib/src/model/log/app_log_service.dart:82–88` persists that record. The comment
`Redact credentials before persisting` at line 75 has no implementation.

A transport exception carrying a secret-bearing request URI can therefore reach
the durable app-log error field. The concrete example is
`ClientException('failure', request.url)` on an authentication query fallback.
For this exception, the `http_log` callback stores `error.message`, not its URI;
do not confuse that with the demonstrated source path into **app_log**. Other
error strings also lack a universal sanitization boundary.

`test/network/http_redaction_test.dart:125` scans selected source spellings rather
than executing persistence. Normal HTTP logging and app-log persistence are
disabled under `FLUTTER_TEST` (`http.dart:198,210,221` and
`app_log_service.dart:82`). No persisted-error redaction oracle was found. This
is a source-confirmed escape path; an actual durable secret leak was not run.

There are also useful behavioral exception-redaction tests at
`test/network/http_redaction_test.dart:151–184`; they cover application-generated
response/mapping exceptions, not raw transport errors serialized through
`AppLogEntry`. The download test at line 189 records message strings only, not
attached errors. Do not describe all existing redaction tests as source scans.

### F6 — INV-007/008: tested entry windows are narrower than the security rules

- **INV-007:** `AuthController.checkToken` fences before and after
  `await authStorage.delete()` (`lib/src/model/auth/auth_controller.dart:138–145`).
  `AuthStorage.delete` unconditionally deletes one shared session key
  (`lib/src/model/auth/auth_storage.dart:51–54`). A newer sign-in whose write
  completes during a delayed delete can survive in memory but lose its stored
  session. The startup test delays validation, not deletion; its fake delete
  clears immediately (`test/model/auth/startup_token_check_test.dart:29–32`).
  The storage completion order is an untested race possibility, not an observed
  platform incident.
- **INV-008:** the hostile-prefix tests exercise `onLinkifyOpen`, which correctly
  checks the parsed host. The platform URI stream and direct `handleAppLink`
  proceed to the path-only resolver without that host guard
  (`lib/src/app_links_service.dart:50–91,100–103,229–235`). The Android manifest's
  host filtering mitigates platform delivery; it is not an application-level
  assertion about every entry point. No hostile-host stream/direct-handler test
  was found.

### F7 — INV-001/002/003/005: persistence tests observe less than their titles promise

- **INV-001:** genuine file-backed close/reopen tests exist, including a vertical
  slice through the service. Neither compares the complete acknowledged state
  before and after reopening. `test/persistence/sqlite_study_repository_test.dart:342–345`
  compares repetitions/lapses/stability/due date; the vertical slice uses a
  stability lower bound and selected counters. Changed difficulty or other
  timestamps at reopen can escape these durability assertions.
- **INV-002:** the repaired service test does record tree-writing repository
  calls. It is no longer the original checkbox test. A same-value SQL rewrite of
  `treeJson` *inside* the delegated SQLite `saveAnswerBatch`, however, evades the
  outer repository-call recorder and leaves its snapshots equal. Also,
  `RepertoireNode` equality compares ID/FEN key, not the complete tree
  (`lib/src/domain/repertoire_node.dart:127`); decision equality omits accepted
  moves (`lib/src/domain/repertoire_decision.dart:69–76`). No SQL-level answer
  write-scope oracle was found.
- **INV-003:** duplicate-import tests count studies and some winning decisions,
  not all chapters and decisions. An extra empty chapter under the winning study
  can escape those assertions. The canonical fingerprint also omits branch
  boundaries; see the adjacent integrity risk below.
- **INV-005:** the added v6–11 and v14–15 fixtures are real progress, but the v12
  test seeds no old rows, v16 seeds only a study table, and no v18-entry fixture
  was found. Historical schemas are largely generated by stripping current DDL,
  rather than frozen copies of shipped schemas. The applicability of inherited
  v1–5 to this fork was not established, so their lack of fixtures is not counted
  as a confirmed shipped-version gap. Existing fixtures also do not exercise
  canonical-keyed review-event history across a rekey.

The event-history omission has a concrete historical shape: at commit
`0664a73de`, schema v10 already wrote review events using `decision.canonicalId`
(`lib/src/domain/review/review_session.dart:171–176,209–214`). Current rekey moves
decisions, knowledge, and mirrors, but not those event keys. Current
`getReviewEvents` searches the occurrence/current canonical keys
(`lib/src/persistence/sqlite_study_repository.dart:1156–1175`). Old event rows can
remain physically present while disappearing from normal current-ID history
lookup. Existing migration event fixtures use occurrence keys. No affected
owner-database rows were inspected in this audit.

Adjacent fingerprint risk: `lib/src/import/pgn_importer.dart:78–83,105–112`
hashes depth-first SAN text without parent/branch delimiters. By static traversal,
these different legal trees have the same fingerprint input:

```pgn
1. e4 e5 (1... c5 2. Nf3) 2. Nc3 *
```

```pgn
1. e4 e5 2. Nc3 c5 3. Nf3 *
```

Both flatten to `e4,e5,Nc3,c5,Nf3,|`. This is not a cryptographic SHA collision;
the serialization already lost tree topology. It is an adjacent identity defect
that the INV-003 hash examples cannot detect. The counterexample was not executed
through the importer or controller.

### F8 — INV-016/017: accepted-set identity is incomplete at two boundaries

The executed duplicate-reply check shows that `canonicalKeyForPosition`
(`lib/src/domain/position_knowledge_state.dart:39–47`) sorts a list but does not
deduplicate it. The same accepted reply **set** can receive different IDs. No
existing duplicate-reply key test was found; this does not establish whether the
PGN parser itself preserves duplicate children in every input form.

Modern questions are protected against colliding single-move lookups. Legacy
questions are not: `lib/src/domain/graph_aware_review_coordinator.dart:126–128`
still resolves legacy identity through `(FEN, first move)`. Pre-v10 migrations
leave some decisions without complete-set canonical IDs. The legacy coordinator
test at `test/domain/graph_aware_review_coordinator_test.dart:751` deliberately
asserts that map-first behavior; it does not test two legacy questions with
different accepted sets sharing the first move.

### F9 — INV-051: bounded reads/deletes are not universal in the implementation

- Above 800 requested IDs, `getReviewStatesByIds` and
  `getKnowledgeStatesByCanonicalIds` issue unrestricted table queries
  (`lib/src/persistence/sqlite_study_repository.dart:1119–1125,922–928`). Filtering
  precedes domain-object conversion, so the precise problem is **whole-table SQL
  result materialization**, not conversion of every row into a domain state.
- `deleteChapter` sends every occurrence ID into two unchunked deletes at
  `sqlite_study_repository.dart:527–538`. There is no large-chapter binding-count
  oracle. The repaired large-`deleteStudy` recorder is substantive and should not
  be reported as still broken.
- The prefetch buffer slices already-loaded decisions. It is not bounded
  database prefetch. `ReviewService._getActiveDecisions` loads all decisions
  before active-study filtering (`lib/src/review/review_service.dart:949–955`),
  while the queue buffer lives in `review_session.dart:414–422`.

No parameter-limit failure or production memory measurement was performed.

### F10 — INV-050/061/062/064: useful tests still leave important clauses unchecked

- **INV-050:** the stopwatch wraps synthetic direct-match service grading plus
  real SQLite persistence. The controller's real board `Position.play`
  (`lib/src/review/review_controller.dart:1550`) is outside it. The fixture uses
  `fen_*`/`startfen` and synthetic SAN (`test/review/move_latency_test.dart:75–119`),
  and the assertion checks median, not each move (`:162–175`). Samples
  `[1,1,1,1,100,100] ms` satisfy the median bound while two moves miss a frame.
  This is an incomplete budget oracle, not evidence of measured slowness.
- **INV-061:** the mounted pill test checks only foreground != background in
  light mode (`test/design/design_primitives_test.dart:125–140`). Near-identical
  unreadable colors satisfy inequality, and dark-only widget role mistakes are
  untested. Both-theme token contrast and board-square tests are substantive,
  but do not prove every widget's foreground/fill composition.
- **INV-062:** `SrsSegmented` specifies minimum width 38 and vertical padding 8,
  without minimum height (`lib/src/design/primitives.dart:337–354`). Its tests
  toggle values but do not measure those targets. `SrsPressable` adds no minimum
  size itself. This is a missing size guarantee, not a runtime measurement of
  the rendered control. The general design minimum token is currently 48;
  SPEC's 44-pixel floor is weaker, not stronger.
- **INV-064:** two first-connect tests inspect actual URLs. Reconnects are
  exercised but their query parameters are not independently asserted.
  Production currently uses the same unconditional `connect` URL construction
  for every attempt; no missing-`sri` reconnect defect was found.

### F11 — INV-040/041/042: duplicated textual scans are not a complete boundary oracle

G03 and the in-suite boundary tests recognize selected source strings, not the
dependency graph or syntax. The executed G03 probes passed with:

```dart
import 'package:web_socket_channel/web_socket_channel.dart';
WebSocketChannel openSocket(Uri uri) => WebSocketChannel.connect(uri);
```

```dart
// In a file covered by the clock rule:
final wallClock = [DateTime.now].single;
DateTime readWallTime() => wallClock();
```

The bracket exemption is meant for documentation but does not establish that the
matched text is a comment (`.gates/banned-apis.json:25`;
`test/gates/domain_boundary_test.dart:40–41,77`). The test's I/O scan does not name
`web_socket_channel` (`:85–98`); neither scanner follows transitive imports.
A Flutter re-export also bypasses the `import` patterns, although that attacks
effective purity rather than the literal word “imports” in INV-040.

GATES already acknowledges some G03 aliased/bracketed blind spots. No matching
production violation was found, and the blocked Flutter run means the predicted
G02 escapes were not executed. Do not describe these as full-CI survivors.

### F12 — answer-driven traversal and completion are not covered by construction tests

- **INV-068:** queue construction caps fresh items, but answering a due ancestor
  can follow an opponent reply to a fresh descendant even when
  `remainingNewQuota` is zero. Traversal at
  `lib/src/domain/review/review_session.dart:785–811` checks the daily-review
  allowance, not the admitted fresh set or remaining fresh allowance; its
  `_isDecisionDue` treats absent state as eligible at line 1316. Place another
  due question elsewhere in scope and this also bypasses due-before-fresh.
  The due-first test at `test/review/review_engine_test.dart:1121` advances with
  `skip()`, not a correct answer down a connected line. A comment permitting
  fresh traversal does not establish compliance with the introduction cap.
- **INV-032:** `onUserMove` captures scope A's screen state, awaits answer
  persistence, and publishes from that captured state without checking the
  original generation (`lib/src/review/review_controller.dart:1519–1526,
  1559–1606`). If scope B finishes loading during that await, the old answer
  can restore scope A. The later animation guard takes its generation snapshot
  only at line 1201, after this vulnerable window. Existing animation-race tests
  switch after grading reaches `lastStepResult`; they do not gate persistence.
  The service captures A's answered decision before its write, so this is a
  stale publication/takeover path, not proof of an answer being written under
  B's decision.
- **INV-031:** the controller increments `dailyReviewedCount` on every successful
  advancement (`lib/src/review/review_controller.dart:1403–1412`), unlike the
  session's canonical-ID set and the database's distinct event count. The
  existing controller test at `test/review/review_controller_test.dart:673–709`
  performs lapse→correct retry→correct re-test but never checks the displayed
  daily count. This can drift the optimistic screen count; the domain set and
  persisted distinct count are not claimed to double-count.
- **INV-028:** exposure timestamps are serialized/reloaded as UTC
  (`lib/src/persistence/sqlite_study_repository.dart:1008–1019,955–972`) but
  compared to local production `Clock.now` using raw year/month/day fields
  (`lib/src/domain/graph_aware_review_coordinator.dart:288–289`). In UTC+02, a
  grant at local 00:30 reloads as the preceding UTC date; another grant at local
  01:30 compares as a different date. Restart tests use UTC on both sides and
  cannot detect this mixed-representation boundary.
- **INV-065:** reached-position membership is additionally constrained by the
  target's recorded incoming move (`review_session.dart:1142,1181`). Put both
  `1.Nf3 Nf6 2.Nc3 Nc6 3.g3` and `1.Nc3 Nf6 2.e4` in scope. At the second line's
  second White move, `Nf3` reaches the first line's position after `Nc3`, but the
  historical arrival moves differ and grading rejects it. Existing acceptance
  fixtures arrive with the target's recorded move. No different-arrival oracle
  was found.
- **INV-026:** both ladder schedulers use the raw `firstInterval` on lapse, unlike
  their correct-answer clamps (`lib/src/domain/scheduler.dart:100–107,198–205`).
  A two-day first interval with a one-day maximum exceeds the maximum on lapse.
  Constructors permit this configuration; cap tests use successes and normal
  parameter ordering. This is a configuration-boundary gap, not a demonstrated
  failure under shipped default parameters.
- **INV-030:** summary/domain matching normalizes opening names, but session
  prefilters compare exact trimmed strings
  (`lib/src/review/review_service.dart:616,982–984`). A case-variant scope can
  report a matching summary yet queue nothing. Import normalizes
  Defense/Defence for new material, reducing that spelling example's reachability,
  but preserves case. The tests exercise normalization at the scope helper,
  not through those prefilters.

These are source-confirmed paths and predicted contract counterexamples, not
executed controller or session failures.

## Intentional behavior / written-contract disagreements

These are not assertion-free tests. Some assertions actively protect behavior
different from the binding text. Do not silently change either side to obtain
agreement.

- **INV-013:** the documented orientation priority ends with default White.
  The implementation additionally uses the custom FEN's side to move before
  defaulting (`lib/src/import/pgn_importer.dart:528–533`), and
  `test/import/pgn_importer_test.dart:888` expressly expects Black for that case.
- **INV-025:** Simple/EaseScaling reset repetitions on lapse. ChessFSRS retains
  lifetime repetitions (`lib/src/domain/chess_fsrs_scheduler.dart:295–297`), and
  `test/domain/chess_fsrs_scheduler_test.dart:124` expressly asserts that.
- **INV-060:** SPEC requires “The repertoire move is”; the app and tests require
  “The study move is” (`lib/l10n/app_en.arb:313`;
  `test/view/review/review_screen_test.dart:557–558`). This is the existing **Q7**
  in `docs/open-questions.md:193–212`, not a new issue. Tests reject a wording
  change; they do not detect agreement with the present SPEC wording.
- **INV-021:** the quota-one lapse→retry case explicitly expects completion in
  `test/review/review_engine_test.dart:1320`, while SPEC says a failed item is
  removed only after re-test pass. Keep this distinct from the substantive
  pending-retest test at line 1409.
- **INV-068:** a stored row with null `nextDueAt` is treated as due by
  `test/domain/due_status_test.dart:48`, whereas SPEC's first sentence requires
  an arrived scheduled date. The distinction from a wholly absent state is
  deliberate; the null-date exception is not written into the sentence.
- **INV-066:** the urgency-selected set is not preserved during the walk.
  `test/review/review_session_test.dart:766–816`, **the daily quota cut can never
  drop a promised re-test**, explicitly prompts a less-urgent descendant that
  the construction-time quota excluded. `docs/review-program.md:226` endorses
  off-queue due prompting. This is contrary to the strict same-set wording, but
  is not an untested accidental behavior. An exception only for full-line mode
  would not resolve the due-only case protected by that test.

## Complete 45-rule evidence matrix

**Oracle** = substantive observable assertion for the stated case, not complete
proof. **Partial** = an important clause/edge has no rejecting assertion.
**Code gap** = a path/boundary is not enforced, not “the entire feature is absent.”
**Drift** = code/tests deliberately disagree with literal SPEC. All predicted
mutation failures in this matrix are unexecuted unless noted above.

### A. Persistence and integrity

| Rule | Enforcing code | Executable test / rejecting assertion | Assessment / uncovered violation |
|---|---|---|---|
| INV-001 | `lib/src/review/review_service.dart:715–753`, `submitMove`; `lib/src/persistence/sqlite_study_repository.dart:829`, answer transaction | `test/persistence/sqlite_study_repository_test.dart:212`, **durability across restart (close and reopen)**: exact counters/stability/due after real file reopen; `test/vertical_slice_gate_test.dart:58`: actual service lifecycle | **Partial.** Losing saved repetitions fails; complete service-produced state equality, including difficulty/timestamps, is not asserted. F7. |
| INV-002 | `lib/src/persistence/sqlite_study_repository.dart:829–876`, `saveAnswerBatch`; service awaits it | `test/review/review_service_test.dart:43`, **incremental persistence: moves save state and event without rewriting trees**: one batch, no tree-writer calls, selected persisted state/event | **Partial, repaired oracle.** Added service tree-writer call fails; direct same-value SQL tree rewrite inside the delegated batch escapes. F7. |
| INV-003 | `lib/src/review/review_controller.dart:1787–1892`, duplicate lookup/scope; `lib/src/persistence/sqlite_study_repository.dart:45–95`, serialized import recheck | `test/review/review_controller_test.dart:1490`, **importing identical PGN detects duplicate and avoids data duplication**: duplicate flag, stored ID, study count; persistence test `:820` checks concurrent winner | **Partial.** Duplicating a study fails; extra chapters/global decisions are not exhaustively counted. Topology-preserving fingerprint oracle missing. F7. |
| INV-004 | `lib/src/persistence/sqlite_study_repository.dart:298–392`, `deleteStudy`; `:512–569`, `deleteChapter` survivor guards | `test/persistence/sqlite_study_repository_test.dart:1088`, **deleteStudy preserves shared canonical knowledge states referenced by another study**; `:1176` preserves shared events/mirrors; `:708` preserves another chapter's state | **Oracle with narrower chapter coverage.** Removing study ownership guards fails; chapter-specific shared canonical event/knowledge retention is not tested as fully. |
| INV-005 | `lib/src/db/database.dart:90–387`, `openAppDatabase` upgrade path; `lib/src/persistence/canonical_rekey_migration.dart:33`, rekey | `test/persistence/migration_fixtures_test.dart:77`, **a v$version database lands on the current schema with its rows and identities intact** (6–11), plus 14/15 at `:177`; v12/13 tests in SQLite suite, v16/17 in `test/db/srs_upgrade_test.dart` | **Partial / derived history gap.** Dropping seeded v6 progress fails. v18 entry, populated v12/v16 shapes, and canonical-keyed event rekey/lookup lack equivalent oracles. F7. |
| INV-006 | `lib/src/model/auth/auth_repository.dart:301–360`, body-first/fallback; `lib/src/network/http.dart:101,205`, URI redaction | `test/model/auth/auth_repository_test.dart:310,415,549`: exact body/fallback transport; `test/network/http_redaction_test.dart:38,47,151,175`: helper/application-exception secrets absent; `:125`: source scan | **Code gap / no durable raw-error test.** Removing URI-field redaction is observable; secret-bearing attached transport error can escape into app-log storage. F5. |
| INV-007 | `lib/src/model/auth/auth_controller.dart:114–145`, generation/token fences and delete | `test/model/auth/startup_token_check_test.dart:127`, **a sign-in during the check is not signed out by its result**: Bob retained in memory/storage; `:101` requires matching invalid Alice to be cleared | **Partial enforcement.** Stale validation deletion fails; delayed-delete/new-write interleaving is not modeled. F6. |
| INV-008 | `lib/src/app_links_service.dart:297–306`, parsed-host guard for linkify | `test/app_links_service_test.dart:475`, **does not treat a host prefixed with the lichess host as first-party**: editor not opened, with legitimate-host positive counterpart | **Code gap on other ingress.** Prefix bug in linkify fails; hostile URI through platform stream/direct handler is untested and unguarded at application level. F6. |
| INV-069 | `lib/src/persistence/orphaned_review_state_sweep.dart:25–42`; `lib/src/db/database.dart:384–385`; rekey mirror carry `canonical_rekey_migration.dart:165–184` | `test/persistence/orphaned_review_state_sweep_test.dart:102`, **a v19 database with stranded rows is swept on the upgrade**: stranded absent/all reachable keys retained; rekey tests `:318,353` inspect old/new mirrors | **Oracle.** Removing knowledge-only reachability or mirror carry is directly observable. |

### B. Import pipeline and identity

| Rule | Enforcing code | Executable test / rejecting assertion | Assessment / uncovered violation |
|---|---|---|---|
| INV-010 | `lib/src/import/pgn_importer.dart:604–683`, recursive `_buildChildren`; `lib/src/import/pgn_exporter.dart:102–151` | `test/import/pgn_importer_test.dart:306,319,325,333`: exact sibling counts/order/subtree; `test/persistence/json_adapters_test.dart:122`: decoded branches/comments | **Oracle for examples; depth coverage partial.** Dropping an example sibling fails; no arbitrary-depth/nested whole-tree oracle. |
| INV-011 | `lib/src/import/pgn_importer.dart:119,266–279,317–328,639–650`, typed quarantine; controller refuses zero-decision imports | `test/import/pgn_importer_test.dart:394,403,461,948`: bad FEN, later valid chapter, exact move locator, non-PGN refusal; controller test `:103` requires no stored empty study | **Oracle.** Abort-after-bad-chapter and wrong-index mutations have rejecting assertions. |
| INV-012 | `lib/src/import/pgn_importer.dart:318–333,620,659–668`, dartchess starting position/normalization/legality | `test/import/pgn_importer_test.dart:357,363`: exact normalized root FEN/key; `:681`, **promotion move encodes promotion piece**: custom-only legal `e7e8q` | **Oracle.** Replacing the custom root with the initial board fails. The isolated custom-position `Nf3` example alone is not discriminatory. |
| INV-013 | `lib/src/import/pgn_importer.dart:451–533`, `resolveChapterOrientation` | `test/import/chapter_orientation_test.dart:11,40,74,92`: exact priority/overrides/mixed sides; importer test `:888` expects Black from a custom FEN | **Drift.** Written default White omits the tested FEN-turn fallback. |
| INV-014 | `lib/src/import/pgn_exporter.dart:34–64,92–151`, metadata and variations; import chapter-title priority `pgn_importer.dart:536–559` | `test/import/pgn_exporter_test.dart:224`, **multi-chapter export keeps the chapters distinguishable after re-import**: exact titles; `:134,170,58` cover side/opening/variation comment | **Oracle for distributed examples.** Dropping named metadata fails; complete nested tree plus all metadata in one round-trip fixture is not asserted. |
| INV-015 | `lib/src/import/pgn_importer.dart:201`, `fenKey`; `lib/src/model/common/chess.dart:427–430`, `positionIdentity`; importer normalizes through dartchess | `test/import/pgn_importer_test.dart:23`: exact first four fields; `:357–366`: normalized custom root; `test/domain/position_knowledge_state_test.dart:22`: pinned independent digest | **Oracle for current path.** Adding clocks or dropping castling/EP fails the exact output. Raw stripping helper is not itself a normalization oracle. |
| INV-016 | `lib/src/domain/position_knowledge_state.dart:39–47`, complete reply identity; `lib/src/domain/review/review_session.dart:122–125`, dedup; shared persistence | `test/review/review_service_test.dart:794`, **transposition sharing: reviewing move in Study A updates shared canonical state in Study B**: manually shared memory/due/one question; importer test `:575` compares empty sets | **Vacuous import oracle; duplicate-set code gap.** Executed repeated-reply check fails; hand-wired sharing remains substantively tested. F1/F8. |
| INV-067 | `lib/src/import/opening_name.dart:67,82,262–266`; `lib/src/persistence/opening_name_repair_migration.dart:39–74` | `test/persistence/opening_name_repair_migration_test.dart:128`: bogus family null, real/unknown preserved; `:43`: current ECO-produced families survive; importer `:133,146` checks bad/unknown headers | **Oracle.** Erasing unknown names or accepting the known bogus title is observable. |
| INV-017 | `lib/src/domain/graph_aware_review_coordinator.dart:126–128`, trusts modern complete-set ID but legacy map-first fallback remains | `test/review/review_engine_test.dart:1750`, **a review is scheduled against the question that was asked, not a different one sharing its FEN and first move**: independent progress; coordinator test `:704` rejects modern collision | **Modern oracle; legacy code gap.** Redirecting modern state to a colliding ID fails. Conflicting accepted sets on surviving legacy rows are not covered. F8. |

### C. Review engine and scheduling

| Rule | Enforcing code | Executable test / rejecting assertion | Assessment / uncovered violation |
|---|---|---|---|
| INV-020 | `lib/src/domain/review/review_session.dart:1133–1138,543,598`, repertoire matching/grading; INV-065 supplies an out-of-line exception | `test/review/review_engine_test.dart:149,232`: expected move correct, legal other move incorrect, exact repetition/lapse state | **Oracle.** Accept-all/reject-all fails. Engine independence/opponent inaccuracy acceptance is supported structurally rather than an explicit adverse-engine fixture. |
| INV-021 | `lib/src/domain/review/review_session.dart:669–680`, lapse requeue; `lib/src/review/review_controller.dart:1594`, feedback; retry clears pending retest at session `:723–724` | `test/review/review_controller_test.dart:640`, **handles incorrect move (lapse) and allows user to reguess on the board**; screen test `:329` exercises reguess/retest; engine `:1409` preserves pending retest | **Quota-path drift/gap.** Removing ordinary requeue fails; quota-one retry completion is explicitly accepted by engine test `:1320` despite SPEC's retest-pass requirement. |
| INV-022 | `lib/src/domain/review/review_session.dart:108–120,789,1218,1313`, due reconsideration/opponent branch selection | `test/review/review_engine_test.dart:186`: exact skipped moves; `:294`: clock makes stored items due; `:565`: forced random rolls reach both due branches; session test `:1781`: guided sideline reached | **Partial.** First-branch-only selection is observed. No combined auto-exposure→persist/reload→updated due-date retrieval or sustained starvation oracle. |
| INV-023 | `lib/src/domain/review/review_session.dart:557,608,849,864`, practice no scheduling/graph credit; `lib/src/review/review_service.dart:730,789`, no persistence | `test/review/review_engine_test.dart:345,402`: real practice moves, null events, unchanged selected fields, exact replies; controller `:1169` enters/exits without answering | **Partial; controller no-write oracle vacuous.** Actual storage writes of unchanged state and differential equivalent-eligibility traversal are not asserted. F4. |
| INV-024 | `lib/src/domain/scheduler.dart:69,167`; `lib/src/domain/chess_fsrs_scheduler.dart:223`, explicit `now`; G03 clock rules | `test/domain/scheduler_properties_test.dart:152`, **INV-024 schedule is pure: wall-clock never consulted**: equal Simple outputs/time-shift relation; `:15` repeats Simple transitions; boundary test `:70` rejects direct clock strings | **Partial across schedulers.** No mixed success/lapse full-state replay for EaseScaling/ChessFSRS; randomness is not banned by this checker. |
| INV-025 | `lib/src/domain/scheduler.dart:77–108,175–206`, ladder growth/reset; `chess_fsrs_scheduler.dart:295–297`, retained repetitions on lapse | `test/domain/scheduler_test.dart:122,152,288,298`: exact reset/lapse/recovery; `test/domain/chess_fsrs_scheduler_test.dart:124` deliberately requires retained repetitions | **Drift.** Simple/Ease reset failures are observable; FSRS tests protect a different counter contract. |
| INV-026 | `lib/src/domain/scheduler.dart:62,160`, success clamps; incorrect branches `:104–107,202–205` use raw `firstInterval`; FSRS clamp/equality | `test/domain/scheduler_test.dart:184,314`: cap checks; FSRS tests `:312,358,372`: preview/equal params; controller `:3186`: scheduler-type reload | **Code gap / partial equality oracle.** Lapse with `firstInterval > maximumInterval` is not clamped/tested. Unequal FSRS field coverage and params-only reload are incomplete. |
| INV-027 | `lib/src/domain/graph_aware_review_coordinator.dart:165–172,221–259`, bounded decaying contagion; session descendant graph `:1352` | `test/domain/graph_aware_review_coordinator_test.dart:152,258`: exact depth-1/2/3 changes, depth-4/cold states untouched; service test `:869`: descendant changes persist | **Numerical oracle; scope partial.** Wrong decay/depth/cold updates fail. No branching unrelated/sibling sentinel fixture establishes the intended line-only scope. |
| INV-028 | `lib/src/domain/graph_aware_review_coordinator.dart:185–218,288`, credit/refusal/raw-date throttle; service loads persisted exposure at `:540–545` | `test/domain/graph_aware_review_coordinator_test.dart:449,488,523,571,603,632`: exact 8% bump, same-day/restart throttle, due/cold refusal | **Strong ordinary oracle; timezone boundary gap.** Persisted UTC and local `now` are not normalized before calendar comparison; mixed-zone same-local-day grant is untested. |
| INV-029 | `lib/src/domain/graph_aware_review_coordinator.dart:270–285`, matching UCI/capped sibling difficulty; session sibling lookup `:1372` | `test/domain/graph_aware_review_coordinator_test.dart:361,411`: matching +0.35, nonmatching unchanged, cap 10; engine `:930`; session `:1517` checks separate sibling identities | **Oracle.** Always-couple/sign-flip/wrong-ID/cap removal is observable. Castling-equivalent confusion matching is not covered. |
| INV-030 | `lib/src/review/review_service.dart:512,581–654,247`, scope/tally; `review_scope.dart:44`, normalized `matches`; service opening prefilters `:616,982–984` are exact | `test/review/review_service_test.dart:1514,1624,1873,2123`: exact active/family/side/chapter results; `test/domain/review_scope_test.dart:188`: Defense/Defence matches | **Opening-path code gap.** Exact prefilters defeat normalized spelling variants before session construction; the normalized helper test cannot see that. |
| INV-031 | `lib/src/persistence/sqlite_study_repository.dart:1182`, local-midnight distinct count; session canonical completion set; controller `:1410–1412` increments display on completion | `test/persistence/sqlite_study_repository_test.dart:1625,1674`: distinct identities/midnight; engine `:1346,1409`: attempts/pending retest; controller `:673` exercises retry→retest but does not check count | **Controller count gap.** Repeated successful completion increments the optimistic screen count; persisted distinct count is separately protected. Active-session midnight rollover is untested. F12. |
| INV-032 | `lib/src/review/review_controller.dart:503,622,1201`, load/animation fences; service activation fence `:699` | `test/review/review_service_test.dart:1113`, **a session that resolves after a newer one has been requested does not become active** (newer completes first); controller `:1086,712`: load/animation races | **Await-window gap.** Delayed answer persistence followed by a completed scope switch is not tested; captured old state can be published before the later animation fence. Older load completing while a newer request is still pending is not exercised. |
| INV-033 | `lib/src/domain/repertoire_move.dart:35–54`, all castle forms; `repertoire_node.dart:100`, `childForMove`; session uses `matches` | `test/domain/entities_test.dart:79`: both directions/all four castles; controller `:1323`, **user playing O-O on board is accepted when expected move is castling** | **Primitive oracle; caller coverage partial.** Map removal fails; raw-comparison mutations specifically in domain tree lookup or king-takes-rook grading lack direct caller tests. |
| INV-065 | `lib/src/domain/review/review_session.dart:1151–1181`, legal target/scope search; `:1142,1181` additionally require matching target incoming move | `test/review/review_transposition_test.dart:313,335,356,409,431`: accepted transposition, outside/off/within-study/cross-study cases; session `:1618`: promotion | **Arrival-path gap.** Existing accepted fixtures use the target's recorded incoming move; a same-position transposition arriving by a different move is untested and rejected by the extra check. |
| INV-066 | `lib/src/domain/review/review_session.dart:165–205,236–272`, urgency cut then order/shuffle; continuation at `:789–811` can choose descendants outside that selected set | `test/review/review_order_test.dart:190,211,236,260`: initial/order oracles; `test/review/review_session_test.dart:766–816` explicitly prompts an excluded descendant | **Drift / contradictory oracle.** Sorting/shuffle failures are observable, but a newer test intentionally protects off-queue due prompting contrary to strict same-set wording, including due-only mode. |

### D. Architecture and wire contract

| Rule | Enforcing code | Executable test / rejecting assertion | Assessment / uncovered violation |
|---|---|---|---|
| INV-040 | Current domain declarations/imports; `.gates/banned-apis.json:4–14` bans selected UI/DB imports | `test/gates/domain_boundary_test.dart:55`, **INV-040 domain imports no UI, database, or chessboard packages**: violation list empty; `:101` verifies both quote forms | **Partial boundary oracle.** Direct named UI imports are detected; transitive UI dependencies/re-exports and adapter-only routing are not established. F11. |
| INV-041 | `lib/src/domain/clock.dart:12–22`, injected Clock; named scheduler/review files checked by `.gates/banned-apis.json:17–26` | `test/gates/domain_boundary_test.dart:70`: named files contain no unexempted clock string; scheduler FixedClock tests | **Checker gap.** Executed bracket-clock G03 escape; predicted same exemption in G02. New scheduler filenames can fall outside the named list. F11. |
| INV-042 | `.gates/banned-apis.json:4–14`, selected direct import bans; current domain computes without I/O imports; G02 adds a substring scan | `test/gates/domain_boundary_test.dart:85`, **INV-042 domain performs no I/O**: `dart:io`, `package:http`, `HttpClient` violation list empty | **Checker gap.** Socket-package I/O is absent from that oracle; executed G03 accepts the socket probe. F11. |
| INV-064 | `lib/src/network/socket.dart:254–290`, `connect` unconditionally builds URL with client `sri`; production pool/analysis clients receive session value | `test/network/socket_test.dart:138,148`, **connects with the sri in the query string** and analysis counterpart: exact recorded query value | **First-connect oracle; retries partial.** Removing `sri` globally fails; first-only `sri` construction is not checked by retry URL assertions. Current code appears conforming. |

### E. Performance budgets

| Rule | Enforcing code | Executable test / rejecting assertion | Assessment / uncovered violation |
|---|---|---|---|
| INV-050 | Controller board legality `lib/src/review/review_controller.dart:1550`; session direct matching `:1133`; service awaits real answer persistence `:753` | `test/review/move_latency_test.dart:127`, **a graded move validates and persists well inside one display frame**: at least six correct submissions; median <16ms | **Partial budget oracle.** Uniform service slowness fails; legality/controller work and slow tails are outside the asserted budget. F10. |
| INV-051 | `lib/src/persistence/sqlite_study_repository.dart:310–385,914–946,1113–1140`, small-read/study-delete chunks and >800 full scans; session in-memory buffer `:414–422` | `test/persistence/sqlite_study_repository_test.dart:1901` observes deleteStudy bindings <=401; `test/review/review_session_test.dart:832` forces zero-threshold refill; engine wiring test `:183` asserts 7/4 config | **Code gaps plus weak read oracles.** Study-delete cap/refill wiring failures are observed. Whole-table large reads, large chapter deletes, and database-level prefetch are not bounded by those tests. F3/F9. |

### F. Review UX and fresh/due partition

| Rule | Enforcing code | Executable test / rejecting assertion | Assessment / uncovered violation |
|---|---|---|---|
| INV-060 | `lib/src/view/review/review_screen.dart:1036–1052,1158–1170`, verdict label/shared live region | `test/view/review/review_screen_test.dart:500`: exact correct/lapse labels, initial silence, correct clearing; `:2593`: correct live-region flag | **Wording drift / partial edges.** Removing announcements fails; SPEC's “repertoire” differs from asserted “study.” Lapse-specific live-region/clearing and unannotated success lack the same independent assertions. |
| INV-061 | `lib/src/design/primitives.dart:169–181`, pill fill/ground label; tokens and theme bridge; board painter/color adapter | `test/design/design_primitives_test.dart:125`: light pill label != fill; `test/design/srs_colors_contrast_test.dart:43,57`: both-theme contrast; `test/design/board_squares_test.dart:27,45,73`: luminance/parity/paint pixels | **Partial rendered-control oracle.** Square swap/token contrast failures are observed. Low-contrast unequal pill colors or dark-only wrong widget role can escape. F10. |
| INV-062 | Size constraints on named buttons/exit/dots; bounded scrolling sheets; segmented target constraints incomplete | `test/design/practice_exit_test.dart:37,59`: actual size/tap; `test/design/design_primitives_test.dart:39,169,284`: named sizes; `test/view/review/study_actions_sheet_test.dart:51`: scroll/tap Delete | **Specific target oracles; three blinded overflow tests.** Shrinking named targets/removing sheet scroll is observable; suppressed RenderFlex errors and unmeasured segmented targets remain. F2/F10. |
| INV-063 | `lib/src/view/review/review_screen.dart:742–764`, shapes gated by annotations + answer revealed; passed to real board at `:866` | `test/view/review/review_screen_test.dart:825,877,1220,1360,2527`: exact empty pre-recall, exact arrow/circle after both verdicts, disabled/toggled setting, position-comment shapes | **Oracle.** Recall leakage, lapse-only reveal, dropped shapes, or ignoring the setting have rejecting assertions. |
| INV-068 | `lib/src/domain/review/due_status.dart:37`; service tally and constructor fresh cap; session `:1316` independently treats missing state as due for traversal | `test/domain/due_status_test.dart:20,36,40`; `test/review/review_service_test.dart:1240,1266`: exact fresh/due/scheduled partition; engine `:1104,1121`: initial cap/skip-driven due-first order | **Traversal gap / null-date drift.** Classification/cap constructor mutations are observed. Answering a due ancestor can reach a fresh descendant outside its allowance before remaining due work; no cross-session introduction cap or answered connected-line oracle. |

## Suggested repair order (no fixes included)

1. Replace the empty transposition and swallowed-overflow oracles with assertions
   that observe nonempty identities and actual geometry/error signals.
2. Close durable-log error redaction and the delayed-storage auth test window.
3. Test answer-driven connected traversal against the fresh allowance, urgency
   selected set, retest lifecycle, and scope-switch persistence window.
4. Record SQL write/query scope and binding counts, including large chapter
   deletes and >800-ID reads. Keep the repaired study-delete/refill tests.
5. Complete the upgrade/history and service-acknowledged state comparison tests.
6. Add mixed-history scheduler replay, lapse caps, params-only reload, and
   mixed-timezone exposure tests.
7. Reconcile intentional spec/code disagreements separately with owner review;
   do not alter the spec or tests inside a product fix to hide the discrepancy.
8. Make the performance and rendered-control assertions match the actual claimed
   path and bounds. Keep broad/mutation verification on CI, not this machine.

G05 remains useful as a missing-citation tripwire. It must not be presented as a
test-strength gate: its implementation (`scripts/gates/spec_trace_check.py:21–26,48–52`)
collects IDs from arbitrary file text. G06/G09 are not wired as blocking mutation
and fail-to-pass jobs in the inspected CI workflows. A named invariant needs an
observed failure against a specific violating implementation—not merely another
comment or checked box.
