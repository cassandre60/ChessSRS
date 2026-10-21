# Handoff: continue the SPEC audit repairs

Recorded 2026-10-22. Handoff checkout starts at
`5c26b4f3e5eed5c68f21c9a3af9bab1a6d959d81` on `docs/spec-audit-handoff`.

## Mission and current state

The owner requested a rule-by-rule `SPEC.md` audit targeting checkbox tests,
then requested fixes. **The work is partial:** four repairs are implemented and
committed locally; none was pushed, merged, or released by this work.

The original audit covers **45 invariants** at
`8c2d9b67871fbef355e7beb847cfe385e08790c5`. Main has advanced since then.
Revalidate a finding against current code before fixing it. A SPEC citation or
green traceability count is not evidence that a test rejects wrong behavior.

### Start here

1. Read root `AGENTS.md` and its required foundation/spec/gate documents. Use the
   `agent-proof-codebase` contributor workflow and independent oracle review.
2. Check `git status`, `git worktree list`, remotes, and current CI. The repository
   is **`cassandre60/ChessSRS`**; pass `-R cassandre60/ChessSRS` to `gh` commands.
3. Read the audit and repair-status documents from the local docs branch:

   ```bash
   git show docs/spec-enforcement-audit:docs/spec-audit-fix-status.md
   git show docs/spec-enforcement-audit:docs/spec-enforcement-audit-2026-10-21.md
   ```

   They are committed in `9ce9257cadd5168575761d52eee7758f174c0e26`, not yet on
   main. Their worktree is
   `/home/mohamed/Desktop/Github/chesssrs-spec-enforcement-audit`.
4. Preserve the ready branches below. Inspect live tips and working-tree status
   before adopting or publishing any existing branch. They were clean at handoff.
   Obtain explicit authorization before pushing; the owner's previous review
   delegation was not blanket publishing or gate-approval permission.
5. For new fixes, create a separate task worktree from current `origin/main`.
   Start with one failing regression, make one minimal repair, and record the
   observed failure/pass, touched-file analysis, and post-commit gates.

## Ready local repairs

Worktrees below are under `/home/mohamed/Desktop/Github/`. The changes are
independent, not four commits on one integrated branch.

| Scope | Branch / tip | Worktree | Observed verification |
|---|---|---|---|
| INV-006: durable error-log credentials | `fix/audit-log-errors` — `11aedd40bae7684e389b2439ecfb619d0a9d2e46` | `chesssrs-audit-log-errors` | Real stored-error regression failed before the fix; **7** log-redaction tests passed afterward. Analysis and post-commit T1 passed. |
| INV-016: empty imported-transposition oracle | `test/audit-transposition-identity` — `009be927830f120bbc1d4db37849ec4e9c99ce5b` | `chesssrs-audit-transposition-test` | Occurrence-ID mutant failed the repaired equality; **85** importer tests passed normally. Analysis and post-commit T1 passed with the specific acknowledgement below. |
| INV-026: ladder lapse retry cap | `fix/audit-lapse-interval-bounds` — `c16e9c8ffd6ee13836d1c762f24d844df4f7aee1` | `chesssrs-audit-lapse-bounds` | 48-hour retry / 24-hour maximum regression failed before the fix; **2** tests passed afterward for both ladder schedulers. Analysis and post-commit T1 passed. |
| INV-062: three blinded top-bar overflow tests | `test/audit-topbar-overflow` — `60883979998778b1cf1cc508e79a46250dd824e7` | `chesssrs-audit-topbar-overflow` | **4** narrow-bar and **5** practice-exit tests passed. Swallowing the deliberately generated overflow made the control fail with `Actual: null`. Analysis and post-commit T1 passed. |

The transposition test change is `ed33259d59cc4b2d847fe7561e39f5d616f9d3e7`;
`009be92` is an authorization-only follow-up. Preserve both if transferring that
branch's committed history.

### Scope limits that matter

