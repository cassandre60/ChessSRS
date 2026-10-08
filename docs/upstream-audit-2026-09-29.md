# Upstream Diff Audit — 2026-09-29

Fork `chess-repertoire-srs` vs `lichess-org/mobile`. **Read-only audit. No merge, rebase,
code change, push, build, or test was performed. No remotes were altered.**

## 0. Basis & method

| Item | Value |
|---|---|
| Fork HEAD | `ea1d09678` (2026-09-29, `docs(agents): local test budget… (#83)`) |
| Upstream HEAD | `e57fcb411` (2026-09-29, `Add more missing translations`) |
| Merge-base | `6e1d045a0` (2026-09-11, `Bump version`) |
| Upstream ahead | **125 commits** (`git rev-list --count HEAD..upstream/main`) |
| Fork ahead | **196 commits** (cuts + Diagram reskin + SRS/review feature work) |
| Raw overall diff | **1187 files**: 460 added, 287 deleted, 438 modified, 2 renamed (`git diff --name-status upstream/main...HEAD`) |
| Sync | `git fetch upstream --no-tags` only. Triple-dot diffs (`upstream/main...HEAD`) show fork-side change since merge-base; `HEAD..upstream/main` logs show upstream-ahead commits. File listings capped per subsystem; rest summarized by directory. |

Product authority applied (Step 0): `PRODUCT.md`, `MVP.md`, `CUT_PROPOSALS.md`, `AGENTS.md`
(§7 licensing, §3/§3.1 budget). **`docs/upstream-realign.md` does not exist** in this
checkout (checked `docs/` listing) — relevance was decided from `CUT_PROPOSALS.md` +
`PRODUCT.md` non-goals instead.

Remote check (Step 1): `upstream → https://github.com/lichess-org/mobile.git` for
**both fetch and push** — the push-URL trap is real. Nothing was pushed; push is
impossible to do accidentally here since no push command was run.

Pre-existing working-tree dirt (untouched): 52× `lib/l10n/*.dart` formatting churn
(known codegen artifact, see `AGENTS.md` Lessons 2026-09-28) plus 3 untracked files from
other agents (`POLISH_TASKS.md`, `audit.md`, `chesssrs-audit-and-scene-log.md`).
This audit wrote exactly one file: this report.

## 1. Your changes vs upstream (per subsystem)

| File/subsystem | Category | Change | Notes |
|---|---|---|---|
| study (`lib/src/model/study`, `lib/src/view/study`) | Fork-diverged | 13 files M (6 model + 7 view); server-study kept (C3/C18 import path) | Overlaps upstream Takes `320c6a2ad`, `17d7a3cd8`, `8ded3a61c`, `f24cfee4c`. Controller still socket-based — see §2 verdict |
| settings (`model/settings`, `view/settings`) | Fork-diverged + Cut-intended | 15 M, 3 D, 1 A | D = `brightness.dart`, `background_theme_choice_screen.dart`, `settings_screen.dart` (UI-F background removal, deliberate per `CUT_PROPOSALS.md`); A = `srs_settings_screen.dart` (fork-new) |
| analysis (`model/analysis`, `view/analysis`) | Fork-diverged + Cut-intended | 25 M, 1 D, 1 A | D = `conditional_premoves.dart`; A = `analysis_hub_screen.dart` (fork-new). C15 GREY — left structurally intact |
| engine (`model/engine`, `view/engine`) | Fork-diverged | 17 model + 3 view M; C13 GREY, kept | Fork still pins **unpublished git refs** for `lc0`/`multistockfish` + `dependency_overrides` that upstream removed after publishing (see §3) |
| review/persistence (`review/`, `domain/`, `import/`, `persistence/`, `view/review`, `db/database.dart`) | Fork-new (no upstream counterpart) | ~40 files A, `database.dart` M | `lib/src/review`, `domain`, `import`, `persistence` do not exist upstream. Local SRS stack; nothing to take |
| shared widgets/styles/theme/app | Presentation-only + Fork-diverged | `design/` 17 A (Diagram system, deliberate D016); `tab_scaffold.dart` D (2-tab shell, deliberate Step 12); `background.dart`, `expanded_section.dart`, `server_outage_display.dart`, `side_indicator.dart`, `text_badge.dart`, `puzzle_icons.dart` D (deliberate Steps 2/17); ~30 widgets M (mostly reskin) | Visual diffs are `Skip` per Step 0; logic hunks inside M files assessed per-commit in §4 |
| l10n (`lib/l10n`, `intl.dart`, `localizations.dart`) | Skip (presentation/pipeline) | 52 generated M + 2 M | Upstream-ahead is ~30 Crowdin/i18n churn commits; flows through the kept l10n pipeline, no action. Convention is hardcoded-English-first |
| platform/splash (`android/`, `assets/`, splash) | Presentation-only + Fork-diverged | Brand assets A (`brand/`, `figurines/`, Diagram fonts/pieces); `board-thumbnails/` D (deliberate); `MainActivity` + widget provider R (package rename); splash webp→png; `build.gradle.kts` M | Upstream `ed3dbea51` (abiFilters) is a Take — §4 |
| cut features (puzzle, lobby/play, tv, tournament, broadcast, watch, correspondence, learn, blog/recap/announce, OTB, clock-tool, social views, relation, message) | Cut-intended | 91 D in sampled cut paths; 287 D overall | Gone on purpose per `CUT_PROPOSALS.md` Steps 1–18. Absence is `Intended`, never a flag; no Take may restore these |
| network/auth/socket (`network/`, `model/auth`, socket pool) | Fork-diverged (kept: C3 auth, C17 socket, C18 HTTP) | `http.dart` M, `auth_repository.dart` M, `app_links_service.dart` M | Overlaps Takes `214bb0353`/`a99dad8a1`, `bc0213734`, `e0952d579`, `60309eb8d` |
| `pubspec.yaml` | Fork-diverged | Renamed `chess_srs` 0.2.0; see §3 drift table | Do not hand-merge; needs a dedicated dependency-alignment task with CI |

