# Upstream Diff Audit — 2026-09-30

Fork: `cassandre60/chess-repertoire-srs` (ChessSRS) · Upstream: `lichess-org/mobile`
Supersedes nothing: `docs/upstream-audit-2026-09-29.md` remains the earlier snapshot.

**Read-only audit. Nothing was merged, rebased, pushed, or modified.** The only
network operation was `git fetch upstream` on a remote that already existed.
Verified afterwards: `git remote -v` unchanged, working tree unchanged.

## 0. Basis and method

| | |
|---|---|
| Upstream ref | `upstream/main` @ `f7f71d120` (2026-09-30 12:40 +0200) |
| Fork ref | `main` @ `d2f660365` (2026-09-30 21:26 +0100) |
| Merge base | `6e1d045a` |
| Fork commits | 222 |
| Upstream-only commits | 167 (155 non-merge + 12 merges) |
| Diff | 1341 files, +103491 / −98050 → **496 A, 440 M, 404 D, 1 R081** |

Commands used (all read-only):

```
git fetch upstream
git diff --name-status upstream/main...HEAD
git log --oneline upstream/main..HEAD
git log --oneline HEAD..upstream/main
git merge-base upstream/main HEAD
```

Per the repo's own audit conventions (`docs/upstream-audit-prompt.md` §Step 0),
relevance was decided against `PRODUCT.md`, `MVP.md`, `CUT_PROPOSALS.md` and
`docs/upstream-realign.md` — not by "does it affect functionality" in the
abstract. A subsystem listed as cut is **not** a finding.

**The pre-existing `lib/l10n/*` working-tree churn in the primary checkout is
excluded from every number here.** It is `build_runner` formatting output, not
committed work (see AGENTS.md Lessons Learned, 2026-09-28).

---

## 1. The finding that governs everything else

**`e57fcb411` — the point `docs/upstream-realign.md` Task 1 synced to — is not
an ancestor of `HEAD`.**

```
$ git merge-base --is-ancestor e57fcb411 HEAD   # → NO
```

Upstream fixes reach this fork only as hand-applied, squash-committed
cherry-picks. At least these five upstream commits are **already applied**
here under different hashes:

| Upstream commit | Fork commit | Change |
|---|---|---|
| `a99dad8a1` / `214bb0353` | `bcb66ad5b` | Email-login credentials in POST body, not query string |
| `25cf0fae5` | `a0d9ed580` | Board editor accepts FENs describing illegal positions |
| `60309eb8d` | `0fad2d1e3` | App links routed by exact host, not prefix match |
| `c60a0edd8` | `7f2a0c4e7` | Index `openings.epd` for per-position lookup |
| `498ce10a7` | `02d91a23f` | Await openings database cleanup |

Consequences:

1. `git log HEAD..upstream/main` **overstates** the real gap by at least these
   five. Do not read the number 167 as "167 missing fixes".
2. A blind `git merge upstream/main` will conflict on files that are already
   correct, because git has no lineage telling it so.
3. There is no "just merge and resolve" path. Realignment has to be
   subsystem-by-subsystem, which is what `docs/upstream-realign.md` already says.

