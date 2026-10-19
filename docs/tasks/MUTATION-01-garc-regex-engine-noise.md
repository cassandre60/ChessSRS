# MUTATION-01 — regex mutation engine on `graph_aware_review_coordinator.dart`

**Date:** 2026-10-18
**Stream:** 1 (Mutation Testing & Test-Gap Elimination)
**Class:** docs-only (no production code, no test code)
**Target:** `lib/src/domain/graph_aware_review_coordinator.dart`
**Content hash under test:** `git hash-object` = `b11aeacc6fa00d5e8c4b55aa62535fcee465a794`,
sha256 = `eabdb38c426321d539d970a54fed98266be38b80f8c447abbe6e60a993392c8c`

## Headline

**Zero surviving mutants in the sanctioned 20-mutant window. No test gaps found, so no tests
were added.** The window itself was 85% uncompilable noise (17 of 20), so the engine's reported
`100.0%` kill rate is an artefact of only 3 mutants ever reaching the suite. The value of this
run is the instrument analysis below, which applies to the five remaining Stream 1 targets.

## Engine settings used

```bash
python3 scripts/autonomous/mutation_engine.py \
  --source lib/src/domain/graph_aware_review_coordinator.dart \
  --test-cmd "fvm flutter test test/domain/graph_aware_review_coordinator_test.dart" \
  --max-mutants 20 \
  --timeout 240 \
  --output-issue docs/tasks/mutant_issue.md \
  --output-json /tmp/opencode/garc_mutants.json
```

Two deliberate deviations from the catalogue's copy-paste command:

- `--timeout 240` instead of the default `60`. The clean baseline for this single file measured
  **22.7s** wall on an otherwise idle machine, so the default left only a 2.6x margin. A timeout is
  scored by `subprocess.TimeoutExpired` as return code 1 with empty stdout/stderr, which
  `_is_compile_failure` reads as false and the engine therefore records as **killed**. Under CPU
  contention a 60s cap silently converts timeouts into kills and inflates the kill rate — the exact
  false-positive class `GATES_PLAN.md` row 9 has to clear before this tool is ever promoted to
  blocking CI. Every run in this file completed in under 8s at `--timeout 240`, so the raise cost
  nothing and removed the risk.
- `--output-json` to a path outside the repository, to capture the full machine-readable result.
  `--output-issue` produces nothing when there are no survivors (`mutation_engine.py:302` gates it
  on `and survived`), which is why `docs/tasks/mutant_issue.md` does not exist for this run.

`--max-mutants` was left at 20, and the engine was run exactly once.

## Totals

| Outcome | Count | Share |
|---|---|---|
| Killed by the suite | 3 | 15% |
| Survived | 0 | 0% |
| Uncompilable (invalid) | 17 | 85% |
| Candidates generated but not evaluated (window cut) | 35 | — |
| Engine-reported kill rate | 100.0% | 3 killed / 3 killable |

The rate is technically correct and practically meaningless: 3 of 55 candidates were both
compilable and inside the window.

## Per-mutant table

Kill evidence was captured by re-applying each mutation by hand, running the single test file, and
restoring via `git checkout -- lib/src/domain/graph_aware_review_coordinator.dart` (with
`git diff --exit-code -- lib/` verified clean after every restore).

