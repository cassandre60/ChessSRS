# Before / after — ChessSRS test-audit branch `test-audit` (2026-10-18)

> **Status: Read-only evidence.** Refresh is owned by the capstone agent that closes the last autonomous stream (see `docs/test-audit/PLAN.md`).

Same machine/method as `baseline.md`. "Before" is `main` at `a9fbfe0fb`
(before this branch). "After" is this branch at HEAD. CI timings are from
`Tests` workflow run `39118936674` (before) vs same workflow after (when CI
runs). Numbers that could not be re-measured locally are noted.

## Suite size

| Metric | Before | After | Delta | How |
|---|---|---|---|---|
| `_test.dart` files | 182 | **183** | +1 | `find test -name '*_test.dart' | wc -l` |
| Test declarations (`test(`+`testWidgets(`) | 1,883 (`rg -c`) / 1886 (ratchet) | **1,888** | +5 | new `scheduler_properties_test.dart` contributes 5 |
| Lines in `_test.dart` | 57,380 | **~57,545** | +165 | one new file (formatted) |
| Kind: widget / flutter-unit / pure | 66 / 116 / 0 | 66 / 117 / 0 | +1 flutter-unit | new file imports `flutter_test` for matchers |
| SRS pool (`domain`+`import`+`persistence`+`review`) | 30 files | 31 files | +1 (`domain`) | new file under `domain` |
| `expect(` calls | 5,426 | **~5,440** | +~14 | grep estimate |

Ratchet `test_declarations`: baseline 1,886 → no change applied on this
branch (would be a protected-path edit requiring `gate-approved`). The
T1 ratchet checks `current >= baseline`, so +5 is compliant. A tightening
to the new floor should be a follow-up `gate-approved` commit.

## Wall-clock

| Tier | Before (CI) | After (projected) | Method |
|---|---|---|---|
| `build_runner` | ~64 s | ~64 s (cached: --) | `test.yml` step timing |
| `analyze` | ~35 s | ~35 s | same |
| `flutter test` | ~291 s | ~292 s (+1 s for the new file, ~15ms within it + overhead) | local: single-file probe ~2 s wall incl. compile; CI delta not re-measured on this branch pending a `Tests` run |
| **Total wall** | ~6:56 | **~6:57** (no saving this PR) | stacking above |

The redesign targets **~4:30** after the `dart test` lane + tiering + caching + pumpAndSettle cap (see `redesign.md`). This PR is **not** that saving — it is the audit + one property test + the docs that let the next PR do it cleanly.

## Signal

| Signal | Before | After |
|---|---|---|
| Mutation score (`.gates/mutants.json`, 6 on `scheduler.dart`) | 6/6 = 100% | 6/6 = 100% (re-checked with `scheduler_test` + `scheduler_properties` co-run) |
| Mutants outside `scheduler.dart` | 0 | 0 (corpus not expanded this PR) |
| Property tests | 0 | 1 file, 5 tests, ~15ms |
| New mutants killed by property tests alone | — | All 6 still killed by existing tests; property tests are additive for future mutants (cap-removal, double-count, negation all loop-checked) |
| Coverage split by directory | not instrumented | not instrumented (needs CI `lcov` artifact) |
| Unique kill / deletion proof | none | none (per-task rule: no deletion without evidence; none proposed) |

## What got worse

- Nothing correctness-wise. One new file adds ~1 s CI overhead (amortized). The risk of a future weak agent adding an un-bounded `pumpAndSettle` or a `sleep` remains until the `banned_patterns` gate is wired (deferred).

## What could NOT be measured on this branch

Same gaps as `baseline.md §7`: per-test/per-file timing, 3× flake sweep, and
`lcov` line/branch split require a full `flutter test --reporter=json` +
`--coverage` run (~5 min, saturates the machine) or a CI run. Budget rule
(`AGENTS.md §3.1`) deferred those to CI. The branch is green by targeted
checks (`flutter test` on the touched file, `analyze`, mutation re-check)
rather than a local full-suite run.

## Files shipped (vs proposed)

- **Shipped:** `docs/test-audit/baseline.md`, `inventory.csv`, `audit-report.md`, `redesign.md`, `final.md`; `test/domain/scheduler_properties_test.dart`.
- **Proposed in `redesign.md` but not shipped:** `scripts/gates/banned_patterns_check.py`, `scripts/gates/test_budgets.py`, `dart_test.yaml`, tag tiering, crash-consistency/fault-injection, differential FSRS vectors, table-driven merges, sharding. Each is spelled out with method and why it was deferred (keeps this branch small/green and avoids protected-path edits without `gate-approved`).
- **Updated `TEST_STRATEGY.md` pyramid/budgets/rules:** drafted in `redesign.md` but not committed as a doc edit because `TEST_STRATEGY.md` is a protected path. The doc change belongs in the same `gate-approved` PR that wires the new gates (avoids two protected-path PRs).
- **Production code `refactor(testability)` seams:** none needed — `domain/` is already pure (zero `flutter` imports verified), `Clock`/`Random` seams exist, and the two tiny seams (`pgn_offload` env check, `sqlite_study_repository` wrapper) are documented for a follow-up `refactor(testability)` commit.

## Repro

```
# size
find test -name '*_test.dart' | wc -l
rg -c "^\s*(test|testWidgets)\(" test --glob "*.dart" | awk -F: '{s+=$NF} END{print s}'
wc -l test/domain/scheduler_properties_test.dart

# targeted check (the local loop on this branch)
fvm flutter test test/domain/scheduler_properties_test.dart --no-pub
fvm flutter analyze test/domain/scheduler_properties_test.dart

# mutation
python3 scripts/gates/manual_mutation_runner.py \
  --mutants .gates/mutants.json \
  --test-cmd "fvm flutter test test/domain/scheduler_test.dart test/domain/scheduler_properties_test.dart --no-pub" \
  --force
```