## 2. Required callout — Study subsystem verdict

**Verdict: upstream's study screen + controller fundamentally require lichess IDs,
sockets, and chat. They cannot run against local study data with skinning only.**

File/line evidence (upstream `upstream/main`, identical structure in fork HEAD):

- Entry requires a server ID: `lib/src/model/study/study_controller.dart:37`
  `typedef StudyOptions = ({StudyId id, StudyChapterId? initialChapter});`
  and `lib/src/view/study/study_screen.dart:43`
  `StudyScreen({required final StudyOptions options, …})`.
- `build()` is server-first (`study_controller.dart:93–122`): it awaits
  `studyRepository.getStudy(id: …)` (server GET), then opens
  `socketPool.open(Uri(path: '/study/${options.id}/socket/v6'), version: study.socketVersion)`
  (`:105–108`) and subscribes to socket events (`:109–110`); there is no local-data path.
- Chat is structural, not cosmetic: `chatId => options.id` (`:83`), `chatReportResource =>
  'study/${options.id}'` (`:87`), `initChat(chapter.study.chat)` inside `build()` (`:119`),
  `chatEnabled => study.chat != null` (`:834`), plus `ChatMixin<StudyState>` (`:57`).
- Repository is REST-bound (`study_repository.dart:63–129`): `GET /study/…`,
  `GET /api/study/<id>.pgn` (`:87–89`), `POST /api/study/<id>/import-pgn`,
  `DELETE /api/study/<id>/<chapter>`, `POST /api/study` for creation.
- Writes go back over the socket: `_sendMoveToSocket` (`:331`), like via socket (`:277`),
  `_recordChange` sends `socketEvent + chapter.id` (`:500–504`); server analysis via
  `ServerAnalysisSource.studyChapter(studyId:, chapterId:)` (`:758`).
- Fork status: fork's `study_controller.dart:39–117` and `study_repository.dart:68–103`
  are still socket/`StudyId`-based (fork M, not decoupled).

A local backend would have to replace identity (`StudyId` → local id), transport
(socket → no-op/local bus), chat (→ disabled), and repository (→ sqlite/local) — i.e. a
backend swap behind the same state shape, not a skin. The fork's separate
`persistence/sqlite_study_repository.dart` + `import/` + `domain/` + `review/` stack is
the correct seam; the pending study Takes (`320c6a2ad`, `17d7a3cd8`) are server-feature
work that inherits this dependency. Next step: a dedicated study-sync task that decides
local-backend-vs-server per `MVP.md` (local PGN import is MVP; Lichess import is an
explicit future horizon), not a cherry-pick.

## 3. Required callout — Dependency drift (`pubspec.yaml`)

