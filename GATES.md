# GATES: the registry of everything that can reject a change

Protected path. Authority: gate registry, change-class evidence and approval.
See `docs/documentation-map.md`. An undocumented executable check still rejects
a change: document it, do not ignore it because this registry is stale.
Local entry point: `./scripts/gates.sh [t0|t1|t2]`. CI uses trusted-base scripts
and configuration; the local wrapper uses checkout copies, not independent judges.

Product-suite authority is the Tests job in test.yml (format/analyze/full tests
and script checks). `verify` is a convenience wrapper, not CI's literal command.
Local budgets/runtime acceptance live in TEST_STRATEGY. T1 runs no Flutter tests;
t2 can be expensive and requires narrow scoping/remote execution under that budget.
Since 2026-10-23 that job reports in seconds for a diff that is only Markdown
under `docs/**` (docs-only fast lane; the classifier is unit-tested in the same
lane), while root Markdown still runs the full suite because
`enforcement_matrix_test.dart` parses `TEST_STRATEGY.md`. Merges to main go
through a merge queue, so both required checks are re-run against the batched
tree on `merge_group`.

| ID | Gate | Tier | Runtime | Catches | Known blind spots | Local command | Owner |
|----|------|------|---------|---------|-------------------|---------------|-------|
| G01 | format + lint + strict types | T0/T1 | min | style drift, unsafe casts | logic errors | owned by `test.yml` (`dart format` check + `flutter analyze`) | CI |
| G02 | architecture boundary test | T1 | s | domain importing UI/DB/IO, wall-clock reads in scheduling paths | dynamic imports; application-layer network use (import path only, by design) | `fvm flutter test test/gates/domain_boundary_test.dart` | gates PR |
| G03 | banned APIs in core | T0 | s | hidden clocks, layer rot | aliased/bracketed call sites; `Random()` fallback (documented, injected) | `scripts/gates.sh t0` | gates PR |
| G04 | unit + property + widget tests | T1 | min | regressions, invariant breaks | unspecified behavior; load-sensitive review tests (see Blind spots) | owned by `test.yml` | CI |
| G05 | spec traceability | T1 | s | invariants with no test; tests citing unknown IDs | weak tests that cite IDs (needs G06) | `python3 scripts/gates/spec_trace_check.py --spec SPEC.md --tests test` | gates PR |
| G06 | hand-picked mutants (opt-in T2) | T2 | min | missing boundary/state/graph assertions | unlisted lines; equivalent mutants; t2 runs only scheduler_test.dart despite the expanded catalogue | manual_mutation_runner.py with matching narrow test command; inspect before using t2 | contributor |
| G07 | protected paths | T1 | s | referee edits without human approval | uncommitted local edits (CI judges commits) | `python3 scripts/gates/protected_paths_check.py --base origin/main` | owner |
| G08 | test-weakening tripwire | T1 | s | removed asserts/tests, new `skip:`/suppressions in live code | subtle weakening (renamed expectations, padded tolerances); `redteam/` + `scripts/gates/` excluded (inert corpus data / self-naming patterns — both G07-guarded) | `python3 scripts/gates/test_weakening_check.py --base origin/main` (an `Ack-G08: <reason>` commit trailer records reviewed intent; findings still print — the trailer is a line of its own starting with `Ack-G08:`, matched as `^Ack-G08:`, so a mention inside another line does not count) | owner |
| G09 | fail-to-pass (bugfix PRs) | T2 | min | tests that cannot fail | wrong-reason failures (use EXPECT_PATTERN); reviewer-enforced until CI-wired | `bash scripts/gates/fail_to_pass_check.sh <base> "<test cmd>"` | reviewer |
| G10 | ratchets (deps, suppressions, skips, tests, domain size) | T1 | s | silent drift | metrics gamed in isolation (kept small on purpose) | `./scripts/gates.sh t1` (collect + compare) | gates PR |
| G11 | dependency + secret posture | T1 | — | unjustified deps | no scanner wired yet; pubspec.yaml is a protected path so every dep change needs approval | reviewer + G07 | owner |
| G12 | red-team corpus recall | T3/nightly + gate-change PRs | min | weak fast gates | unknown unknowns | `python3 scripts/gates/redteam_runner.py --gate-cmd "./scripts/gates.sh t1"` | gates PR |
| G13 | vendored skill drift | T1 (offline) + weekly upstream check | s | `scripts/autonomous/` diverging from its pinned upstream tree; undeclared local files there | compares content hashes, not behavior; upstream moves are reported by `skill-sync.yml` (an issue), not by t1 | `python3 scripts/gates/vendor_drift_check.py` (`--remote` compares with `cassandre60/skills`) | gates PR |

## Class → evidence (enforced by reviewer + PR template; CI-wired where noted)

| Class | Required evidence |
|---|---|
| bugfix | regression test failing on base, passing here (G09 script output pasted; EXPECT_PATTERN for the right reason) |
| perf | before/after numbers on the pinned harness + equivalence test vs old implementation |
| refactor | no test files modified (G08 verifies), behavior-equivalence evidence |
| feature | new contracts approved in a dedicated spec-change PR first; reuse existing INVs when sufficient; property tests for new invariants (G05 checks citations, not strength) |
| test-only | names the mutant, invariant, or ratchet it improves |
| dependency | written reason + pubspec.yaml approval (G07); size/startup note |
| docs | no product code; Markdown triggers both workflows (a filtered-out required check blocks the merge forever), but a diff that is only prose under `docs/**` takes the Tests job's docs-only fast lane; root Markdown (SPEC/GATES/QUALITY/TEST_STRATEGY/AGENTS) and `docs/screenshots` goldens still run the full suite |
| gate-change / spec-change | separate PR, no product code, human approval (G07), red-team recall not reduced |