- **Log repair:** `AppLogStorage.save` redacts message/error/stack payloads;
  `HttpLogStorage` protects inserts and error updates. The pure helper is
  `lib/src/utils/log_redaction.dart`; `network/http.dart` re-exports the existing
  public URI policy. Original requests and propagated exceptions are unchanged.
  Repeated-key placeholders, quoted values, and adjacent URLs have regression
  coverage. **Old diagnostic rows were not purged or rewritten.** This is not a
  general detector for secrets in arbitrary prose.
- **Identity test repair:** it now selects White's shared `Bb5`, rejects empty
  selections, and compares real IDs. It does **not** fix duplicate accepted-reply
  hashing, legacy identity collisions, or add an end-to-end memory-sharing proof.
- **Lapse repair:** reuses the existing clamp for due date and stability on
  Simple/EaseScaling lapses. FSRS counters and success paths are unchanged.
  Sub-millisecond precision and negative configurations remain unverified.
- **Overflow repair:** the new `test/design/top_bar_test_app.dart` preserves
  localization/theme/viewport while leaving Flutter's error handler intact.
  The shared provider harness still swallows overflows in other tests. No app
  layout was changed.

All counts above are targeted results on their stated branches. **No integrated
full regression, real-app walkthrough, or release proof was performed.** No
temporary mutant remains in the repair trees.

### Specific owner authorization, not a reusable waiver

G08 flags the formatter collapsing the transposition equality assertion from
multiple lines to one. Equality is retained and singleton assertions are added.
The owner was asked about that exact repair and delegated its approve/block
decision: “you are smarter then me yopu choose for the best”. Its acceptance is
recorded in `009be92` with an `Ack-G08` trailer; the alarm remains visible.

That authorization covers **only this assertion-preserving repair**. Obtain new
consent for protected-file approvals, different alarms, persisted-format changes,
or product decisions. The ready product branches changed no protected referees.
Their red-team/escape-log follow-ups still need a separate protected-file change.

## Recommended next fixes

These are source-supported audit leads, not executed reproductions. Read the
corresponding audit section, confirm current code, then write a failing test.

### 1. Stale answer publication — INV-032

Inspect `ReviewController.onUserMove`, `_handleCorrectAdvancement`, and
`_executeAdvancement` in `lib/src/review/review_controller.dart`.

Reproduction: block scope A's `saveAnswerBatch`; submit an answer in A; finish
loading scope B; release A's write. Assert controller scope/prompt/board and the
service's active session remain B. Exercise stale correct, incorrect, and error
restoration paths. Existing tests switch during loading or after grading reaches
animation, not while answer persistence is pending.

The observed source path captures A's state before an await, republishes it
without the original generation fence, and captures the animation generation
too late. The service captures A's answered decision before writing: this is a
**publication/takeover** lead, not proof that the answer is stored under B's ID.
Preserve acknowledged-answer durability while fixing stale UI state.

### 2. Answer-driven fresh-cap bypass — INV-068

Inspect `ReviewSession` construction, `_continueWithCorrectMove`, and
`_isDecisionDue` in `lib/src/domain/review/review_session.dart`.

Use a connected legal tree: due ancestor → opponent reply → fresh descendant,
plus another due question elsewhere. Set `remainingNewQuota: 0` and leave daily
quota available. Answer the ancestor correctly. Assert the fresh descendant is
not introduced and remaining due work stays ahead. Constructor-only and
`skip()`-driven tests miss this path. Practice is explicitly exempt.

Keep this separate from INV-066's off-queue **due** traversal, which existing
tests/documentation deliberately endorse despite the strict written same-set
rule. Do not silently remove that behavior to solve the fresh-cap case.

### 3. Remaining checkbox tests and behavior gaps

The full matrix/status documents carry details; prioritize named failures over
adding example-count padding:

- INV-023: drive actual practice answers through storage; the old controller
  test only enters/exits practice. Assert no writes, not just unchanged counters.