No audit/build commands run (per task constraints); breaking-change notes below come
only from the version deltas themselves — treat `⚠` rows as "check the changelog in the
alignment task", not as confirmed breakage.

| Package | Fork | Upstream | Flag |
|---|---|---|---|
| `dartchess` | `^0.13.1` | `^0.14.0` | **Behind** ⚠ minor bump on the single chess representation (`QUALITY.md`) — changelog check required |
| `chessground` | `^10.2.0` | `^10.3.0` | **Behind** ⚠ board renderer; check changelog (upstream `54f7eeedd`) |
| SDK / Flutter | `^3.12.2` / 3.47.3 | `^3.13.0` / 3.47.5 | **Behind** (upstream `f4279fa10`, `1e0baf1e0`, `4fe1a4b37`) |
| `lint` | `^2.8.0` | `^2.14.0` | **Behind** (upstream `f4279fa10`) |
| `lc0` | git pin `04284fa` | `^0.1.0` published | **Behind** — upstream `db80c5a2a` moved to published sources; fork keeps stale git ref |
| `multistockfish` | git pin `896c388` + `dependency_overrides` block | `^0.6.0` published, overrides removed | **Behind** — same as above; fork keeps stale pins + overrides |
| `flutter_markdown_plus` | `^1.0.12` (pub.dev) | git pin `HaonRekcef…74dd63f` | **Diverged** — upstream `fbea4165e` migration; follow only if the fork hits the same issue |
| `cupertino_ui` | `^1.1.1` | `^1.0.0` | Ahead (fork) — no action |
| `firebase_core` / `crashlytics` / `messaging` | `^4.15.0` / `^5.4.0` / `^16.7.0` | `^4.13.0` / `^5.2.7` / `^16.5.0` | Ahead (fork) — no action (C1/C2 GREY, untouched) |
| `file_picker` | `^13.1.0` | `^13.1.0` | In sync (both upgraded) |
| `flutter_secure_storage` | `^11.2.0` | `^11.0.0` | Ahead (fork) — no action |
| `flutter_local_notifications` | `^22.3.1` | `^22.3.0` | Ahead (fork) — no action |
| `flutter_svg` / `uuid` | `^2.0.17` / `^4.5.0` | absent | Fork-added (Diagram brand + local IDs) — no action |

Also: `ed3dbea51` (remove unrequired `abiFilters`) and `44b341d60`/`2c45d9720`
(rubyzip 2.4.1→3.4.0, iOS/Android) are Take-later build/CI items, not code Takes.

## 4. Upstream changes not in fork (Take candidates only)

Effort assumes the fork-diverged overlap noted in §1 (nearly every kept-subsystem file
is M on both sides; only `openings_database.dart` is untouched in fork). Risk applies
only to Logic-shared / Fork-diverged rows. Cut-subsystem commits (~40: learn, practice,
puzzle, lobby/TV/tournament/broadcast/correspondence, social/friends/inbox/relation,
team-social, game-server) are `Intended` absences and excluded. ~30 i18n/Crowdin commits
are `Skip` (pipeline). Toolchain/dep upgrades are Take-later (see §3 + list after table).

