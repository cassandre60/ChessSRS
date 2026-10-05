# GATES: the registry of everything that can reject a change

Protected path. If a gate is not in this file, it does not exist.
Local entry point (same as CI): `./scripts/gates.sh [t0|t1|t2]`.

Product suite entry point `./verify` (analyze + full `flutter test`) is owned
by `test.yml` and stays the authority on whether the suite is green. The gates
below do not duplicate it; they enforce what it cannot: referee integrity,
spec coverage of intent, and check strength.

| ID | Gate | Tier | Runtime | Catches | Known blind spots | Local command | Owner |
|----|------|------|---------|---------|-------------------|---------------|-------|
| G01 | format + lint + strict types | T0/T1 | min | style drift, unsafe casts | logic errors | owned by `test.yml` (`dart format` check + `flutter analyze`) | CI |
| G02 | architecture boundary test | T1 | s | domain importing UI/DB/IO, wall-clock reads in scheduling paths | dynamic imports; application-layer network use (import path only, by design) | `fvm flutter test test/gates/domain_boundary_test.dart` | gates PR |
| G03 | banned APIs in core | T0 | s | hidden clocks, layer rot | aliased/bracketed call sites; `Random()` fallback (documented, injected) | `scripts/gates.sh t0` | gates PR |
| G04 | unit + property + widget tests | T1 | min | regressions, invariant breaks | unspecified behavior; load-sensitive review tests (see Blind spots) | owned by `test.yml` | CI |
| G05 | spec traceability | T1 | s | invariants with no test; tests citing unknown IDs | weak tests that cite IDs (needs G06) | `python3 scripts/gates/spec_trace_check.py --spec SPEC.md --tests test` | gates PR |
| G06 | hand-picked mutants (local T2) | T2 | min | tests that do not check scheduler boundaries | unlisted lines; equivalent mutants | `./scripts/gates.sh t2` | contributor |
| G07 | protected paths | T1 | s | referee edits without human approval | uncommitted local edits (CI judges commits) | `python3 scripts/gates/protected_paths_check.py --base origin/main` | owner |
| G08 | test-weakening tripwire | T1 | s | removed asserts/tests, new `skip:`/suppressions in live code | subtle weakening (renamed expectations, padded tolerances); `redteam/` + `scripts/gates/` excluded (inert corpus data / self-naming patterns — both G07-guarded) | `python3 scripts/gates/test_weakening_check.py --base origin/main` (an `Ack-G08: <reason>` commit trailer records reviewed intent; findings still print) | owner |
| G09 | fail-to-pass (bugfix PRs) | T2 | min | tests that cannot fail | wrong-reason failures (use EXPECT_PATTERN); reviewer-enforced until CI-wired | `bash scripts/gates/fail_to_pass_check.sh <base> "<test cmd>"` | reviewer |
| G10 | ratchets (deps, suppressions, skips, tests, domain size) | T1 | s | silent drift | metrics gamed in isolation (kept small on purpose) | `./scripts/gates.sh t1` (collect + compare) | gates PR |
| G11 | dependency + secret posture | T1 | — | unjustified deps | no scanner wired yet; pubspec.yaml is a protected path so every dep change needs approval | reviewer + G07 | owner |
| G12 | red-team corpus recall | T3/nightly + gate-change PRs | min | weak fast gates | unknown unknowns | `python3 scripts/gates/redteam_runner.py --gate-cmd "./scripts/gates.sh t1"` | gates PR |

## Class → evidence (enforced by reviewer + PR template; CI-wired where noted)

| Class | Required evidence |
|---|---|
| bugfix | regression test failing on base, passing here (G09 script output pasted; EXPECT_PATTERN for the right reason) |
| perf | before/after numbers on the pinned harness + equivalence test vs old implementation |
| refactor | no test files modified (G08 verifies), behavior-equivalence evidence |
| feature | SPEC.md updated first in a spec-change PR; property tests per new invariant (G05 verifies) |
| test-only | names the mutant, invariant, or ratchet it improves |
| dependency | written reason + pubspec.yaml approval (G07); size/startup note |
| docs | no code changes (fast CI lane stays cheap) |
| gate-change / spec-change | separate PR, no product code, human approval (G07), red-team recall not reduced |

## Blind spots (known, accepted)

- Uncommitted local edits bypass G07/G08 locally; CI judges pushed commits.
- Several review controller tests are load-sensitive (`pumpAsync` fixed 80ms
  waits): they can flake under CPU contention in wide runs and pass in
  isolation. Re-run the file alone before blaming a change; the real fix is
  condition-polling helpers (see AGENTS.md lessons 2026-09-28).
- `build_runner` rewrites `lib/l10n/*.dart` formatting in fresh worktrees;
  run `dart format lib/l10n/` after codegen and do not commit the churn.
- G05 proves intent coverage, not test quality; G06 covers six scheduler
  boundaries only. Full mutation and crash-consistency are Phase 2.

## Gate health (review quarterly)
| Gate | Rejections | False positives | Flaky reruns | Escapes traced | Action |
|------|-----------|-----------------|--------------|----------------|--------|
| (empty — first review 2027-01) | | | | | |

## Escapes log
| Date | What escaped | Root cause | New gate / invariant / red-team case |
|------|--------------|------------|--------------------------------------|
| (none recorded since gates introduced 2026-10-01) | | |
| 2026-10-02 | Every lichess socket handshake was refused with HTTP 400, so cloud evaluation, study sync and the ping indicator were dead while the suite stayed green | The fake channels key on path alone, so no test could see that the sri was missing from the connect URL, and no fast gate reads a wire format | Regression test shipped in #129. SPEC INV-064 and its test citation added in the escape PR (this row's "not added" stood until G-BASEINV was fixed by #135/#137). Red-team case rt-08 guards the trace link; the wire-behavior link is guarded by the required Tests lane (G04) — t1 recall runs no flutter tests, so a reintroduced wire bug escapes t1 by construction | |

Adding a row? Follow `docs/ESCAPE_TO_GATE.md` — the row is step 7 of the
escape loop, after the regression test, SPEC invariant, and red-team case.

## Operator checklist (owner actions, not automatable here)

1. GitHub branch protection on `main`: required status checks (`Tests`,
   `Gates`), required human review, no direct pushes, no force pushes.
2. Confirm SPEC.md T0/T1 invariants by merging (they transcribe QUALITY.md).
3. Quarterly: review this file's health tables, tighten ratchets, delete dead gates.
