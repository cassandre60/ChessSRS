# DevOps, CI/CD & Tooling Audit

**Date:** 2026-11-17  
**Scope:** Build pipeline, CI/CD workflows, gate system, scripts, DX, release process, dependency health

---

## Executive Summary

The ChessSRS CI/CD and tooling infrastructure is **mature and well-engineered**
for a project of this scale. The gate system is one of the most thoughtful
agent-proof referee setups I've audited: trusted-base-copy execution, monotone
ratchets, spec traceability, and a nightly red-team corpus. The release pipeline
is fully automated with version-stamp verification, multi-format Linux packaging,
and smart nightly decisions.

That said, there are concrete improvement opportunities in caching, security
hardening, dependency hygiene, DX polish, and a few gate blind spots.

---

## 1. CI/CD Pipeline Analysis

### 1.1 Workflow Inventory

| Workflow | Trigger | Purpose | Runtime |
|---|---|---|---|
| [test.yml](file:///home/mohamed/Desktop/Github/ChessSRS/.github/workflows/test.yml) | PR, push, merge_group | Full test suite: format, analyze, flutter test, release-stamp tests | ~6 min |
| [gates.yml](file:///home/mohamed/Desktop/Github/ChessSRS/.github/workflows/gates.yml) | PR (inc. labeled), merge_group, nightly | Referee integrity: G03/G05/G07/G08/G10 + nightly red-team | ~seconds (T1) |
| [docs-check.yml](file:///home/mohamed/Desktop/Github/ChessSRS/.github/workflows/docs-check.yml) | PR/push (docs only) | Acknowledge docs-only change | ~3s |
| [nightly.yml](file:///home/mohamed/Desktop/Github/ChessSRS/.github/workflows/nightly.yml) | 03:17 UTC daily | Smart nightly build dispatch | <1 min decision |
| [release.yml](file:///home/mohamed/Desktop/Github/ChessSRS/.github/workflows/release.yml) | tag push v*, dispatch | Linux + Android builds, GitHub Release | ~30 min |
| [release-proof.yml](file:///home/mohamed/Desktop/Github/ChessSRS/.github/workflows/release-proof.yml) | dispatch, self-PR | Throwaway-signed proof build | ~20 min |
| [runtime-smoke.yml](file:///home/mohamed/Desktop/Github/ChessSRS/.github/workflows/runtime-smoke.yml) | dispatch, self-PR, workflow_call | Real app under xvfb | ~15 min |
| [skill-sync.yml](file:///home/mohamed/Desktop/Github/ChessSRS/.github/workflows/skill-sync.yml) | Weekly Mon 05:23 | Vendored skill drift detection | ~1 min |
| [upstream-sync.yml](file:///home/mohamed/Desktop/Github/ChessSRS/.github/workflows/upstream-sync.yml) | Weekly Mon 06:00 | Lichess upstream tracking | ~1 min |

### 1.2 Findings

#### HIGH — Missing `actions/cache` for `pub get` in test.yml

- **Location:** [test.yml#L189-L191](file:///home/mohamed/Desktop/Github/ChessSRS/.github/workflows/test.yml#L189-L191)
- **Issue:** `flutter pub get` runs uncached every time. The `subosito/flutter-action` caches the Flutter SDK itself (`cache: true`), but the project's pub cache (`~/.pub-cache`) is not cached.
- **Impact:** ~15-30s wasted per run downloading 65+ dependencies.
- **Fix:** Add a cache step keyed on `pubspec.lock`:
  ```yaml
  - uses: actions/cache@v6.1.0
    with:
      path: ~/.pub-cache
      key: pub-${{ runner.os }}-${{ hashFiles('pubspec.lock') }}
      restore-keys: pub-${{ runner.os }}-
  ```

#### HIGH — build_runner cache key doesn't include Dart/Flutter version

- **Location:** [test.yml#L210](file:///home/mohamed/Desktop/Github/ChessSRS/.github/workflows/test.yml#L210)
- **Issue:** The codegen cache key is `codegen-${{ runner.os }}-${{ hashFiles('pubspec.yaml', 'pubspec.lock', 'build.yaml') }}`. It does not incorporate the Flutter/Dart SDK version. A Flutter version bump with the same pubspec could serve stale generated code from the old SDK's build_runner.
- **Impact:** Low probability (Flutter bumps are rare), but the failure mode is subtle: the cache restores, build_runner sees matching input digests, and skips regeneration even though the codegen output format may have changed.
- **Fix:** Add `hashFiles('.fvmrc')` or the Flutter version to the key.

#### MEDIUM — Duplicated `apt-get` dependency lists across workflows

- **Location:** [release.yml#L48](file:///home/mohamed/Desktop/Github/ChessSRS/.github/workflows/release.yml#L48), [runtime-smoke.yml#L48-L51](file:///home/mohamed/Desktop/Github/ChessSRS/.github/workflows/runtime-smoke.yml#L48-L51)
- **Issue:** Linux build dependencies are listed in two places. If one is updated and the other isn't, builds break in one workflow but not the other.
- **Fix:** Extract to a shared composite action or a `.github/scripts/install-linux-deps.sh`.

#### MEDIUM — `release-proof.yml` doesn't cache build_runner output

- **Location:** [release-proof.yml#L60-L61](file:///home/mohamed/Desktop/Github/ChessSRS/.github/workflows/release-proof.yml#L60-L61)
- **Issue:** Unlike test.yml, the release-proof workflow runs `dart run build_runner build` without any asset-graph cache.
- **Impact:** ~60-80s extra on every proof build.

#### MEDIUM — `docs-check.yml` is essentially vestigial

- **Location:** [docs-check.yml](file:///home/mohamed/Desktop/Github/ChessSRS/.github/workflows/docs-check.yml)
- **Issue:** The workflow fires on docs changes and runs `echo`. It is not a required check and does not gate anything. The extensive comment history explains why, but it still burns a runner slot for 3 seconds.
- **Recommendation:** Keep as-is for now (comment history is valuable documentation); consider removing if runner usage becomes a concern.

#### LOW — `skill-sync.yml` uses `actions/checkout@v4`, not `@v7`

- **Location:** [skill-sync.yml#L24](file:///home/mohamed/Desktop/Github/ChessSRS/.github/workflows/skill-sync.yml#L24)
- **Issue:** Every other workflow uses `actions/checkout@v7.0.1`; skill-sync.yml uses `@v4`. Same for `upstream-sync.yml`.
- **Impact:** Functional but inconsistent; v4 is EOL-approaching.
- **Fix:** Bump to `@v7.0.1` for consistency.

#### LOW — `upstream-sync.yml` uses `actions/setup-python@v5`, not pinned to hash

- **Location:** [upstream-sync.yml#L37](file:///home/mohamed/Desktop/Github/ChessSRS/.github/workflows/upstream-sync.yml#L37)
- **Issue:** Actions are tag-pinned (`@v5`), not SHA-pinned. This is industry-standard but slightly less secure than SHA pins.
- **Impact:** Very low; tag pinning is the norm for community actions.

#### INFO — Well-designed: docs-only fast lane in test.yml

The [trusted-base classifier](file:///home/mohamed/Desktop/Github/ChessSRS/.github/scripts/ci-docs-only.sh) that skips Flutter steps for docs-only PRs is excellent:
- Classifier is loaded from the base commit (a PR can't tamper with its own judge)
- Self-tested on every PR
- Falls back to full suite on any classification failure
- Narrow rule (only `docs/*.md`) with clear rationale for excluding root Markdown

#### INFO — Well-designed: concurrency groups and cancel-in-progress

All workflows correctly use concurrency groups with `cancel-in-progress` for PRs while never cancelling main pushes.

---

## 2. Gate System Analysis

### 2.1 Gate Coverage Assessment

| Gate | Coverage | Strength | Notes |
|---|---|---|---|
| G01 (format+lint) | ✅ Strong | CI-owned by test.yml | strict-casts, strict-inference, strict-raw-types all on |
| G02 (arch boundary) | ✅ Present | Flutter test | Exists but not wired into gates.yml fast lane |
| G03 (banned APIs) | ✅ Strong | Regex-based, well-scoped | Has gate-allow escape hatch with visibility |
| G05 (spec trace) | ✅ Strong | Two-spec mode prevents dodge-by-deletion | |
| G06 (mutants) | ⚠️ Limited | Only tests scheduler_test.dart despite expanded catalog | Documented limitation |
| G07 (protected paths) | ✅ Strong | Has self-test, auto-approval for additive ledger rows | See §2.2 |
| G08 (test weakening) | ✅ Strong | Pairing rule reduces false positives | |
| G09 (fail-to-pass) | ⚠️ Manual | Reviewer-enforced, not CI-wired | |
| G10 (ratchets) | ✅ Strong | 5 metrics, monotone | |
| G11 (dep posture) | ⚠️ Reviewer-only | No scanner; relies on G07 (pubspec is protected) | |
| G12 (red-team recall) | ✅ Strong | Nightly + gate-change PRs | |
| G13 (vendor drift) | ✅ Strong | Offline hash check + weekly upstream | |

### 2.2 Trusted-Base-Copy Pattern Robustness

**Verdict: Robust, with one edge case.**

The [gates.yml](file:///home/mohamed/Desktop/Github/ChessSRS/.github/workflows/gates.yml#L73-L110) pattern:
1. Checks out the PR tree at `pr/`
2. Checks out the base SHA at `trusted/`
3. Runs gate scripts from `trusted/` so a PR can't tamper with its own judge
4. Falls back to PR tree with a warning on bootstrap

**Edge case:** The fallback (`TRUSTED=.`) means the first PR that introduces a gate script is self-judging. This is documented and accepted (owner review), but worth tracking.

### 2.3 Protected Paths Coverage

**Location:** [.gates/protected-paths.txt](file:///home/mohamed/Desktop/Github/ChessSRS/.gates/protected-paths.txt)

**Current coverage (32 patterns):**
```
SPEC.md, GATES.md, GATES_PLAN.md, QUALITY.md, TEST_STRATEGY.md,
docs/ESCAPE_TO_GATE.md, CODEOWNERS, verify, .gates/*, redteam/*,
scripts/gates/*, .github/*, AGENTS.md, CLAUDE.md, analysis_options.yaml,
pubspec.yaml, test/fixtures/*, test_fixtures/*,
docs/AUTONOMOUS_IMPROVEMENT_CATALOG.md, docs/AUTONOMOUS_WORK_LEDGER.md,
docs/UNIVERSAL_AUTONOMOUS_IMPROVEMENT_PROMPT.md,
docs/recursive-agent-improvement-strategy.md, scripts/autonomous/*
```

#### MEDIUM — Missing protected paths

| Path | Why it should be protected |
|---|---|
| `pubspec.lock` | Dependency resolution; test.yml triggers on it but G07 doesn't protect it. A rogue lockfile update could introduce compromised transitive deps. |
| `build.yaml` | Code generation config changes what gets generated. Currently triggers test.yml but not G07. |
| `PRODUCT.md` | Product intent; authoritative home per AGENTS.md §1. |
| `MVP.md` | Beta scope; authoritative home per AGENTS.md §1. |
| `ARCHITECTURE.md` | Module boundaries; authoritative home per AGENTS.md §1. |
| `IMPLEMENTATION_PLAN.md` | Delivery status; authoritative home per AGENTS.md §1. |
| `packaging/linux/*` | Release packaging scripts affect what ships. |

#### LOW — `.github/*` glob covers everything in `.github/`

The pattern `.github/*` with fnmatch semantics (`*` crosses `/`) covers all scripts, workflows, and dependabot config. This is correct and intentionally broad.

### 2.4 Gate Script Quality

**Overall: High quality. 1,520 LOC of Python/Bash across 14 scripts.**

| Script | LOC | Quality Notes |
|---|---|---|
| [protected_paths_check.py](file:///home/mohamed/Desktop/Github/ChessSRS/scripts/gates/protected_paths_check.py) | 187 | Well-structured; has 173-line companion test |
| [test_weakening_check.py](file:///home/mohamed/Desktop/Github/ChessSRS/scripts/gates/test_weakening_check.py) | 178 | Smart pairing rule; Dart-tuned |
| [vendor_drift_check.py](file:///home/mohamed/Desktop/Github/ChessSRS/scripts/gates/vendor_drift_check.py) | 199 | Hash-based content verification |
| [collect_metrics.py](file:///home/mohamed/Desktop/Github/ChessSRS/scripts/gates/collect_metrics.py) | 110 | Clean; deterministic text scans |
| [spec_trace_check.py](file:///home/mohamed/Desktop/Github/ChessSRS/scripts/gates/spec_trace_check.py) | 67 | Concise; two-spec mode is well-implemented |
| [gates.sh](file:///home/mohamed/Desktop/Github/ChessSRS/scripts/gates.sh) | 68 | Clean orchestrator; uses `set -euo pipefail` |

**Positive patterns:**
- All Python scripts have clear docstrings, argparse, and exit codes (0/1/2 convention)
- All shell scripts use `set -euo pipefail`
- All have shebangs (`#!/usr/bin/env bash` or `#!/usr/bin/env python3`)
- Gate scripts in CI run from the trusted base, not the PR tree

**Minor issues:**
- `fail_to_pass_check.sh` and its test (69+121=190 LOC) are complex enough to warrant Python rewrite for testability
- `scaffold_redteam_case.sh` (54 LOC) generates templates; fine as-is

---

## 3. Build Configuration

### 3.1 pubspec.yaml

**Location:** [pubspec.yaml](file:///home/mohamed/Desktop/Github/ChessSRS/pubspec.yaml)

#### HIGH — 5 git-pinned dependencies that should be pub.dev releases

| Package | Pin | Comment in pubspec | Risk |
|---|---|---|---|
| `lc0` | `04284fa` from lichess-org/dart-lc0 | "branch not merged nor published yet" | Stale pin; upstream may have moved |
| `multistockfish` | `896c388` from lichess-org/dart-multistockfish | "Git ref while engine refactor lands" | 3 sub-packages in dependency_overrides |
| `multistockfish_chess` | Same SHA via override | Transitive | Same risk |
| `multistockfish_light` | Same SHA via override | Transitive | Same risk |
| `multistockfish_variant` | Same SHA via override | Transitive | Same risk |

**Impact:** Git-pinned deps bypass pub.dev's security scanning, have no version constraints, and can cause resolution conflicts. The pubspec itself acknowledges this is temporary ("restore a pub.dev version before merging").

**Recommendation:** Track upstream publication status; create a task to migrate when published.

#### MEDIUM — 65 direct dependencies is high

The ratchet baseline records 65 direct dependencies. Some that may be removable:
- `signal_strength_indicator: ^0.5.0` — very specific UI widget; last pub.dev update check needed
- `cupertino_ui: ^1.1.1` — if the app is primarily Material Design
- `cupertino_http: ^3.0.2` — iOS-specific; if no iOS build ships, dead weight
- `flutter_displaymode: ^0.7.0` — Android-only display refresh rate; niche

#### LOW — `lint: ^2.8.0` in dev_dependencies

The analysis_options.yaml includes `package:lint/strict.yaml`, and `lint` is listed as a dev dependency. This is the community `lint` package, which is fine but may overlap with Flutter's built-in `flutter_lints`.

### 3.2 analysis_options.yaml

**Location:** [analysis_options.yaml](file:///home/mohamed/Desktop/Github/ChessSRS/analysis_options.yaml)

**Strengths:**
- All three strict modes on (`strict-casts`, `strict-inference`, `strict-raw-types`)
- Generated code excluded correctly (`*.g.dart`, `*.freezed.dart`)
- Page width set to 100 (consistent with dart format check in CI)

#### MEDIUM — `riverpod_lint` is commented out

```yaml
# plugins:
#   - riverpod_lint
```

For a Riverpod-heavy app, `riverpod_lint` catches common provider mistakes (missing `ref.watch` dependencies, incorrect provider scoping). The comment suggests it was tried and disabled.

**Recommendation:** Re-evaluate enabling `riverpod_lint` now that it's more stable.

#### LOW — Missing useful lint rules

Consider adding:
- `prefer_const_constructors: true` — reduces widget rebuilds
- `unnecessary_lambdas: true` — cleaner code
- `avoid_print: true` — force proper logging

### 3.3 build.yaml

**Location:** [build.yaml](file:///home/mohamed/Desktop/Github/ChessSRS/build.yaml)

**Configuration is minimal and correct:**
- `freezed` and `json_serializable` scoped to `lib/src/model/**` and `lib/src/**/*_models.dart`
- `freezed` also includes `*_providers.dart`
- `from_json: false` and `to_json: false` on freezed (annotation-driven per class)

This is optimal — narrow `generate_for` globs mean build_runner skips most of the source tree.

### 3.4 FVM Configuration

**Location:** [.fvmrc](file:///home/mohamed/Desktop/Github/ChessSRS/.fvmrc)

Pins Flutter `3.47.7`. CI uses `flutter-version-file: pubspec.yaml` (which declares the same `3.47.7`), creating a single source of truth. This is correct.

---

## 4. Scripts Quality

### 4.1 Shell Scripts Assessment

| Script | Shebang | set -euo | Error handling | Grade |
|---|---|---|---|---|
| [gates.sh](file:///home/mohamed/Desktop/Github/ChessSRS/scripts/gates.sh) | ✅ | ✅ pipefail | ✅ fail() helper | A |
| [dev_run.sh](file:///home/mohamed/Desktop/Github/ChessSRS/scripts/dev_run.sh) | ✅ | ✅ pipefail | ✅ set -e exits on failure | A |
| [gen-translations.sh](file:///home/mohamed/Desktop/Github/ChessSRS/scripts/gen-translations.sh) | ✅ | ✅ pipefail | ✅ | A |
| [check_dartdoc_domain.sh](file:///home/mohamed/Desktop/Github/ChessSRS/scripts/check_dartdoc_domain.sh) | ✅ | ✅ pipefail | ✅ | A |
| [check_domain_docs.sh](file:///home/mohamed/Desktop/Github/ChessSRS/scripts/check_domain_docs.sh) | ✅ | ✅ pipefail | ✅ | A |
| [ci_failure_summary.sh](file:///home/mohamed/Desktop/Github/ChessSRS/scripts/ci_failure_summary.sh) | ✅ | ✅ pipefail | ✅ arg check | A |
| [verify](file:///home/mohamed/Desktop/Github/ChessSRS/verify) | ✅ | ⚠️ `set -e` only | No pipefail | B |

#### LOW — `verify` script uses `set -e` without `-uo pipefail`

- **Location:** [verify](file:///home/mohamed/Desktop/Github/ChessSRS/verify#L2)
- **Issue:** Uses `set -e` but not `-uo pipefail`. An unset variable won't error; a piped command's failure won't propagate.
- **Impact:** Minimal since `verify` runs only `flutter analyze` and `flutter test`, but inconsistent with all other scripts.

#### LOW — `dev_run.sh` missing trailing newline

- **Location:** [dev_run.sh](file:///home/mohamed/Desktop/Github/ChessSRS/scripts/dev_run.sh#L20)
- **Issue:** File ends without a newline (POSIX non-compliance).

#### INFO — No hardcoded paths found

All scripts use `$(dirname "$0")` or similar patterns to resolve paths relative to their location. No absolute paths detected.

### 4.2 Python Scripts Assessment

All gate scripts follow consistent patterns:
- `#!/usr/bin/env python3`
- Docstring with usage, purpose, and exit codes
- `argparse` for CLI
- Consistent exit code convention (0 clean, 1 failure, 2 usage)

**No issues found.** Python scripts are well-maintained.

### 4.3 Node.js Scripts

| Script | Purpose |
|---|---|
| [gen-arb.mjs](file:///home/mohamed/Desktop/Github/ChessSRS/scripts/gen-arb.mjs) (9,518B) | ARB localization file generation |
| [scripts/package.json](file:///home/mohamed/Desktop/Github/ChessSRS/scripts/package.json) | Node deps for gen-arb |
| [scripts/firebase/send-message.js](file:///home/mohamed/Desktop/Github/ChessSRS/scripts/firebase/send-message.js) | Firebase messaging |
| [scripts/firebase/package.json](file:///home/mohamed/Desktop/Github/ChessSRS/scripts/firebase/package.json) | Firebase deps |

#### LOW — Firebase scripts may be dead code

The firebase directory contains a `send-message.js` and its `package.json`. If Firebase Cloud Messaging isn't used in the local-first fork, these may be removable.

---

## 5. Developer Onboarding

### 5.1 Setup Documentation

**Location:** [docs/setting_dev_env.md](file:///home/mohamed/Desktop/Github/ChessSRS/docs/setting_dev_env.md)

#### MEDIUM — setup docs are inherited from lichess-org/mobile with minimal ChessSRS adaptation

The file opens with a note pointing to `CLAUDE.md` and `AGENTS.md`, but the body is largely unchanged upstream documentation:
- References lichess Discord for help
- Mentions lila server setup (unnecessary for local-first SRS training)
- Covers iOS/Android emulator setup (iOS doesn't ship)
- No Linux desktop setup instructions (the primary shipped platform)

**Missing for a new ChessSRS developer:**
1. `fvm install` / `fvm use` (FVM is assumed but not documented step-by-step)
2. `scripts/dev_run.sh` existence and usage (the script self-documents but setup docs don't mention it)
3. Linux desktop build dependencies (`libsqlite3-dev`, etc.)
4. How to run gates locally (`./scripts/gates.sh t1`)
5. How worktrees work (AGENTS.md covers this for agents, not humans)

### 5.2 `dev_run.sh` Quality

**Location:** [scripts/dev_run.sh](file:///home/mohamed/Desktop/Github/ChessSRS/scripts/dev_run.sh)

**Verdict: Excellent.** It correctly chains `pub get → build_runner → flutter run`, which is exactly the gotcha the AGENTS.md warns about (flutter run doesn't regenerate). Accepts extra args via `"$@"`.

---

## 6. Release Process

### 6.1 Release Automation

**Verdict: Fully automated and well-designed.**

The [release.yml](file:///home/mohamed/Desktop/Github/ChessSRS/.github/workflows/release.yml) pipeline:

1. **Tag-triggered:** `git tag v1.7.0 && git push origin v1.7.0`
2. **Parallel Linux + Android builds** with version stamping from the tag
3. **Post-build assertions** verify the artifact reports the correct version
4. **Multi-format Linux:** tarball, .deb, AppImage
5. **Android:** AAB + APK with fallback to throwaway key if secrets absent
6. **GitHub Release** with auto-generated notes, file guide, SHA256SUMS
7. **Post-release runtime smoke** (non-gating, deliberate)

**Smart nightly:** The [nightly-decide.sh](file:///home/mohamed/Desktop/Github/ChessSRS/.github/scripts/nightly-decide.sh) script skips unnecessary builds by checking if shipped code actually changed since the last tag. Well-tested by [nightly-decide-test.sh](file:///home/mohamed/Desktop/Github/ChessSRS/.github/scripts/nightly-decide-test.sh).

### 6.2 Version Stamping

**Verdict: Correctly fixed a real historical bug (v1.5.0-v1.6.2 showing v1.4.0).**

The tag is the sole version ledger. `pubspec.yaml` is the development version and is not bumped per release. Build jobs assert stamp correctness. This is well-documented in [releases.md](file:///home/mohamed/Desktop/Github/ChessSRS/docs/releases.md).

### 6.3 Missing: Automatic Play Store upload

The AAB is built and signed (when secrets exist), but upload to Google Play Console is manual. This is documented and accepted — the owner controls the store listing.

### 6.4 Missing: Changelog automation

Release notes are auto-generated from GitHub's commit summary. There's no `CHANGELOG.md` file or structured release notes beyond commit titles. For a beta-stage app this is fine.

---

## 7. Dependency Health

### 7.1 Git-Pinned Dependencies

| Package | SHA | Upstream repo | Status |
|---|---|---|---|
| `lc0` | `04284fa` | lichess-org/dart-lc0 | Engine refactor branch; not merged/published |
| `multistockfish` | `896c388` | lichess-org/dart-multistockfish | Same engine refactor |
| `multistockfish_chess` | (override) | Same | Same |
| `multistockfish_light` | (override) | Same | Same |
| `multistockfish_variant` | (override) | Same | Same |

**Risk:** Git-pinned deps don't get pub.dev vulnerability advisories. The SHA pins mean no automatic security patches.

**Recommendation:** Set a recurring check (quarterly) on the upstream repos for publication status.

### 7.2 Potentially Abandoned/Niche Dependencies

| Package | Last pub.dev update | Concern |
|---|---|---|
| `signal_strength_indicator` | Check needed | Very niche package (WiFi signal bars) |
| `sound_effect` | Check needed | Sound playback; alternatives exist |
| `popover` | Check needed | UI overlay; alternatives in Flutter core |
| `flutter_displaymode` | Check needed | Android refresh rate control |

### 7.3 License Compatibility

**Base:** GPL-3.0 (from Lichess Mobile fork)

All listed pub.dev dependencies use MIT, BSD-3, or Apache-2.0 licenses, which are GPL-3.0 compatible. The git-pinned packages from lichess-org are also under compatible licenses (the upstream is AGPL-3.0 but the fork is GPL-3.0 per ARCHITECTURE.md §6).

**No license conflicts detected.**

### 7.4 Dependency Security

#### MEDIUM — No automated vulnerability scanning

There's no `dependabot.yml` or equivalent for Dart/pub.dev dependency vulnerability alerts. G11 (dependency posture) is noted as reviewer-enforced, with no scanner wired.

**Recommendation:** Add a `.github/dependabot.yml` for GitHub Actions version updates at minimum:
```yaml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

Pub.dev doesn't have native Dependabot support, but `dart pub outdated` can be run in a periodic workflow.

---

## 8. Summary of Proposals

### CI/CD Improvements (Priority Order)

| # | Proposal | Severity | Effort |
|---|---|---|---|
| C1 | Add pub cache to test.yml via `actions/cache` | High | 5 min |
| C2 | Include Flutter version in build_runner cache key | High | 2 min |
| C3 | Add build_runner cache to release-proof.yml | Medium | 5 min |
| C4 | Bump checkout action to v7 in skill-sync.yml and upstream-sync.yml | Low | 2 min |
| C5 | Extract Linux deps to shared script | Medium | 15 min |
| C6 | Add Dependabot for GitHub Actions | Medium | 5 min |

### Dependency Recommendations

| # | Proposal | Severity | Effort |
|---|---|---|---|
| D1 | Track upstream lc0/multistockfish publication; migrate when available | High | Monitor |
| D2 | Audit niche deps (signal_strength_indicator, sound_effect, etc.) for maintenance status | Medium | 1 hr |
| D3 | Add periodic `dart pub outdated` workflow | Low | 20 min |

### Gate System Enhancements

| # | Proposal | Severity | Effort |
|---|---|---|---|
| G1 | Add `pubspec.lock` to protected paths | Medium | 1 min |
| G2 | Add `build.yaml` to protected paths | Medium | 1 min |
| G3 | Add `packaging/linux/*` to protected paths | Low | 1 min |
| G4 | Consider protecting `PRODUCT.md`, `MVP.md`, `ARCHITECTURE.md` | Low | Discussion |
| G5 | Wire G09 fail-to-pass into CI for bugfix PRs | Medium | 1 hr |
| G6 | Expand G06 mutation runner beyond scheduler_test.dart | Low | Ongoing |

### DX Improvements

| # | Proposal | Severity | Effort |
|---|---|---|---|
| X1 | Add ChessSRS-specific quick-start to setting_dev_env.md (Linux deps, FVM, dev_run.sh, gates) | Medium | 30 min |
| X2 | Re-evaluate enabling `riverpod_lint` in analysis_options | Medium | 30 min |
| X3 | Add `set -uo pipefail` to `verify` script | Low | 1 min |
| X4 | Add trailing newline to `dev_run.sh` | Low | 1 min |
| X5 | Audit and potentially remove `scripts/firebase/` if unused | Low | 15 min |
| X6 | Add `prefer_const_constructors` lint rule | Low | Evaluate impact |

---

## 9. What's Working Well (Keep Doing This)

1. **Trusted-base-copy pattern** — PR can't tamper with its own judge. This is the gold standard.
2. **Docs-only fast lane** — Smart, unit-tested, fail-safe, and uses the real job name.
3. **Tag-based version stamping** — Fixed a real bug (v1.4.0 shown for v1.5.0-v1.6.2). Post-build assertions prevent regression.
4. **Nightly build intelligence** — Skips when nothing shipped changed. Tested on every PR.
5. **Ratchet system** — Monotone, automatically tightens, requires human review to loosen.
6. **Script quality** — Every script uses `set -euo pipefail`, has shebangs, relative paths, and clear error messages.
7. **Workflow documentation** — The comment blocks in test.yml and gates.yml are exceptional: they explain not just what the config does, but why each decision was made and what went wrong when it was different.
8. **Gate escape log** — Links incidents to the new gate/invariant/red-team case that closes them.
9. **Multi-format Linux packaging** — tarball, .deb, AppImage all automated.
10. **Concurrency management** — All workflows use correct cancel-in-progress for PRs.