**Standing recommendation:** keep an explicit ledger of applied-upstream commits
(`docs/upstream-applied.md` does not exist yet — creating it is cheap and makes
the next audit's counts trustworthy).

---

## 2. Your changes vs. upstream

Grouped by subsystem rather than as 1341 rows, per `docs/upstream-audit-prompt.md`
§Step 3. Categories are the repo's own: `Cut-intended`, `Presentation-only`,
`Logic-shared`, `Fork-diverged`, `License`.

| Area | Category | Change | Risk | Upstream impact | Notes |
|---|---|---|---|---|---|
| `lib/src/domain/` — 21 files: FSRS scheduler, review session, graph-aware coordinator, repertoire node, position identity | New product logic | Added | High | No | No upstream counterpart. Zero merge surface. |
| `lib/src/design/` — 17 files: tokens, primitives, theme bridge, srs_sheet/toast/dialog, board background, notation line | Presentation-only | Added | High | No | Deliberate fork identity. Explicitly out of scope for realign (`docs/upstream-realign.md` Task 2). |
| `lib/src/persistence/` — 6 files: `sqlite_study_repository.dart` (977 lines), `canonical_rekey_migration.dart`, `srs_schema.dart` | New product logic | Added | High | Maybe | `lib/src/db/database.dart` is modified on both sides (2 upstream commits) → real merge point. |
| `lib/src/import/`, `lib/src/review/` — 7 files | New product logic | Added | High | No | New subsystems. |
| `lib/src/view/review/` — 9 files, incl. `review_screen.dart` (+1206) and `review_scope_drawer.dart` (+902) | New product logic | Added | High | No | New subsystem. |
| `lib/src/model/study/study_controller.dart` (+203/−40) | **Fork-diverged** | Modified | High | **Yes** | Upstream moved here: `17d7a3cd8`, `320c6a2ad`, `f24cfee4c`. Highest-value realign target. |
| `lib/src/view/analysis/analysis_screen.dart` (+328/−155) | **Fork-diverged** | Modified | High | **Yes** | Upstream `8ded3a61c` extracted `EngineToggleButton` into this file; fork `d2f660365` fixes the same in-flight guard. Likely duplicate — see §5. |
| `lib/src/model/engine/{position_evaluator,evaluation_mixin}.dart` | **Fork-diverged** | Modified | High | **Yes** | Upstream's `e0bbd096a` (Practice) rewrites both. |
| `lib/src/view/board_editor/board_editor_screen.dart` (+534/−317) | **Fork-diverged** | Modified | High | **Yes** | Upstream: `25cf0fae5`, `f1f312931`, `39f598c87`, `6cac2d18e`. |
| `lib/src/network/http.dart` (+150/−86) | **Fork-diverged** | Modified | Medium | **Yes** | Upstream `bc0213734`, `e0952d579`. Signature-compatible — see §5. |
| `lib/src/view/explorer/opening_explorer_*.dart` | **Fork-diverged** | Modified | Medium | **Yes** | Upstream `b6bc9d593` (date range), `83309ff57`, `8bf16896f`. |
| `lib/src/view/settings/*` — 5 files | **Fork-diverged** | Modified | Medium | **Yes** | Upstream `aa663b2d2`, `6415d0d65`, `cfd25632d`, `3c457942d`, `39f598c87`. |
| 186 `lib/` files — broadcast, puzzle, play, tv, learn, correspondence, clock, tournament, relation, message, more/home tabs | **Cut-intended** | Deleted | Medium | No | Matches `CUT_PROPOSALS.md`. 208 of these are still being modified upstream — which is *expected and not a defect*; it is simply the cost of cutting. |
| `test/` — 72 added, 101 modified, 56 deleted | Fork-diverged | Mixed | Medium | **Yes** | 44 test files are on the both-sides list, incl. shared harness `test_helpers.dart`, `test_provider_scope.dart`, `test/binding.dart`. |
| `assets/pieces/{light,dark}/png-512` (72 files), `figurines/`, `brand/`, 2 variable fonts | Assets | Added | Low | No | New design system. |
| `assets/board-thumbnails/` (32), `logo-*.webp`, discord/mastodon | Cut-intended | Deleted | Low | No | Consistent with the `background_theme_choice_screen.dart` cut. |
| 10 `.github/workflows/*` (build, deploy_play_store, crowdin ×2, draft_github_release) | Tooling | Deleted | Medium | No | Replaced by `test.yml` + `release-proof.yml`. |
| `.github/workflows/test.yml` | **Fork-diverged** | Modified | Medium | **Yes** | Fork widened the path filter (`assets/**`, `scripts/**`), added `workflow_dispatch` and an explanatory comment, and **dropped upstream's `concurrency` block**. |
| `pubspec.yaml` / `pubspec.lock` | **Fork-diverged** | Modified | High | **Yes** | Renamed `lichess_mobile` → `chess_srs`; version `0.28.3+002803` → `0.2.0+1`; 5 deps removed; 2 added. |
| `scripts/` — 6 modified, 1 deleted (`gen-widget-strings.mjs`) | Tooling | Modified | Low | Maybe | `update_openings_db.py` also changed upstream (`c60a0edd8`). |
| `ios/` (94 D, 19 M), `android/` (18 D, 12 M) | Cut-intended | Mixed | Medium | No | Firebase + home-widget removal. |
| 146 `docs/` files (120 of them screenshots) + 8 root spec files (`PRODUCT.md`, `QUALITY.md`, `ARCHITECTURE.md`, `CUT_PROPOSALS.md`, `IMPLEMENTATION_PLAN.md`, `TEST_STRATEGY.md`, `MVP.md`, `AGENTS.md`) | Documentation | Added | Low | No | Docs-only changes get no CI run — by design, see AGENTS.md §3. |
| 112 `design/` files + `design/reference/index.html` | Documentation | Added | Low | No | Excluded from the analyzer in `analysis_options.yaml`. |

---

## 3. Upstream changes not in your fork

Of the 155 non-merge upstream-only commits, measured against the fork's
kept-and-modified surface (excluding `lib/l10n` and `pubspec`):

| Overlap class | Count |
|---|---|
| Touch **no** file the fork modified | 40 |
| Touch **only** l10n/pubspec of fork-modified files | 26 |
| Touch fork **code** (hard overlap) | **89** |

Ranked by relevance to *kept* subsystems. Cut-intended changes are excluded
entirely per `docs/upstream-audit-prompt.md` §Step 0.

| Commit | Type | Summary | Relevance | Merge effort | Risk |
|---|---|---|---|---|---|
| `e6be63d22` | feat | Native **Linux audio playback** in `sound_service.dart` | **Yes** — runtime validation runs `flutter run -d linux` | Trivial | Low |
| `cd25cd5f8` | ci | `concurrency: cancel-in-progress` so only the latest PR commit is tested | **Yes** | Trivial (3 lines) | Low |
| `ed3dbea51` | chore | Remove unrequired `abiFilters` from `build.gradle.kts` | Yes | Trivial | Low |
| `8ded3a61c` | refactor | Extract `EngineToggleButton`, dedup the toggle guard across bottom bars | **Yes** — overlaps fork `d2f660365` | Moderate | Medium |
| `00bcfd8f9` | fix | Engine button popup bug (`engine_button.dart`) | Yes | Moderate | Medium |
| `1a3a4dda8` | fix | Cancel the eval stream subscription of a *replaced* eval request | **Yes** — same defect class the fork fixed in #104 | Moderate | Medium |
| `4d9cb3c12` | fix | Don't restart the move-expiration timer on unrelated rebuilds | Yes | Moderate | Medium |
| `4d19138fc` | refactor | Unify duplicated NAG annotation tables in `pgn.dart` | Yes | Moderate | Medium |
| `f24cfee4c` | refactor | Move view contracts from `view/` to `model/` | Yes | Moderate | Medium |
| `4b44389e1` | fix | `HttpNetworkImageWidget`: read the static client once, pass `height` through | Yes (6 call sites in fork) | Trivial | Low |
| `7fc986dc4` | fix | Compare Maia weight-file claims by URI, not path | Unclear | Trivial | Low |
| `39f598c87`, `6cac2d18e`, `8bf16896f`, `0028a4fb2` | chore | Replace hardcoded UI strings with mobile translations | **Yes** — collides with fork `#108` | Complex (l10n) | Medium |
| `b6bc9d593` (#3764) | feat | Date-range selection in the opening explorer | Unclear | Moderate | Medium |
| `1c5a32369` (+ `33c39d110`, `89f6a0084`, `154484a2d`) | fix + test | Perf-stats title overflow on long translations | Low (perf stats kept) | Moderate | Low |
| `4537c8b75`, `9e51a6bb6` | fix | Shimmer skeletons and profile sections at stable height while loading | Low | Trivial | Low |
| `792ee93ac`, `2c0e4e338`, `513d8f33f` | refactor | Memoization extension; per-tile perf sort; display-rating getters | Unclear | Moderate | Low |
| `a99dad8a1`, `214bb0353` | fix | Email-login POST body | **Already applied** (`bcb66ad5b`) | — | — |
| `25cf0fae5` | fix | Board editor accepts illegal FENs | **Already applied** (`a0d9ed580`) | — | — |
| `60309eb8d` | fix | App-links exact host check | **Already applied** (`0fad2d1e3`) | — | — |
| `c60a0edd8`, `498ce10a7` | perf/fix | Openings EPD index; await DB cleanup | **Already applied** (`7f2a0c4e7`, `02d91a23f`) | — | — |
| `e0bbd096a` (#3689), `0345429f6` (#3681) | feat | **Practice** and **Learn** features | Cut-intended | — | — |
| `b51f4997b`, `de5a1bf1e`, `0bd75aead`, `dc63b3673`, `37ddbffd1` | feat/fix | FCM refactor, inbox delete, friend search/sort | Cut-intended (Firebase + message cut) | — | — |
| `f4279fa10` | chore | **Lint + SDK floor bump — sweeps 250+ files and `pubspec.yaml`** | Yes | **Complex** | High |

---

## 4. Dependency drift

Resolved versions from `pubspec.lock` on both sides, direct deps only.

### Behind upstream (fork is older)

| Package | Upstream | Fork | Notes |
|---|---|---|---|
| `chessground` | 10.3.0 | **10.2.0** | **High interest.** Board rendering is this app's core surface, and the fork layers `lib/src/design/board_background.dart` plus 72 custom piece PNGs on top. Test the bump in a worktree before taking. |
| `material_ui` | 1.5.0 | 1.2.0 | The fork imports it in 10+ files. |
| `cronet_http` | 1.10.0 | 1.9.0 | Android only. |
| `cupertino_icons` | 2.0.0 | 1.0.9 | Major-version gap. |
| `multistockfish` | 0.6.1 | 0.6.0 | Patch. |

Also: SDK floor `^3.12.2` (fork) vs `^3.13.0` (upstream); Flutter `3.47.3` pinned
in both `pubspec.yaml` and `.fvmrc` vs upstream's `3.47.5` and `.fvmrc: "stable"`.
`package:lint` 2.8.0 vs 2.14.0 — note `f4279fa10` cannot apply without raising
the SDK floor first.

### Removed in fork (intentional)

`firebase_core`, `firebase_crashlytics`, `firebase_messaging`,
`flutter_local_notifications`, `home_widget` — matches fork `9b127d27c` (Option B)
and `8082c0152`. Not a finding.

### Added in fork

`flutter_svg` ^2.0.17 (figurines/brand marks), `uuid` ^4.5.0 (repertoire ids).
No upstream conflict.

---

## 5. API / ABI compatibility

Probed for removals and renames upstream made that this fork still calls.
**No breaking API drift found.**

| Probe | Result |
|---|---|
| `appThemeSeed` (removed upstream by `e0952d579`) | 0 references in fork. Safe. |
| `downloadFiles` (removed upstream by `e0952d579`) | 0 references in fork. Safe. |
| `withClientCacheFor` / `withAggregatorCacheFor` (rebased onto `RefExtension.cacheFor` by `bc0213734`) | **Byte-identical signatures** on both sides. No drift. |
| `HttpNetworkImageWidget` | Upstream made it `const` and moved the implementation to `utils/http_network_image.dart`. Same public parameters. Cosmetic only. |
| `Perf`/`Speed`/`Variant` icons (moved out of the model layer by `8f940808f`) | No fork call sites use model-layer icon getters. |

---

## 6. Licensing

**Clean. No flag.**

- `LICENSE` and `COPYING.md` are both preserved from upstream.
- `README.md` §Licensing states the GPL-3.0 fork lineage and names listudy
  (AGPL, behaviour only) and chessrs (GPL, attribution).
- `docs/LITCHESS_TRIM_BASELINE.md` and `docs/INTEGRATION_MAP.md` record the
  attributions required by AGENTS.md §7.

> **Do not re-raise "387 surviving files have no per-file GPL header" as a
> finding.** It was measured and it is a false positive: upstream itself puts
> no per-file headers in the same files (`study_controller.dart`,
> `network/http.dart`, `analysis_screen.dart`, `board.dart`, `game.dart` all
> score zero upstream too). Licensing here is file-level `LICENSE` +
> `COPYING.md`, exactly as upstream does it.

---

## 7. Conflict surface

| Measure | Count |
|---|---|
| Files **modified on both sides** | **319** |
| Files **deleted in fork** but still modified upstream | **208** |
| Upstream non-merge commits with hard overlap on fork code | **89** |

Of the 208 delete/modify files, the overwhelming majority sit in subsystems the
fork cut on purpose (puzzle, broadcast, play, TV, learn, correspondence,
tournament, relation, message) — churning, not a defect.

The three worth an explicit look, because they are in **kept** territory and
were deleted in the fork:

- `lib/src/view/analysis/conditional_premoves.dart`
- `lib/src/widgets/background.dart`
- `lib/src/model/game/game_controller.dart`

These are **not** merge candidates. They are a reachability question: if any is
genuinely reachable in the fork's build, that is a bug in a cut, not something
to re-merge.

---

## 8. Flags

| Type | Severity | Description | Action required |
|---|---|---|---|
| Process | **High** | `e57fcb411` is not an ancestor of `HEAD`; upstream fixes arrive as hand-squashed cherry-picks. `git log HEAD..upstream/main` overstates the gap (§1, 5 confirmed pairs). | Create an applied-upstream ledger before attempting any sync. |
| Conflict | **High** | 319 files modified on both sides; 208 deleted in fork but still modified upstream. | Never merge wholesale. Realign per subsystem. |
| Conflict | **High** | `f4279fa10` alone sweeps 250+ files plus `pubspec.yaml` (lint + SDK floor). | Script it; do not hand-resolve. Requires the SDK floor bump first. |
| Dependency | **High** | `chessground` 10.2.0 → 10.3.0. | Test the bump in a worktree; the fork's design layer sits on top of the board widget. |
| Toolchain | Medium | Fork `sdk: ^3.12.2` / Flutter `3.47.3` pinned; upstream `^3.13.0` / `3.47.5`. `package:lint` 2.8.0 vs 2.14.0. | Raise the floor deliberately; it gates `f4279fa10`. |
| Duplication | Medium | Fork `d2f660365` (engine toggle in-flight guard) vs upstream `00bcfd8f9` + `8ded3a61c`. | Decide keep-fork vs take-upstream *before* realigning `analysis_screen.dart`. |
| Duplication | Medium | Fork `1a3a4dda8`-class fix (cancelled eval stream) may be missing — see §3. | Take upstream `1a3a4dda8`. |
| CI | Medium | Fork's `test.yml` lacks upstream's `concurrency: cancel-in-progress` (`cd25cd5f8`). Wasted CI minutes on every push. | 3-line add. Free win. |
| l10n | Medium | 56 `l10n_*.dart` files plus `app_en.arb` are on the both-sides list. Upstream's string work (`39f598c87` et al.) collides with fork `#108`. | Decide once: accept upstream's `app_en.arb`, or maintain the fork's. This decides whether the next sync is 1 commit or 56. |
| Dead-cut | Low | Three files deleted in the fork but still modified upstream (§7). | Verify reachability; do not re-merge. |
| License | — | Clean (§6). | None. |

---

## 9. Recommendations

Ordered by value per unit of effort. None of these were performed — this
document is a report.

1. **Now, ~30 min, no merge risk.** Take `cd25cd5f8` (CI concurrency) and
   `ed3dbea51` (abiFilters) by hand. Trivial, conflict-free, immediately
   useful. Then add `docs/upstream-applied.md` listing the five confirmed
   cherry-picked commits from §1, so the next audit's counts are trustworthy.
2. **Next, still cheap and directly relevant.** Take `e6be63d22` (Linux audio —
   the owner validates on `flutter run -d linux`) and `1a3a4dda8` (cancelled
   eval stream — the same defect class #104 fixed). Then attempt the
   `chessground` 10.3.0 bump **in a worktree**; it is the one dependency whose
   blast radius reaches the fork's design layer.
3. **Do not attempt `git merge upstream/main`.** There is no lineage to merge
   onto (§1). Realign subsystem-by-subsystem per `docs/upstream-realign.md`,
   highest value first: `lib/src/view/study/` + `lib/src/model/study/`, then
   `lib/src/view/analysis/analysis_screen.dart`, then the settings screens.
4. **Resolve the l10n ownership question before the next sync.** The recurring
   cost of every sync is the 56 generated `l10n_*.dart` files. One decision
   removes it permanently.
5. **Long-term.** Add a scheduled job (CI cron or a periodic agent task) that
   runs `git fetch upstream && git log --oneline HEAD..upstream/main` and
   reports the **count only**. Cheap, and it makes the gap visible before it
   reaches 167 again.

---

## 10. Summary

**1341** files diverge from upstream — 496 added, 440 modified, 404 deleted;
**167** upstream commits are unmerged at the git level, but at least **5** are
already applied by hand and there is no merge lineage to merge onto. Critical
items: `f4279fa10` (250-file lint/SDK sweep), the `chessground` 10.2.0 → 10.3.0
gap, and the duplicated engine-toggle fix. Licensing is clean; the per-file GPL
header question is a measured false positive. **Next step:** take the two
trivial CI/build commits plus the Linux-audio fix now, then realign
study → analysis → settings per subsystem instead of merging.
