# TASK-07 — CI tiering / tags / caching / conditional build_runner

> **Pick this up in a fresh worktree.** `git worktree add ../chesssrs-ci-tier -b feat/ci-tiering origin/main` then `fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs`.

## Goal

Cut **30–60s** off `Tests` (~6:56 wall, `build_runner` ~64s within it) via **tags, pub/cache caching, and conditional `build_runner`**, without duplicating check names (the collision closed in #95/#107).

## Why

Today `Tests` pays `pub get` + `build_runner` + `analyze` + `flutter test` (291s test within 6:56 wall, CI run 39118936674 per `baseline.md` §2). Docs-only PRs pay it anyway because branch protection requires the plain `Tests` check name. The redesign projects **~4:30 wall** once tiering + caching + conditional build_runner land with the `dart test` lane (task 01).

## Read before editing

- `docs/test-audit/baseline.md` §2 (CI timings + overhead split) and `redesign.md` §7 (tiering/sharding/tags/caching/codegen/**pumpAndSettle**).
- `.github/workflows/test.yml` (current `Tests` job, `unit-test` name) and `.github/workflows/gates.yml` (T1 fast gates, `labeled` event note) — do **not** rename the reported check names without updating branch protection (`gh api` check below).
- `AGENTS.md` §Isolation (worktree rule) + `CLAUDE.md` (publishing).
- `.gates/protected-paths.txt` — `.github/**` and `.gates/*` are protected; this PR needs `gate-approved`.

## What to do (small, targeted — keep the PR green)

1. **Add `dart_test.yaml` tags.** Define (at least) `unit`, `widget`, `integration`, `perf`. Example:
   ```yaml
   tags:
     unit:   { description: "pure / no binding" }
     widget: { description: "flutter_test + widget binding" }
     integration: { description: "slivers needing db/network" }
     perf: { description: "benchmarks, noisy" }
   ```
   Tag existing `test/**` files with `@Tag('unit')` / `@Tag('widget')` where obvious — but you may defer tagging to fast-path files only and do the rest incrementally (just document that choice). TASK-01's `dart` lane should be `@Tag('unit')` if it ships.
2. **Tier `test.yml`.** In the `Tests` workflow:
   - **Tier A (fast PR gate):** `flutter test --tags unit --reporter json` (+ `dart test --tags unit` if TASK-01 landed). Keep the reported job name as **`Tests`** for branch protection — do not add a second reported name like "Tests (fast)" that would collide or require a protection update. If you must add a second job, make it non-required or document the protection change in the PR body.
   - **Tier B (main + nightly):** `flutter test` (full) + `manual_mutation_runner` (T2) + long property runs. Gate it with `if: github.ref == 'refs/heads/main' || github.event_name == 'schedule'`.
3. **Cache `pub` + `build_runner` outputs.** Add `actions/cache` (or the Flutter action's cache) keyed on `pubspec.lock` hash:
   - `~/.pub-cache` (or the action's pub cache),
   - `.dart_tool/build/` for `build_runner` outputs.
   The Flutter action (`subosito/flutter-action@v2`) already has `cache: true` — see if that suffices before adding a second cache. Measure cold vs warm in the PR body.
4. **Conditional `build_runner`.** Skip `dart run build_runner build` when the PR diff touches **only** `test/**` / `docs/**` / `*.md` (nothing in `lib/**`). GitHub's `paths` filter is already on `test.yml` but the job's steps run unconditionally — add an `if: steps.changed_lib.outputs.any == 'true'` using `dorny/paths-filter@v3` or similar. This saves ~64s on test-only PRs that currently re-run build_runner.
5. **Gate health hygiene.** While you are in these files, confirm:
   - `Tests` and `T1 fast gates` are the two required checks and neither collides with `Docs check` (see `gates.yml` comment on `labeled`).
   - `gates.sh t2`'s hard-wired `test/domain/scheduler_test.dart` is aligned with the `dart` lane if TASK-01 landed (update the `--test-cmd` if needed).

## Done when

- [ ] `dart_test.yaml` exists with `unit`/`widget`/`integration`/`perf` tags.
- [ ] `test.yml` has a tiered job that stays reported as `Tests`, plus pub/build cache keyed on `pubspec.lock` SHA, and a conditional `build_runner` that skips on `test/**`-only diffs.
- [ ] Docs-only and `test/**`-only PRs show ~64s less wall time than the baseline (run 39118936674) — paste the before/after step timings from the CI log into the PR body.
- [ ] `verify` still passes locally on `HEAD` (or say "Tests lane green on CI" if you only touched workflows).

## Not to do

- Do not shard (`--shard-index`) in this PR — redesign defers it until the `dart test` lane already halves time.
- Do not make the new tier a required check under a new name without updating branch protection (G-CIREPORT trap).
- Do not touch `TEST_STRATEGY.md` (TASK-08).

## Evidence

- Per-check CI timings: `gh run view <id> --json jobs` before/after (or the `Tests` log lines for `Code generation` / `Verify formatting` / `Analyze` / `Run unit tests`).
- `gh api repos/cassandre60/ChessSRS/branches/main/protection/required_status_checks` if you changed any reported name.
- Local `fvm flutter analyze` on touched workflow-adjacent files (if any) + `python3 scripts/gates/spec_trace_check.py --spec SPEC.md --tests test --base-spec …` if you added tags near `SPEC`-cited files.

---
Source: `docs/test-audit/baseline.md` §2 + §7, `redesign.md` §7, `GATES.md` Blind spots, `GATES_PLAN.md` §4 #9–11.
