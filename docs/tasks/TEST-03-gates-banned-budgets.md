# TASK-03 — Banned-patterns + test-budgets gates

> **Pick this up in a fresh worktree.** `git worktree add ../chesssrs-test-gates -b feat/test-gates origin/main` then `fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs`.

## Goal

Make "CI time going down, not up" and "no sleeping/real-delay unit tests" mechanically enforced, not just documented.

## Why

Baseline has **53 `pumpAndSettle`**, **46 `Future.delayed`/`sleep`/`pump(Duration)`**, and **6 `DateTime.now()`** — mostly legitimate (HTTP mocking, `perf` wall-clock, `sqflite_common_ffi`), but a future weak agent can add a 30s settle with no signal. No gate fails on `sleep` or real delays in unit tests, and no per-test runtime budget exists (audit blind spot #10).

## What to do

### 3A — `banned_patterns_check.py` (new T1 gate)

1. Read `scripts/gates/banned_apis_check.py` as a template (allowed/forbidden globs, `--config` json, exit 1 on violation). Create `scripts/gates/banned_patterns_check.py` that fails on:
   - any `test(` / `testWidgets(` block with **zero** `expect`/`check`/`expectLater` (assertion-less test),
   - `sleep(` or bare `Future.delayed(` outside `test/perf/` and `test/**/fake*`,
   - `DateTime.now()` outside an allowlist (today only `test/perf/**`, `test/model/log/**` — 4 of the 6 are expected; the allowlist lives in a json file, not hardcoded).
   Use `rg`-class regexes with explicit allowlist file; start strict and allowlist liberally.
2. To judge the allowance, run `rg -n "DateTime\.now\(\)|Future\.delayed|sleep\(" test --glob "*_test.dart"` and classify the 6 + 46 hits before choosing the allowlist.
3. The script must run in <1s on this tree and exit 0 on `HEAD`.

### 3B — `test_budgets.py` (new gate, initially T2)

1. This gate **must not be blocking CI on this PR.** Wire it as **T2 opt-in** first (or not at all in `gates.yml`) — `GATES_PLAN.md` says "an unverified blocking job risks red CI". The enforcement tier promotes only after it has run green twice.
2. Parse `flutter test --reporter=json` (or `dart test --reporter=json` for the `dart` lane) timing. Simplest: run `fvm flutter test --reporter json > /tmp/timing.json` on a single `test/domain/` file locally (AGENTS.md §3.1 allows one file, not the whole suite), then design the budget checker against that shape. For full-suite timing, **use a CI artifact** from the `Tests` run (or ask the orchestrator to trigger one via `gh workflow run`) — do not run the whole suite locally.
3. Proposed budgets (from `redesign.md` §2):
   - per-test: **2s widget / 200ms unit** (`dart test` lane),
   - per-tier: **<30s pure / <120s flutter-unit+widget / <60s integration** (whole-suite parallel), total PR gate **<180s** test execution (vs today's ~291s).
   Start with these numbers even if the CI run exceeds them — then **calibrate** from the CI `timing.json` artifact rather than guessing. Record the calibration command in the PR body.
4. Implement `--tier-budget` / `--per-test-budget` flags and a `--timing` input (json file path). Exit 0 when under budget, 1 when over, 2 on setup error. Include a human-readable "top N slowest tests" printout (the baseline promised "20 slowest" — this is that report).

### Wiring (if you wire it — optional this PR)

- If you add the scripts but leave `gates.yml` unwired, state "not yet wired — needs two green runs before promotion" in the PR body and leave a `TODO(GATES_PLAN #11)` comment in the scripts. That is the preferred path for this task.
- If you do wire `banned_patterns_check.py` as **T1**, add it to `scripts/gates.sh t1` and to the `T1 fast gates` job in `.github/workflows/gates.yml`. That makes it a **protected-path PR** (`scripts/gates/*`, `.github/**`, `.gates/*` are protected) — it needs `gate-approved`.

## Done when

- [ ] `scripts/gates/banned_patterns_check.py` exists, documented, and passes on `HEAD` (0 assertion-less tests today; the allowlist covers the 4 expected `DateTime.now` hits).
- [ ] `scripts/gates/test_budgets.py` exists and, given a `timing.json` from a `test/domain` run, reports per-test + per-tier vs budget and exits 0.
- [ ] `GATES.md` updated if you wire either as T1 (add row + blind-spot note); `GATES_PLAN.md` gap table updated if you wire T2.
- [ ] Commit message lists the `rg` hit counts and the targeted timing command you ran.

## Not to do

- Do not tighten `TEST_STRATEGY.md` (TASK-08).
- Do not expand mutants (TASK-02).
- Do not bulk-edit `test/**/*_test.dart` to fix existing `pumpAndSettle` calls — just gate future ones; bulk fixes belong in TASK-04 with mutation proof.
- Do not make `test_budgets.py` block CI without the two-green-run calibration (GATES_PLAN.md).

## Evidence

- `python3 scripts/gates/banned_patterns_check.py --root .` output (or with `--config`).
- `python3 scripts/gates/test_budgets.py --timing /tmp/timing.json --tier-budget '{"pure":30,"flutter":120}'` output (or your chosen invocation).

---
Source: `docs/test-audit/audit-report.md` §Static smells + §10 Wall-clock, `redesign.md` §8, `GATES.md` G03/G10.
