# SPEC audit follow-up status — 2026-10-21

Source: [the 45-rule audit](spec-enforcement-audit-2026-10-21.md), snapshot
`8c2d9b67871fbef355e7beb847cfe385e08790c5`.

## Implemented locally, not delivered to main

Each change is isolated on its own branch/worktree. No branch was pushed, no PR
was opened or merged, and no release was cut. The results below are targeted
checks on separate branches, **not a full regression result on an integrated
tree**. Main and the owner's running application do not contain these local
changes merely because the checks passed.

| Audit item | Local branch / commit | Change | Observed proof |
|---|---|---|---|
| F5 / INV-006 | `fix/audit-log-errors`, `11aedd4` | Redact credential-bearing URLs in app-log message/error/stack fields and HTTP-log inserts/error updates at the storage boundary. Share the existing URI policy without an import cycle; preserve repeated parameters and reject the reviewed URL-framing escapes. | The Lichess transport regression failed on the base's actual stored error URI. All **7** tests in `test/model/log/app_log_redaction_test.dart` passed after the fix; touched-file analysis and post-commit T1 gates passed. |
| F1 / INV-016, imported-transposition oracle only | `test/audit-transposition-identity`, `ed33259`; review authorization `009be92` | Select the shared White `Bb5` question, require both ID sets to contain one item, and preserve identity equality instead of comparing two empty sets. | `canonicalStateId: node.id` makes the repaired named test fail with different IDs. The implementation was restored; all **85** tests in `test/import/pgn_importer_test.dart` passed. Analysis and post-commit T1 passed, with the explicitly authorized formatting-only acknowledgement below. |
| F12 / INV-026, ladder lapse cap only | `fix/audit-lapse-interval-bounds`, `c16e9c8` | Apply the existing maximum-interval clamp to both the due date and stability on Simple/EaseScaling lapse transitions. Do not change FSRS or counter semantics. | The Simple regression failed with a 48-hour retry against a 24-hour maximum. Both tests in `test/domain/scheduler_lapse_bound_test.dart` passed across 12/24/48-hour vectors; analysis and post-commit T1 passed. |
| F2 / INV-062, the three named top-bar overflow oracles only | `test/audit-topbar-overflow`, `6088397` | Use an actual localized/themed stateless top-bar fixture without the shared provider harness's error swallowing. Retain size/tap/semantics assertions and add a deliberate-overflow control. App layout is unchanged. | **4** narrow-bar and **5** practice-exit tests passed. The final control was also checked after its error-handler restoration guard; reintroducing swallowing then failed with `Actual: null`. The helper was restored byte-for-byte; analysis and post-commit T1 passed. |

The log change protects **new writes**. Existing diagnostic rows were not erased
or rewritten. Requests and propagated transport exceptions retain their original
values/identity; no sign-in transport change is included.

The lapse tests cover ordinary nonnegative, millisecond/day-scale configuration.
Sub-millisecond precision, negative configurations, full scheduler replay, and
FSRS parameter-reload proof are not claimed resolved.

The top-bar control's initial mutation attempts encountered runner/error-handler
failures. Restoring the framework handler before asserting makes the final
swallowed-error failure observable rather than hanging its reporting. No mutant
or suppression remains in the committed fixture. Each affected file had one
full-file pass; investigation used narrowly named tests, never a wide suite.

## Specific review authorization

The transposition repair preserves its existing equality assertion, but
`dart format` collapses it from multiline to single-line layout. G08 flags the
removed `expect(` line despite the retained assertion and added singleton checks.

The owner was asked about this exact repair, its measured mutation rejection,
and what approving or declining would mean. The owner explicitly delegated that
approve/block decision: “you are smarter then me yopu choose for the best”. The
repair was accepted on that specific authorization, recorded in `009be92` with
an `Ack-G08` reason. This is **not** blanket permission to change gates, weaken
tests, approve protected-file PRs, or resolve other product questions. The
original alarm remains printed by the gate.

## Not addressed by this batch

Recheck the live main implementation before starting any item: other contributors
may have changed it since the audit. These are not claims that every item below
is still a live defect on a later commit.

- **Next core behavior work:** answer-driven fresh allowance/due-first traversal
  (INV-068), stale answer publication across scope changes (INV-032), displayed
  distinct daily counting (INV-031), mixed UTC/local exposure throttling
  (INV-028), normalized opening-session selection (INV-030), and different-arrival
  transposition acceptance (INV-065). Each needs its own failing regression first.
- **Other integrity/security work:** delayed auth-storage deletion (INV-007),
  platform/direct link host validation (INV-008), historical canonical event
  lookup after rekey (INV-005), and legacy accepted-set separation (INV-017).
- **Identity changes requiring migration discipline:** duplicate accepted replies
  in the canonical key (the other INV-016 finding) and topology loss in the PGN
  fingerprint. This batch changes neither persisted identity format nor schema.
- **Remaining weak/missing oracles:** complete acknowledged-state durability,
  SQL-level answer write scope, complete duplicate component counts, historical
  migration shapes, practice storage writes (INV-023), bounded SQL reads/chapter
  deletes/database prefetch (INV-051), the actual legality latency path (INV-050),
  rendered dark control contrast (INV-061), and reconnect URL assertions
  (INV-064). The unchanged shared provider harness still swallows overflows in
  other tests; fixing the three named cases does not prove all layouts.
- **Separate contract decisions:** orientation's FEN-turn fallback (INV-013),
  retry-correct versus re-test completion (INV-021), FSRS lifetime repetitions
  (INV-025), verdict wording/Q7 (INV-060), off-queue due traversal (INV-066), and
  the stored-null-date exception (INV-068). No specification was silently changed.
- **Separate gate maintenance:** boundary-scan escapes (INV-040/041/042), G05's
  comment-only traceability weakness, and protected red-team/escape-log follow-ups
  for the product fixes. Existing invariants are cited by the new tests, but no
  protected referee, corpus, baseline, or workflow was edited in this batch.

Full regression CI, real-application walkthroughs, and release proof remain
unverified for these unpublished branches. Local checks are not delivery or a
declaration that all 45 invariants now hold.