| Commit | Type | Summary | Merge effort | Risk |
|---|---|---|---|---|
| `1a3a4dda8` | fix | Cancel eval-stream subscription of a replaced eval request (+149-line test) | Trivial | Low |
| `00bcfd8f9` | fix | Engine button popup bug (`view/engine/engine_button.dart`, 1 file) | Trivial | Low |
| `7fc986dc4` | fix | Maia weight-file claims compared by URI, not path (`weights_service.dart`) | Trivial | Low |
| `b87e54c79` | fix | Guard controller entry points against valueless state (take retro hunk only; tournament hunk is cut) | Trivial | Low |
| `fd4b528a1` | fix | Blink next-mistake button in retro review (1 line, `retro_screen.dart`) | Trivial | Low |
| `498ce10a7` | fix | Await openings-database cleanup (`db/openings_database.dart` — untouched in fork, applies clean) | Trivial | Low |
| `4d19138fc` | refactor | Unify duplicated NAG annotation tables (`widgets/pgn.dart` + test) | Moderate | Low |
| `4b44389e1` | fix | `HttpNetworkImageWidget`: read static HTTP client once, pass through height | Trivial | Low |
| `bc0213734` | refactor | Rebase `withClientCacheFor`/`withAggregatorCacheFor` on `RefExtension.cacheFor` (`network/http.dart`, net deletion) | Trivial | Medium |
| `60309eb8d` | fix | App-links exact host check in `onLinkifyOpen` (+52-line test) | Trivial | Low |
| `25cf0fae5` | feat | Board editor accepts illegal-position FENs (+tests, kept C16 tool) | Moderate | Medium |
| `c60a0edd8` | perf/data | Index `openings.epd` for per-position lookup (+script +test; additive) | Moderate | Low |
| `e0952d579` | cleanup | Remove unused `downloadFiles` + deprecated `appThemeSeed` (fork still carries both — verified by grep in `network/http.dart:417`, `general_preferences.dart:107–119`) | Moderate | Medium |
| `8ded3a61c` | refactor | Extract `EngineToggleButton`, dedup toggle guard across bottom bars (3 files, all fork-diverged) | Moderate | Medium |
| `f24cfee4c` | refactor | Move view contracts (eval gauge, pgn) into model (`node.dart`, `position_evaluator.dart`, `engine_gauge.dart`, `pgn.dart`) | Moderate | Medium |
| `320c6a2ad` | feat | Button to add PGN to study in analysis + `study_list.dart` extraction (+tests; touches cut learn screen; server-study-bound per §2) | Complex | High |
| `17d7a3cd8` | feat | Button to create a new study + repository `POST /api/study` (server-study-bound per §2) | Complex | High |
| `f8f919d74` | refactor | Shared JSON row helper — take `db/json_row.dart` (new) + `game_storage.dart` hunk only; correspondence/puzzle hunks are cut | Moderate | Medium |
| `ed3dbea51` | build | Remove unrequired `abiFilters` from `build.gradle.kts` (3-line deletion) | Trivial | Low |
| `e6be63d22` | feat | Native Linux audio playback (`sound_service.dart`, +93/−6; desktop-only path) | Moderate | Medium |
| `214bb0353` + `a99dad8a1` | fix | Email-login code params in POST body, not query string (auth kept C3; pair as one Take) | Trivial | Medium |

Take-later with reason (not Takes): `b51f4997b` FCM refactor (C2 GREY notifications —
leave untouched); `792ee93ac` memoization (touches cut `friend_screen`); `8f940808f`
icon move (presentation-adjacent, spans many cut files); `426cae508` user-repo hunk
(social periphery, no test); `7b5e74943` game-history index (serves cut server-game
lists); `f4279fa10` lint/SDK floor + Flutter/dep upgrades (`1e0baf1e0`, `4fe1a4b37`,
`4533954c7`, `1ead7857a`, `a5005e7e2`, `fbea4165e`, swift/js-yaml/ci-deps/rubyzip bumps —
toolchain batch with CI); `1e66ebee3` + `31fe0c52c` CI config; `a26cb3293`
background-selection fix (`Skip` — fixes UI-F, which the fork deliberately removed);
`c5f7a8058` swallowed-catch logging (both hunks in cut challenge/puzzle files —
Cut-intended); `4d9cb3c12` move-expiration timer + `6a3a0d6c1` game-screen routing
(cut server-game views — Cut-intended); `0c41bb4db` team updates (l10n-only — Skip).

## 5. Flags (Fork-diverged + License only)