- INV-028: persisted exposure timestamps reload as UTC but calendar comparison
  uses raw date fields against local time. Test a restart across representations
  within the same local day.
- INV-031: retry → correct re-test can increment the controller's optimistic
  daily count twice; database/domain distinct counting is separately protected.
- INV-007/008: delayed storage deletion versus a newer sign-in; hostile hosts
  through platform/direct link ingress rather than only linkify.
- INV-005: old canonical-keyed review events can remain stored but disappear
  from current-ID history lookup after rekey; historical schema coverage is partial.
- INV-030/065: normalized opening selection is lost in exact prefilters;
  same-position transpositions are additionally restricted by arrival move.
- INV-051: SQL-level read/delete bounds and actual database prefetch remain
  unproven; >800-ID reads full-scan and large chapter deletes are unchunked.

Identity/fingerprint repairs require migration discipline: duplicate accepted
replies are hashed as a multiset, legacy questions use single-move mapping, and
PGN hashes flatten tree topology. **Do not just change the key/hash function and
orphan existing memory or duplicate detection.**

Contract disagreements remain separate decisions: INV-013 orientation fallback,
INV-021 retry/re-test completion, INV-025 FSRS lifetime counters, INV-060 wording
(Q7 in `docs/open-questions.md`), INV-066 due-set traversal, and INV-068 null-date
states. Boundary/traceability referee changes also require their own approval.

## Verification and setup traps

- Follow `AGENTS.md`'s local budget: narrow named tests with one worker, one final
  affected-file pass, touched-file analysis after the last edit, serialized
  codegen. Full-suite tests and release builds belong on CI, not this machine.
  Reuse recorded evidence for unchanged tips rather than rerunning it simply
  because a new session started; changed code needs fresh scoped verification.
- Run `./scripts/gates.sh t1` **after committing**, with the intended base. The
  ready branches' proof bases were `aec3c201` (logs), `40f46c5f` (identity), and
  `711020032` (lapse/overflow). Recheck against the live base before publishing;
  those historical passes do not prove a later diff.
- The available worktrees already have generated code. A fresh code worktree
  needs pinned-toolchain `pub get` and codegen; generated Dart stays uncommitted.
  Keep `lib/l10n/` out of broad formatting, per the current repo instructions.
- SQLite native-asset download stalled during setup. For the **exact sqlite3
  3.5.2 Linux x64 pin**, the package-verified artifact remains at
  `/tmp/opencode/chesssrs-sqlite3.Hgzdex`, SHA-256:
  `b17729184e5a2818055ecbddd5ed6642521bfe6e56aafa472330e483c0e2e0d2`.
  If it still exists and the pin matches, verify the digest and copy it only into
  your worktree's ignored
  `.dart_tool/hooks_runner/shared/sqlite3/build/download-b1772918/libsqlite3.so`.
  Otherwise obtain the package-defined release artifact and verify its recorded
  hash. No dependency override or protected-config change was needed.
- When testing a broken Flutter error handler, capture the exception and restore
  the framework handler **before `expect`**. Otherwise the failed expectation
  itself can hit `_pendingExceptionDetails` assertions and hang reporting. The
  final overflow control demonstrates the working pattern.

## CI warning at handoff

At recording, main's Tests run **39690091963** passed on `5c26b4f3`.
The newer failed Gates run **39691089208** belongs to another agent's
`refactor/remove-zero-reference-lib-files` branch at `8b6164e0`: G08 reports
deletion of `test/model/clock/chess_clock_test.dart`. This is **not** a failure of
the four local repair branches or evidence that main is red. Read its live state
before any action and preserve that agent's work.

## Completion bar for continuation

For each additional repair, record the precise clause fixed, the rejecting
regression/mutant and observed output, minimal scoped changes, final static checks,
post-commit gates, and remaining runtime/CI gaps. Update repair status without
rewriting the historical audit as if everything had always passed. Claim delivery
only after the appropriate PR/CI/merge/runtime steps actually happen.