| # | Line | Mutation | Verdict | Evidence |
|---|---|---|---|---|
| 1 | 16 | `hasCanonicalIdentity = false` -> `true` | **killed** | `legacy occurrence identity still follows the single-move map` |
| 2 | 45 | `List<String>` -> `List <= String>` | invalid | compile: `Operator '<=' should have exactly one parameter` |
| 3 | 45 | `List<String>` -> `List<String >=` | invalid | compile: `Variables must be declared using the keywords 'const', 'final', 'var' or a type name` |
| 4 | 92 | `List<ReviewState>` -> `List <= ReviewState>` | invalid | compile (generic parameter) |
| 5 | 92 | `List<ReviewState>` -> `List<ReviewState >=` | invalid | compile (generic parameter) |
| 6 | 107 | `Map<String, DateTime>` -> `Map <= String, DateTime>` | invalid | compile (generic parameter) |
| 7 | 116 | `Map<String, DateTime>` -> `Map <= String, DateTime>` | invalid | compile (generic parameter) |
| 8 | 116 | `Map<String, DateTime>` -> `Map<String, DateTime >=` | invalid | compile (generic parameter) |
| 9 | 135 | `Map<String, DateTime>` -> `Map <= String, DateTime>` | invalid | compile (generic parameter) |
| 10 | 135 | `Map<String, DateTime>.of` -> `Map <= String, DateTime>.of` | invalid | compile (generic parameter) |
| 11 | 135 | `Map<String, DateTime>` -> `Map<String, DateTime >=` | invalid | compile (generic parameter) |
| 12 | 135 | `DateTime>.of` -> `DateTime >= .of` | invalid | compile (generic parameter) |
| 13 | 138 | `Map<String, DateTime> snapshot` -> `Map <= String, DateTime>` | invalid | compile (generic parameter) |
| 14 | 138 | `Map<String, DateTime> snapshot` -> `...DateTime >= snapshot` | invalid | compile (generic parameter) |
| 15 | 155 | `List<GraphNode> siblings` -> `List <= GraphNode>` | invalid | compile (generic parameter) |
| 16 | 155 | `List<GraphNode> siblings` -> `List<GraphNode >= siblings` | invalid | compile (generic parameter) |
| 17 | 165 | `result == ReviewResult.incorrect` -> `!=` | **killed** | 4 tests: `lapse contagion survives a degenerate tau instead of crashing the session`, `recordActiveReview on incorrect move propagates lapse contagion to descendants`, `INV-027 lapse contagion applies the full lambda0 haircut at depth 1`, `recordActiveReview couples difficulty on confusable sibling moves` |
| 18 | 170 | `playedMoveUci != null && ...` -> `== null && ...` | invalid | compile: `graph_aware_review_coordinator.dart:171:35: Error: The argument type 'String?' can't be assigned to the parameter type 'String'` |
| 19 | 170 | `&&` -> `\|\|` on the coupling gate | invalid | compile: same `String?` -> `String` promotion error (no promotion inside `\|\|`) |
| 20 | 170 | `siblings.isNotEmpty` -> `siblings.isEmpty` | **killed** | `recordActiveReview couples difficulty on confusable sibling moves` |

## Triage

**Killed (3) — genuine coverage, no action.** Each is killed by an assertion that names the
behaviour rather than the implementation: the legacy-identity test distinguishes `hasCanonicalIdentity`
defaulting to false, the contagion tests assert the haircut actually lands on descendants of an
*incorrect* answer, and the coupling test asserts the bump lands on the matching sibling. Note that
mutant 17 is killed from the **positive** direction (an incorrect answer must propagate), not from a
"correct answers propagate nothing" assertion — the inverse-gate blindspot does not exist here.

**Uncompilable / invalid (17) — two distinct engine defects, not test gaps.**

- *15 mutants are the `<` / `>` rules matching Dart generic type parameters.* Every `List<X>` and
  `Map<K, V>` in the file produced a candidate: `List<String>` -> `List <= String>`. Dart reads the
  result as an operator declaration, and the compiler rejects it. These are not mutants of the
  program; they are mutants of the type annotation syntax. Because `generate_mutations` skips only
  comment/import/quote-prefixed lines and not type positions, a filter as cheap as "skip a line whose
  stripped text starts with `List<`, `Map<`, `Set<`, `Iterable<`, or contains `<` between two type
  names" would remove all 15 before a single test process starts.
- *2 mutants break null-safety flow promotion.* Inverting `!= null` to `== null`, or swapping `&&`
  for `||`, removes the promotion of the `String? playedMoveUci` to `String`, so the call on the
  next line fails to compile. Also not program mutants.

Neither class carries signal, and the engine correctly refuses to count them as killed — that part
of the design is sound and is why the summary distinguishes them.

## Why this run is thin, and the fix to make before the next target

`generate_mutations` is first-N in **file order**, so the window is spent on whatever appears
earliest. In this file the first behaviour-bearing expression is on line 165; everything before it
is generic annotations. Fifteen of the twenty slots went to type syntax.