## Blind spots (known, accepted)

- Uncommitted local edits bypass G07/G08 locally; CI judges pushed commits.
- The review-controller fixed-wait helper was replaced by condition polling
  (task 19, #52). Timing failures still need case-specific diagnosis; the old
  blanket pumpAsync-80ms explanation is historical, not a current finding.
- Generated l10n Dart is committed raw with format:false, not hand-formatted.
  Follow CLAUDE; the old formatter workaround is obsolete.
- G05 proves intent coverage, not test quality. G06's expanded catalogue is not
  fully exercised by its scheduler-only wrapper. Blocking mutation,
  crash-consistency and pinned performance gates remain planned (GATES_PLAN).
- G07 sees a label, not human identity. A shared account permits technical
  self-approval; explicit per-item consent is operational (AGENTS §10, Q5).

## Gate health (review quarterly)
| Gate | Rejections | False positives | Flaky reruns | Escapes traced | Action |
|------|-----------|-----------------|--------------|----------------|--------|
| (empty — first review 2027-01) | | | | | |

## Escapes log
| Date | What escaped | Root cause | New gate / invariant / red-team case |
|------|--------------|------------|--------------------------------------|
| 2026-10-02 | Every lichess socket handshake was refused with HTTP 400, so cloud evaluation, study sync and the ping indicator were dead while the suite stayed green | The fake channels key on path alone, so no test could see that the sri was missing from the connect URL, and no fast gate reads a wire format | Regression test shipped in #129. SPEC INV-064 and its test citation added in the escape PR (this row's "not added" stood until G-BASEINV was fixed by #135/#137). Red-team case rt-08 guards the trace link; the wire-behavior link is guarded by the required Tests lane (G04) — t1 recall runs no flutter tests, so a reintroduced wire bug escapes t1 by construction | |
| 2026-10-19 | The v14/v16 canonical rekeys left 67 `srs_review_state` mirrors stranded on the owner's live database — rows keyed to ids that no decision (`id`/`canonicalStateId`) and no knowledge row (`canonicalId`) named any more — while every gate stayed green | No oracle read `srs_review_state` after an upgrade: the rekey tests checked knowledge rows and decisions, the mirror was never asserted to follow, and no fast gate reads cross-table reachability | Regression tests shipped in #239 (`orphaned_review_state_sweep_test.dart`; the two rekey mirror tests). SPEC INV-069, its citations, and red-team case rt-10 added in the escape PR. rt-10 also closed a G08 blind spot found while building it: the tripwire promised "removed test files" yet exited 0 on a whole-file deletion, and now reports one finding per deleted test file. The behaviour link (reverting the mirror carry or the sweep) is guarded by the required Tests lane (G04) — t1 recall runs no flutter tests | |

Adding a row? Follow `docs/ESCAPE_TO_GATE.md` — the row is step 7 of the
escape loop, after the regression test, SPEC invariant, and red-team case.

## Operator checklist (owner actions, not automatable here)

1. Preserve main protection: required contexts are `Tests` and **T1 fast
   gates**, not the workflow name Gates; `strict` and `enforce_admins` are on and
   no reviews are required. Confirm live settings before changing contexts;
   no direct/force pushes.
2. Merge queue (enabled 2026-10-23): main requires a merge queue, so PRs are
   enqueued (`gh pr merge --auto`, or "Merge when ready") instead of merged
   directly. The queue updates the branch itself and re-runs both required
   checks against the batched tree, which is why both workflows trigger on
   `merge_group` and why `gates.yml` resolves its comparison base from the
   group. A queued merge cannot carry a custom `--subject`/`--body-file`, so it
   takes the repository's squash settings instead (currently commit-or-PR title
   and the branch's commit messages) — which is why attribution belongs in the
   **commit trailers**, as the global agent rule requires, and not only in the
   PR body: fleet PR bodies are often opened without a footer, while the commit
   messages carry `Agent:`/`Model:`. Keep `allow_update_branch` on so a behind
   branch can be updated from the UI instead of by hand. Rolling the queue back
   is unchecking "Require merge queue"; no workflow change is needed for that.
3. Protected edits need a dedicated spec-change/gate-change PR, no product code,
   and explicit owner consent for that diff before applying gate-approved.
   The executable protected set is `.gates/protected-paths.txt`.
4. Quarterly: review this file's health tables, tighten ratchets, delete dead gates.

## Committed-branch fast check

Run `./scripts/gates.sh t1` **after committing**, before an authorized push.
G07/G08 read base...HEAD and see no uncommitted changes. Use BASE_REF for the
intended base; an empty diff does not verify work still unstaged.
For protected-file work G07 rejects until explicit owner consent. Only after
consent may APPROVED=1 exercise the remaining local checks. The initial task
request is not approval of the resulting diff.