| Type | Severity | Location | Evidence | Next step |
|---|---|---|---|---|
| Fork-diverged | High | `lib/src/model/study/study_controller.dart:39–117`, `study_repository.dart`, `view/study/study_bottom_bar.dart`, `study_list_screen.dart` | Both sides M; upstream `320c6a2ad`/`17d7a3cd8` pending but server-bound (§2); fork controller still socket-based | Dedicated study-sync task: decide local-backend seam first (§2). Do not cherry-pick |
| Fork-diverged | Medium | `pubspec.yaml` engine pins (`lc0` git `04284fa`, `multistockfish` git `896c388` + `dependency_overrides`) + `dartchess ^0.13.1`, `chessground ^10.2.0`, SDK/lint floor | `git diff merge-base..upstream/main -- pubspec.yaml` (upstream `db80c5a2a`, `54f7eeedd`, `f4279fa10`); fork `pubspec.yaml:8–10,17,26,58–74` | Dependency-alignment task verified on CI (no local builds per constraints); check dartchess/chessground changelogs for breakage |
| Fork-diverged | Medium | `lib/src/network/http.dart`, `lib/src/model/settings/general_preferences.dart` | Both M; fork retains `downloadFiles` (`http.dart:417`) + `appThemeSeed` (`general_preferences.dart:107–119`) that upstream `e0952d579` removed; `bc0213734` also pending | Take up `e0952d579` + `bc0213734` together in one HTTP-layer task with CI |
| Fork-diverged | Medium | `lib/src/model/analysis/*`, `lib/src/view/analysis/*`, `lib/src/model/engine/*` (eval mixin, weights, engine button, position evaluator) | Both M almost file-for-file (§1); upstream Takes `1a3a4dda8`, `00bcfd8f9`, `7fc986dc4`, `b87e54c79`, `fd4b528a1`, `8ded3a61c`, `f24cfee4c` pending | Per-commit cherry-pick batch, smallest hunks first; each with its upstream test, CI-verified |
| Fork-diverged | Low | `lib/src/widgets/pgn.dart`, `lib/src/view/engine/engine_gauge.dart`, `lib/src/model/common/node.dart`, `lib/src/app_links_service.dart`, `lib/src/model/auth/auth_repository.dart`, board-editor pair, `sound_service.dart`, `game_storage.dart`, `user*.dart`, `network_image.dart`, `db/database.dart` | Both M (overlap check §1); upstream Takes pending for most | Fold into the per-commit batches above; `openings_database.dart` (upstream `498ce10a7`) is the one clean apply — take it first |
| License | — | — | **No flag.** `git diff upstream/main...HEAD -- LICENSE COPYING.md` is empty (both preserved); upstream carries no per-file headers (first-4-lines scan over 200 `lib/src` files found zero GPL/Copyright headers — notices live at root by design); fork-new files fall under `COPYING.md` default | None. Keep preserving root files on every cut (AGENTS.md §7) |

## 6. Summary

- **21 Take rows (22 commits)** in §4: 9 Trivial, 9 Moderate, 2 Complex (+1 Trivial pair); 12 Low, 7 Medium, 2 High risk. Cleanest first applies: `498ce10a7`, `fd4b528a1`, `00bcfd8f9`, `7fc986dc4`.
- **5 flag rows, 0 license flags**: 1 High (study overlap), 2 Medium (engine pins, HTTP layer), 1 Medium (analysis/engine batch), 1 Low (widget/auth/misc overlap).
- **Study verdict in one line:** upstream study needs lichess IDs, `/study/<id>/socket/v6`, chat, and `/api/study` REST (`study_controller.dart:37,105–110`, `study_repository.dart:63–129`) — reusable only via a local-backend swap, not skinning.

*Method note: no merge, rebase, checkout of upstream code, push, build, or test was run.
No remotes altered. Follow-ups are separate tasks with their own prompts and CI runs.*

## 7. Application log (2026-09-29/30)

Owner delegated all decisions; the 6 Takes were applied one-worktree-per-task,
targeted-tests-only locally, each merged after green CI. Skips and Take-laters stand
as decided in §4/§6.

| Take | PR | State |
|---|---|---|
| `498ce10a7` openings cleanup | #89 | Merged |
| `c60a0edd8` openings.epd index (script adapted to the fork's atomic-rebuild script) | #90 | Merged |
| `60309eb8d` app-links exact host (test helper uses classic constructors — see note) | #91 | Merged |
| `25cf0fae5` board-editor illegal FENs (`BottomBarButton.onTap` → `SrsTextButton.onPressed`) | #92 | Merged |
| `bc0213734` + `e0952d579` HTTP pair (`dart:async` kept — `Future`/`Stream` need it) | #93 | Merged |
| `214bb0353` + `a99dad8a1` login POST body (needs one live email-code login to confirm) | #94 | Merged |

Port notes (refine §3 drift table and future ports):

- Resolved `dartchess` is the `ed64d8a` git pin (0.14.0-prerelease, Zobrist branch), not
  pubspec's `^0.13.1` — so `Castles.fromSetup`/`FenException` were available and the
  "behind on dartchess" flag is softer than the version strings suggest. The
  `lc0`/`multistockfish` stale pins and SDK/lint floor flags stand.
- Fork SDK floor is 3.12: upstream's `class const` primary-constructor form (needs 3.13)
  does not compile here. Ports must use classic constructor syntax until the SDK
  Take-later lands.
- `test/db/` did not exist in the fork; `c60a0edd8` created it with the index
  regression test. Future DB takes now have a home for coverage.