**The evaluated window therefore covers only lines 16, 45, 92, 107, 116, 135, 138, 155, 165 and 170.**
The lines carrying the file's actual invariants — 191-289, where `recordAutoTraversalExposure`'s
guards, the contagion depth cut, `_pullDueForward`, the sibling move filter and `_isSameCalendarDay`
live — were **not evaluated at all**. The 35 unevaluated candidates are enumerated in the run's
generated list and include, for the record: `previous == null` (191), `previous.stability <= 0` (192),
`lastReviewedAt != null` (198), `lastExposed != null` (202), `remainingMs > 0` (209),
`depth > params.maxContagionDepth` (227), the `(depth - 1)` exponent (238),
`childState == null || childState.stability <= 0` (243), `depth + 1` (258),
`sib.expectedMoveUci != playedMoveUci` (276) and all three `_isSameCalendarDay` comparisons (289).

Recommendation, in priority order, for whoever owns the tool:

1. Suppress candidates whose `<`/`>` sits inside a generic type argument list, and candidates inside
   a `!= null` / `== null` comparison whose operand is passed to a non-nullable parameter.
2. Then re-run with `--max-mutants 20` on this same file: the window will land on real behaviour, and
   the remaining 35 candidates are where this file's remaining coverage risk actually lives.
3. Only then apply the tool to the other five Stream 1 targets, all of which are generic-heavy Dart
   domain files and will lose the same ~75% of their budget to the same noise.

The tool change itself is deliberately **not** made here: a breaker must not retune the instrument
that produces its own evidence, and `GATES_PLAN.md` row 9 requires two green runs without false
positives before promotion anyway.

## Ledger hygiene finding (needs an owner decision, not a fix from this stream)

The Stream 1 row for this file, added by PR #202, records `Content Hash: 9e2c9e480`. That value is
**not a content hash** — it is the abbreviated commit id of `9e2c9e480 refactor(review): remove dead
parameters, duplicated comments, and a bare catch (#182)`, the last commit to *touch* the file. The
ledger's own dedup preamble warns against exactly this substitution:

> `git log -- <file>` is the *last commit touching* the file, not the content.

Consequence: the dedup rule ("if the content hash has not changed, do not repeat work") cannot be
evaluated against the #202 row at all, because the recorded value is not comparable to
`git hash-object` output. This run's target content is byte-identical to what #202 audited
(`b11aeacc6fa00d5e8c4b55aa62535fcee465a794`), so this campaign **re-ran work the ledger marks
COMPLETED**. It produced nothing new, which is the reassuring outcome — but a future agent trusting
that row, or an agent sent to this file for the same reason I was, would have no way to notice.
Suggested owner decision: restate the #202 row's hash as a `git hash-object` value so the dedup rule
is machine-checkable. Not changed here — the ledger row is bookkeeping, but restating another
agent's historical hash is an owner's call, not a breaker's.

## Stream 2 handoff (observed, not actioned)

`recordActiveReview on correct move updates primary state without side effects` asserts
`expect(result.sideEffectStates, isEmpty)` on a graph with **no descendants and no siblings** set
up. Propagation produces nothing on an empty graph whichever branch runs, so that assertion is
vacuous on the propagation axis — it can only fail if the scheduler stops scheduling. The propagation
gate is in fact covered (mutant 17 above), so this is a vacuity observation, not a gap: the assertion
should either be paired with a populated graph or narrowed to what it is really checking. Handing
this to Stream 2 (`test/suite-audit`) rather than writing it here, since Stream 1 only writes tests
against a surviving mutant.

## Honest status

- Ran: one engine pass (20 mutants + baseline, one targeted test file per mutant, source restored
  after each); clean baseline of the file (16/16); kill evidence re-verified by hand for all 3
  killed mutants; compile evidence captured for both uncompilable classes; `lib/` verified
  byte-identical to `origin/main` after every restore.
- Not run / unverified: the 35 candidates past the window; full suite and CI `Tests` (this is a
  docs-only PR and will report no checks at all, by design); no runtime or visual validation applies
  (no user-visible change).
- Tests added: none. There were no surviving mutants, so there is nothing a new test could be proven
  red against. Writing tests to fill the PR would be fake work.
