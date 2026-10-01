# GATES_PLAN: making acceptance expensive to fake

Protected path. Status: **proposed** (this PR is Phase 1).

## 1. Context

Local-first chess repertoire + SRS trainer on the Lichess Mobile fork (GPL-3.0).
Beta-phase product; owner is the beta tester. One wrong SRS write or one lossy
import silently destroys months of the owner's memorization work, so persistence
and import are R0, scheduling/review logic is R1, UI glue is R2.

- Stack: Flutter 3.47.3 (FVM), dartchess (sole chess engine), sqflite, Riverpod 3.x.
- Current maturity: **L3** (specs exist as prose in QUALITY.md, strict analyzer,
  ~1500 tests, CI required on code paths, deterministic Clock/Random seams).
- Missing (verified this session): no CODEOWNERS, no PR template, no protected
  paths, no banned-API/boundary enforcement, no spec↔test traceability
  (zero `INV-` citations anywhere), no ratchets, no mutation/fail-to-pass
  wiring, no red-team corpus. `assess_repo.py` agrees: L3, no mutation/fuzz/
  benchmarks/codeowners/gates_dir.
- Baseline metrics (measured 2026-10-01, recorded in
  `.gates/ratchet-baseline.json`): 65 direct deps, 18 analyzer suppressions
  (excl. generated l10n), 11 `skip:` (all env-gated screenshot captures),
  ~1507 test declarations.

## 2. Risk tiers

| Tier | Modules | Gate expectation |
|---|---|---|
| R0 | `lib/src/persistence/`, `lib/src/db/`, `lib/src/import/` | SPEC T0 invariants, boundary + trace + tripwire on every PR, migration tests, hand-picked mutants (local T2) |
| R1 | `lib/src/domain/` (schedulers, coordinator, review session) | SPEC T1 invariants, purity/clock gates, hand-picked mutants (local T2) |
| R2 | `lib/src/view/review/`, `lib/src/design/`, auth/network glue | strict types, behavior + a11y tests, tripwire |
| R3 | generated (`*.freezed.dart`, `*.g.dart`, `lib/l10n/`) | excluded from metrics and scans |

## 3. Irreversible decisions (frozen by SPEC v1, not changed by this PR)

SQLite schema + migrations, 4-field-FEN position identity, `canonicalKey`
SHA-1 scheme, UUID entity IDs, PGN export format. SPEC.md records them as
invariants; changing any of them is a spec-change PR with human approval.

## 4. Gap table (cost S/M/L, leverage S/M/L, order)

| # | Gate | Catches | Cost | Leverage | Order |
|---|---|---|---|---|---|
| 1 | CODEOWNERS + protected-paths + PR template (Class line) | referee edits without approval | S | L | this PR |
| 2 | Banned-API boundary gate (domain purity, Clock rule) + Dart boundary test | layer rot, hidden clocks | S | L | this PR |
| 3 | SPEC.md (numbered INVs) + trace check | invariants with no test | M | L | this PR |
| 4 | Test-weakening tripwire (Dart-tuned) | gutted tests, new skips/suppressions | S | M | this PR |
| 5 | Ratchets (deps, suppressions, skips, test count) at today's values | silent drift | S | M | this PR |
| 6 | Red-team seed corpus, 7 cases, recall 100% on T1 | weak fast gates | S | M | this PR |
| 7 | `scripts/gates.sh` single entry point + gates.yml (PR fast lane, nightly recall) | CI/local divergence | S | M | this PR |
| 8 | `.gates/mutants.json` + fail-to-pass script (local T2, reviewer-enforced) | tests that cannot fail | S | M | this PR (wiring only) |
| 9 | Diff-scoped mutation as blocking CI | surviving mutants on changed lines | M | L | later (needs runner proving) |
| 10 | Crash-consistency (kill at write boundaries) + fuzz PGN import | data loss, parser crashes | M | M | later (nightly) |
| 11 | Perf budgets on pinned runner (import throughput, queue build) | regressions below 16ms budget | M | S | later |

## 5. Phases

- **Phase 1 (this PR):** rows 1–8. Exit: `gates.sh t1` green on clean tree,
  red-team recall 7/7, `flutter analyze` clean on touched files, one new
  boundary test passing, CI's PR lane + nightly recall wired.
- **Phase 2 (later):** row 9 — promote mutation to blocking after it runs
  green twice without false positives. Row 10–11 go to nightly first.
- **Phase 3 (quarterly):** gate-health review in GATES.md; delete gates that
  stop paying; every escape becomes a corpus case + invariant.

## 6. What I chose NOT to do, and why

- **No blocking mutation CI.** No mature Dart mutation tool is wired here;
  an unverified blocking job risks red CI on every PR. Mutants ship as
  local-opt-in (`gates.sh t2`) with a documented promotion rule instead.
- **No `Random()` ban.** The single `Random()` in `review_session.dart` is an
  injectable-default fallback, seeded in tests; banning it would force a
  lib edit inside a gate PR. Determinism is enforced by injection + tests.
- **No LOC diet ratchet.** LOC punishes features; dependency/suppression/skip
  counts are the drift that matters. LOC is recorded with a wide bloat
  tolerance instead.
- **No engine-isolation or shape-spoiler invariants in SPEC v1.** No covering
  tests exist yet; SPEC admits only invariants with live oracles. Both are
  listed as SPEC candidates for the next feature PR in that area.
- **No `flutter analyze --fatal-warnings` in gates.yml.** Warning policy is
  already owned by `test.yml` + repo convention; duplicating it risks
  conflicting definitions of "passing".
- **No changes to `lib/`, product behavior, schemas, or public formats.**
  Zero product code in a gate-change PR, per the evidence contract.

## 7. Risks

- Tripwire false positives on Dart idioms (tuned: `skip:` named-arg only,
  not `.skip()` collection calls) — watch the first PRs, retune openly.
- `test.yml` and `gates.yml` are two CI definitions; `gates.sh` + GATES.md
  keep them from diverging silently. Long term they should merge.
- Gate maintenance is real work: quarterly review is calendared in GATES.md.
