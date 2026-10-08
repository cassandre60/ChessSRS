# Technical debt inventory & refactor plan

Snapshot: working branch `arena/b5e4f680-chesssrs` @ `b4635a8` (equals `origin/main`), clean tree.
Scope scanned: `lib/` (329 hand-written Dart files, 73,429 LOC excluding `l10n/`), `test/` (51,497 LOC, 1,599
test declarations), `scripts/`, `.gates/`. Generated `*.freezed.dart` / `*.g.dart` are gitignored and absent.

This file is a *report*. Nothing in it has been executed. It is not committed.

---

## 0. Method and its limits (read before trusting the numbers)

What was run, all locally and reproducibly:

| Check | How |
|---|---|
| Duplicate blocks across files | normalized sliding-window hashing over `lib/` (blanked strings/numbers/comments), plus a body-hash comparison of same-named definitions |
| Duplicated class/type names | declaration scan across `lib/` |
| Dead code | identifier frequency over `lib/` + `test/` + `scripts/`; a symbol whose identifying token occurs exactly **once** in the whole tree is unused; cross-checked with `rg` |
| Import graph / cycles | Tarjan SCC over `import`/`export` edges resolved to files |
| Function length | brace-matching extractor (call sites and closures excluded) |
| Deprecated APIs | `rg` sweep for the classic Flutter/Dart deprecations |
| Gates | `./scripts/gates.sh t0` and `t1` — both pass on the current tree |

**Hard limitation for Phase 3:** this sandbox has **no Flutter/Dart toolchain** (`flutter`, `dart`, `fvm` all
absent), the SDK archives are unreachable from the sandbox network, and `pub get`/`build_runner` cannot run.
So `dart format`, `flutter analyze` and `flutter test` **cannot be executed here** — and the generated
freezed/g files do not exist, which means even a hypothetical `dart analyze` would fail on missing parts.
Verification available in this environment is therefore:

* `./scripts/gates.sh t1` — G03 banned APIs, G07 protected paths, G08 test-weakening, G05 spec traceability, G10 ratchets;
* targeted `rg`/scripted equivalence checks against the pre-change text;
* manual review.

Anything that needs codegen (freezed/json changes) or behaviour proof belongs in a normal worktree with the
toolchain. This constraint is why several structurally-attractive items are marked **defer** below.

Scoring: **Impact** 1–5 (5 = actively causes bugs or blocks work), **Effort** 1–5 (1 = <30 min),
**Risk** L/M/H (H = touches shared/critical code or cannot be verified here). Priority = Impact/Effort.

---

## 1. Priority table

High-risk items are flagged ⚠️ regardless of score; "defer" means "do not attempt without the toolchain".

| # | Item | Location(s) | Category | Impact | Effort | Risk | Pri | Description |
|---|---|---|---|---|---|---|---|---|
| 1 | Triplicated `PgnCommentShape → Shape` extension | `view/analysis/game_analysis_board.dart:72`, `view/review/review_screen.dart:1271`, `view/study/study_screen.dart:503` | Duplication | 3 | 1 | L | 3.0 | Identical 15-line `extension on PgnCommentShape { Shape get chessground … }`, byte-for-byte in three files (verified by diff). Fix: one named extension in a shared library + one import per file. |
| 2 | `PositionKnowledgeState` rebuilt field-by-field in two methods | `review/review_service.dart:287-296` (`submitMove`), `:358-368` (`retryMove`) | Missing abstraction | 3 | 1 | L | 3.0 | Both copy the same 8 fields out of a `ReviewState`/side-effect state. The inverse mapper `PositionKnowledgeState.toReviewState()` already exists; the forward one does not. Fix: one `PositionKnowledgeState.fromReviewState(state, canonicalId:)` factory. |
| 3 | Wall-clock fallback in the review path | `review/review_controller.dart:169`, `:185` | Outdated pattern | 3 | 1 | L | 3.0 | `session?.clock.now() ?? DateTime.now()` while `clockProvider` is injectable and the review-screen widget tests override it (20+ overrides in `test/view/review/review_screen_test.dart`). The `?? DateTime.now()` branch is the untestable one. Same file already uses `ref.read(clockProvider).now()` in `_remainingDailyQuota`. |
| 4 | Row-map duplication in the SQLite repository | `persistence/sqlite_study_repository.dart:515-527`, `:546-557`, `:573-585` (knowledge state ×3); `:722-733`, `:740-751`, `:598-607` (review state ×3); `:32-40` vs `:87-95` (study row ×2) | Duplication | 3 | 2 | L-M | 1.5 | The same 10-field insert map is written three times in three methods (single, batch, atomic `saveAnswerBatch`); a fourth copy exists as raw SQL. The read direction already has `_knowledgeStateFromRow`. Fix: private `_knowledgeStateRow(...)` / `_reviewStateRow(...)` / `_studyRow(...)` helpers. |
| 5 | Deprecated `SliderThemeData.year2023`; the constant that carried it is dead code | `theme.dart:13-16` (dead), `design/theme_bridge.dart:223-226` (live) | Outdated pattern | 2 | 1 | L | 2.0 | `kSliderTheme` in `theme.dart` has zero references — it outlived the `makeAppTheme` it was written for — and its only content is the deprecated flag. **Fixed:** the constant is gone (one suppression removed). **Deferred:** the two live `year2023: false` settings, because dropping the flag changes the slider style if the SDK default has not already flipped, and that is a visual change that cannot be verified from here. |
| 6 | Prefetch constants declared three times | `review/review_service.dart:160-161`, `domain/review/review_session.dart:45-46`, `domain/review/review_engine.dart:40-41` | Magic values | 2 | 1 | L | 2.0 | `prefetchBatchSize = 25` and `prefetchRefillThreshold = 3` are repeated as independent defaults in the service, session and engine. Fix: one `kDefaultPrefetchBatchSize` / `kDefaultPrefetchRefillThreshold`. |
| 7 | Never-referenced members (dead symbols) | 20+ sites; see §3 | Dead code | 2 | 1 | L | 2.0 | Identifiers occurring exactly once in the whole tree. The interesting one: `StudyPreferencesNotifier.toggleAnimateOpponentPreMove` (`study_preferences.dart:105`) — the *read* side (`_shouldAnimateOpponentPreMove`) is live, so the animation setting can never be switched by a user. Others: `setLocale`, `getCurrentGame`, `setPremove`, `setConfirmResign`, `makeCurrentNodePgn`, `toApiForecast`, `SrsMovePair`, `kSliderTheme`, `harmonized`, `winningChancesPovDiff`, the `as…OrNull` family in `id.dart`/`chess.dart`. |
| 8 | Test-environment sniffing + two conflicting isolate thresholds | `import/pgn_importer.dart:70`, `:364`; `review/review_controller.dart:1391`; `dart:io` imported in the application layer | Missing abstraction | 3 | 2 | M-L | 1.5 | `kIsWeb \|\| Platform.environment.containsKey('FLUTTER_TEST') \|\| text.length < 8192` is duplicated; the controller then re-tests the same thing at `>= 65536`, so the policy "when to offload PGN work" exists at two sizes and three sites. Fix: one helper (e.g. `shouldOffloadPgnWork(String)`) with one documented threshold; keeps `dart:io` in one place. |
| 9 | Triplicated scope-branch setup in `startSession` | `review/review_service.dart:186-204`, `:205-220`, `:221-232` | Duplication | 2 | 2 | M-L | 1.0 | Three of the five scope branches repeat "getAllStudies → filter isActive → loop getChaptersByStudy → collect". Fix: `_loadActiveStudiesAndChapters({bool Function(Chapter)? where})`. Covered by `test/review/review_service_test.dart` (950 lines). |
| 10 | `getDueSummary` — one 255-line method computing 12 aggregates | `review/review_service.dart:401-655` | Complexity | 3 | 3 | M | 1.0 | Single pass over all decisions that fills per-study, per-chapter, per-opening, per-side and per-scope counters, then builds six progress maps. Correct and well-commented, but every new metric must be threaded through the same loop by hand. Fix: extract the per-decision tally into a small value type (`_DueTally`) + a projection function. |
| 11 | Raw exception text in user-facing snackbars | `view/review/review_scope_drawer.dart:501`, `view/review/repertoire_import_dialog.dart:191`, `:243`, `view/review/export_pgn_dialog.dart:60`, `:81`, `view/more/import_pgn_screen.dart:145`, `view/study/create_study_chapter_bottom_sheet.dart:288`, `:333`, `view/game/gif_export_dialog.dart:81` | Error handling | 2 | 1 | L | 2.0 | `showSnackBar(context, 'Import failed: $e')` interpolated the raw exception into a user-visible string — nine sites across six files. **Fixed**: the toasts now state what failed and the exception goes to a `debugPrint` one line above, using the `SEVERE: [Screen] …` form this layer already uses. All nine prefixes are unchanged, so the single test that asserts on this text (`test/view/study/create_study_chapter_bottom_sheet_test.dart:459`, `textContaining`) still holds. Not touched: `view/settings/app_log_settings_screen.dart:206` (`Text('Failed to load logs: $error')`), where showing the error *is* the screen's job. Follow-up left open: these messages are still hardcoded English; they should become `context.l10n` strings, which needs `build_runner` (see §5's caveat). |
| 12 | Prediction/analysis controllers are near-duplicates | `model/analysis/analysis_controller.dart` vs `model/study/study_controller.dart` | Duplication | 2 | 4 | H ⚠️ | 0.5 | 1,199 diff lines; identical bodies for `jumpToNthNodeOnMainline` (a416 / s512), `onCurrentPathEvalChanged` (a371 / s116), plus both mix in the same three mixins. This is inherited Lichess structure; de-duplicating is a real project, not a session. **Defer.** |
| 13 | Analysis vs Study preferences duplicate the same eight toggles | `model/analysis/analysis_preferences.dart` (93 LOC) vs `model/study/study_preferences.dart` (231 LOC) | Duplication | 3 | 3 | H ⚠️ | 1.0 | `toggleShowEvaluationGauge`, `toggleShowEngineLines`, `toggleAnnotations`, `togglePgnComments`, `toggleShowBestMoveArrow`, `toggleInlineNotation`, `toggleSmallBoard` (+ `enableServerAnalysis`) are duplicated method-for-method, as are the corresponding freezed fields. `CommonAnalysisPrefs` exists but only declares two getters. Fix needs freezed codegen and touches persisted JSON. **Defer.** |
| 14 | Presentation imports the database/persistence layer | `view/settings/srs_settings_screen.dart:7` (`db/database.dart`), `view/review/study_chapters_screen.dart:9` (`persistence/study_repository.dart`) | Tight coupling | 3 | 2 | M | 1.5 | QUALITY.md §1.1 says the presentation layer must never interact with database tables; these read `srsStudyRepositoryProvider` / `databaseProvider` directly. Fix: an application-level provider (e.g. `databaseSizeProvider`, `chaptersExportProvider`) that the screen watches. |
| 15 | Cascade-delete methods are long and interleaved with logging | `persistence/sqlite_study_repository.dart:182-271` (`deleteStudy`, 90 lines), `:357-415` (`deleteChapter`, 59) | Complexity | 2 | 2 | M | 1.0 | Two hand-rolled cascades over the same table set, each re-listing tables and logging per step; the chapter cascade mirrors the study one. Fix: a shared private `_deleteChapters(List<String> ids, {Transaction? txn})`. |
| 16 | Logging is split between `Logger` and `debugPrint` | 43 `Logger(...)` sites incl. all services; 20 `debugPrint` sites, 9 prefixed `'SEVERE: …'`, concentrated in `view/` (user, explorer, settings) | Inconsistent logging | 2 | 2 | L | 1.0 | The app owns a log pipeline (`model/log/*`, `Logger`), yet several screens bypass it with `debugPrint`, and two prefixes (`"SEVERE: [Screen] …"` vs bare) are used for the same kind of failure. Fix: route view-layer failures through the existing logger, or document the split. |
| 17 | `Study` and `StudyRepository` each name two unrelated types | `domain/study.dart:10` vs `model/study/study.dart:14`; `persistence/study_repository.dart:19` vs `model/study/study_repository.dart:23` | Naming | 4 | 4 | H ⚠️ | 1.0 | A local repertoire `Study` and Lichess's online `Study`; a local SRS `StudyRepository` and Lichess's API `StudyRepository`. `review/review_controller.dart` imports **both** repositories today. This is the single largest source of "which one?" confusion in the tree. Fix: rename the Lichess pair (`LichessStudy`, `LichessStudyRepository`) in a dedicated PR. **Defer to its own session.** |
| 18 | Very large screens and widgets | `view/review/review_screen.dart` 1,283 LOC (six `build` methods, largest 217 lines); `view/review/review_scope_drawer.dart` 1,016 (300-line `build`); `view/offline_computer/offline_computer_game_screen.dart` 1,305 (seven `build`s, largest 236); `widgets/pgn.dart` 1,510 | Complexity | 2 | 3-4 | M | 0.6 | Big but generally linear widget trees. Value is real (each is a UI seam) but the churn is large and unverifiable here. |
| 19 | Import cycles | 31-file `view/**` cycle; `persistence/study_repository.dart ↔ sqlite_study_repository.dart`; `design/design.dart ↔ design/srs_sheet.dart`; `model/common/{speed,time_increment}`; `model/analysis/analysis_controller ↔ study_controller` (via mixins) | Tight coupling | 2 | 2-3 | M | 0.8 | The two small ones are cheap: the persistence pair is a barrel file that also builds the concrete repo (move the provider out), and the design pair is a barrel importing a file that imports the barrel. |
| 20 | Unreachable files kept in a ratchet baseline | 16 files, 3,645 LOC, pinned in `test/reachability/reachability_test.dart` | Dead code | 2 | 3 | M | 0.7 | Largest: `board_settings_screen.dart` (549), `study_list_screen.dart` (412), `opening_explorer_screen.dart` (357), `create_study_chapter_bottom_sheet.dart` (343), `user_activity.dart` (331). Deliberately retained with tests for reversibility; deleting them is a product decision, not a cleanup. Leave as-is unless the owner wants the surface cut. |
| 21 | Duplicated small boilerplate | `_divisionFromPick` (`model/analysis/analysis_summary.dart:39`, `model/game/exported_game.dart:344`); `didChangeAppLifecycleState` (`view/account/account_menu.dart:61`, `view/settings/account_preferences_screen.dart:44`); `dispose` remove-observer (`utils/focus_detector.dart:171`, `account_menu.dart:55`, `account_preferences_screen.dart:38`); scroll-listener `initState` ×3 | Duplication | 1 | 1-2 | L | 1.0 | Mechanical dedupes; the analysis/study screen trio is partly dead-surface code (item 20). |
| 22 | Section scaffold repeated in the SRS settings screen | `view/settings/srs_settings_screen.dart` — 7 sections, each `Container(decoration: BoxDecoration(border: Border(top: …))) > Column(children: […])` | Duplication | 1 | 2 | L | 0.5 | `_SettingRow`/`_NavRow` helpers already exist; only the section wrapper is hand-rolled each time. |
| 23 | Magic thresholds and clamps scattered in domain code | `domain/chess_fsrs_scheduler.dart:135`, `:249`, `:299` (`clamp(0.70, 0.99)` three times); `:179` `targetRetention = 0.88` duplicating `StudyPrefs.defaults`; review animation delays `300/350 ms` (`review_controller.dart:940,961,965,1301`) | Magic values | 1-2 | 1 | L | 1.5 | Small, but the duplicate FSRS constants are the kind that silently drift when one side is retuned. |

---

## 2. Category coverage

* **Duplication** — items 1, 4, 9, 12, 13, 21, 22 (block-level and body-hash scans; the sliding-window scan's
  remaining hits were imports, l10n locale tables and data tables, which are not debt).
* **Complexity hotspots** — items 10, 15, 18. Measured spans: `getDueSummary` 255 lines;
  `_makeMoveWithEvaluation` 132 (`model/offline_computer/offline_computer_game_controller.dart:390`);
  `toggleStudyActive` 79 (`review_controller.dart:621`); `onUserMove` 76 (`:1135`); `deleteStudy` 90 and
  `deleteChapter` 59 (persistence); `_findTransposedNode` 45 (`domain/review/review_session.dart:730`);
  `AnalysisController.build` 166 (`analysis_controller.dart:146`).
* **Naming/structure** — item 17; plus `lib/src/review/` (application) sitting beside `lib/src/domain/review/`,
  and `shared_pgn_service.dart` alone at `lib/src/` root while every sibling lives in a folder. The
  `_Body`/`_BodyState`/`_BottomBar` private widget names recur in 12/5/4 screens meaning different things
  (private, so cosmetic only).
* **Outdated patterns** — items 3, 5. The classic deprecations are otherwise clean: `withOpacity`,
  `WillPopScope`, `MediaQuery.of(context).size`, `MaterialState*`, `textScaleFactor`, `MediaQueryData.fromWindow`
  and `describeEnum` all return **zero** hits outside `l10n/`.
* **Missing abstractions** — items 2, 8, and 21's `initState`/`dispose` triplets.
* **Dead code** — items 7 and 20 (§3 below).
* **Configuration/magic values** — items 6, 23.
* **Inconsistent error handling/logging** — items 11, 16; plus two silent swallows
  (`widgets/feedback.dart:310`, `view/review/export_pgn_dialog.dart:169`). For balance:
  `email_login_screen.dart:164` catches and returns `true`, but that one is deliberate and documented
  ("a check that could not be made lets the name through") — not debt.
* **Tight coupling** — items 14, 19.

---

## 3. Dead-code evidence

*File-level.* The repo already owns this: `test/reachability/reachability_test.dart` traces imports **and**
exports from `lib/main.dart` and pins the 16 unreachable files listed in item 20. Re-running that traversal
reproduces the same set, so there is no undiscovered unreachable file.

*Symbol-level.* The file-level ratchet explicitly cannot see "imported but never constructed", and that is
where the remaining debt is. Symbols whose identifier occurs exactly once in `lib/` + `test/` + `scripts/`
(so: declaration only, no call, no tear-off, no test reference):

```
model/account/account_preferences.dart   setPremove, setConfirmResign
model/analysis/analysis_controller.dart  makeCurrentNodePgn
model/analysis/forecast.dart             toApiForecast
model/clock/chess_clock.dart             setTime            (file itself unreachable)
model/common/chess.dart                  asSquareOrNull, asVariantOrNull
model/common/eval.dart                   winningChancesPovDiff
model/common/id.dart                     asStringIdOrNull, asGameIdOrNull, asPuzzleIdOrNull,
                                         asChallengeIdOrNull, asBroadcastTournamentIdOrNull,
                                         asBroadcastRoundIdOrNull, asBroadcastGameIdOrNull,
                                         asTeamIdOrNull, asFideIdOrNull
model/common/speed.dart                  asSpeedOrNull
model/engine/opponent_level.dart         fromLevel
model/game/game.dart                     playerSideOf, materialDiffAt, fenAt, moveAt, positionAt,
                                         archivedWhiteClockAt, archivedBlackClockAt, lastMaterialDiffAt
model/game/game_preferences.dart         toggleChat         (file itself unreachable)
model/game/game_status.dart              asGameStatusOrNull
model/game/player.dart                   setOnGame, setGone
model/offline_computer/…_controller.dart goForward, goBack
model/settings/general_preferences.dart  setLocale
model/study/study_preferences.dart       toggleAnimateOpponentPreMove   ← live reader, no writer
model/user/user_repository.dart          getCurrentGame
styles/styles.dart                       harmonized
theme.dart                               kSliderTheme
design/notation_line.dart                SrsMovePair
```

Framework-invoked overrides (`didAddProvider`, `didPush`, `updateShouldNotify`, `loadImage`, `obtainKey`,
`didChangeLocales`) are **not** dead — they are called by Riverpod/Flutter — and were excluded by inspection.

---

## 4. Recommended "top N" for a focused session

Chosen for verified, low-risk value that can be done with the verification the repo supports (gates + review),
ordered so each is an independent commit:

1. **Item 1** — one shared `PgnCommentShape → Shape` extension (3 dead copies removed). *(Attempted and
   **reverted** — §5. It is the one change in this batch that CI rejected.)*
2. **Item 2** — `PositionKnowledgeState.fromReviewState` factory; two hand-written copies removed. *(Done — §5.)*
3. **Item 4** — `_…Row(…)` map helpers in the SQLite repository (3× + 3× + 2× copies removed). *(Done — §5; ended up 6 builders over 16 insert sites.)*
4. **Item 3** — no wall-clock read in the review path. *(Done — §5; the fallback turned out to be unreachable, so it was deleted rather than re-wired.)*
5. **Item 5** — drop the deprecated `year2023` pair and the dead `kSliderTheme`. *(Batch 1 did the
   dead constant; the two live flags are deferred — see §5.)*
6. **Item 6** — single source for the prefetch defaults. *(Done — §5.)*
7. **Item 11** — stop interpolating raw exception text into user-facing snackbars. *(Done — §5; the copy
   decision was to keep every message prefix and log the exception instead.)*
8. **Item 9** — collapse the triplicated scope setup in `startSession`.
9. **Item 8** — one "offload PGN work" helper with one documented threshold (note: this one *does* move a
   behavioural boundary; it needs a deliberate decision on 8 KB vs 64 KB). *(Deferred in batch 1.)*
10. **Item 14** — move the two presentation→persistence reads behind application providers.

**Explicitly deferred (and why):** items 12, 13, 17 need codegen and/or wide renames and cannot be verified
without the toolchain; 18 and 20 are product-scale decisions; 15, 19, 10 are legitimate but each deserves its
own PR with `flutter analyze` + tests available.

**Repo rules that constrain every Phase 3 diff** (from `AGENTS.md`, `GATES.md`, `.gates/protected-paths.txt`):
protected paths (`pubspec.yaml`, `analysis_options.yaml`, `verify`, `.gates/*`, `scripts/gates/*`,
`test/fixtures/*`, the referee docs) must not be touched; no test may be weakened (G08) and no `skip:` added;
each fix is its own Conventional Commit; `./scripts/gates.sh t1` must stay green; a refactor PR is expected to
carry "no test files modified + behaviour-equivalence evidence", which is only satisfiable with the toolchain.

---

## 5. Status: what batch 1 (this branch) changed

Six commits, one concern each, each verified as far as this environment allows (see §0):

| Item | Commit | Change | How it was checked |
|---|---|---|---|
| 2 | `refactor(review): add PositionKnowledgeState.fromReviewState factory` | the two hand-written field copies in `ReviewService` replaced by a domain factory | the factory's field list is byte-equivalent to each removed copy (scripted comparison, 3/3 sites) |
| 4 | `refactor(persistence): one row builder per table in SqliteStudyRepository` | 6 row builders; 16 insert sites now call them | every pre-change map is reproduced key-for-key by its builder, and each call site passes the receiver in scope (16/16, scripted) |
| 3 | `refactor(review): take "now" from the session clock, not the wall clock` | removed an unreachable `?? DateTime.now()` from two getters | the removed branch is provably unreachable (the guard above it returns unless the session exists); the widget test that asserts "Next review in 1 day" builds its session with the same `FixedClock` the provider is overridden with |
| 5 | `chore(theme): delete the unreferenced kSliderTheme constant` | dead constant deleted | zero references tree-wide; analyzer-suppression ratchet drops 18 → 17 |
| 6 | `refactor(domain): one source for the prefetch defaults` | `kDefaultPrefetchBatchSize` / `kDefaultPrefetchRefillThreshold` replace three independent `25`/`3` defaults | the literals are gone from all three sites; no other `25`/`3` prefetch default exists |

**Item 11** followed as a seventh commit on the same branch (`fix(view): keep raw exception text out of error
toasts`) once the copy decision was made: keep every message prefix, drop the `": $e"` suffix, log the exception
with the layer's existing `SEVERE:` convention. It is a deliberate user-visible copy change and is called out as
such in the commit and in the PR body.

Gate status for the branch: `./scripts/gates.sh t1` passes (G03 banned APIs, G07 protected paths — nothing
protected touched, G08 test-weakening — no test file modified, G05 spec traceability, G10 ratchets —
`analyzer_suppressions` improved 18 → 17, `domain_loc` 3052 → 3076 within the ±150 tolerance).

### Reverted: item 1, the shared `PgnCommentShape → Shape` extension

Item 1 was in this branch and was taken back out. It is the only change in the batch that CI rejected, and it
was found by bisecting the suite, not by reading the diff:

| Branch state | `flutter test` |
|---|---|
| all seven items | 1009 passed, **68 failed** |
| `lib/` at the base commit (item 1 absent) | all passed |
| items 1, 5, 11 only | 1011 passed, **68 failed** |
| **item 1 alone** | 1011 passed, **68 failed** |
| items 2, 3, 4, 5, 6, 11 (what ships) | all passed |

So the 68 failures are item 1's and nothing else's, and they are deterministic — the same count on every run.
What is *not* established is the mechanism, and that is worth saying plainly: this environment has no Dart SDK
and cannot read Actions job logs, so it can only count failures, not name them. The three extension bodies were
byte-identical, the shared one resolves at all three call sites (it compiles), and no second `chessground`
extension on `PgnCommentShape` exists in the tree — so the failure is in something the diff does not show, and
the honest move is to drop the refactor rather than to guess at it.

The duplication is real and the fix is still worth doing; it needs `flutter test` to be runnable locally, where
the failing assertions are one command away. Re-raising it should start from the test names, not from this diff.

### Verification

`./scripts/gates.sh t1` passes (`analyzer_suppressions` 18 → 17, `test_declarations` 1509 → 1599, `domain_loc`
3090 inside the ±150 tolerance, no protected path touched, no test file modified).

`test.yml` was then run against the branch and is **green end to end**: `dart format`, `flutter analyze`
(no exclusions, no suppressions added) and `flutter test` all pass. That is the authority for the six items
above, and it is also what caught item 1. One caveat on method: the sandbox cannot read job logs, so a failing
run can be counted but not read — which is why finding item 1 took four bisect runs instead of one log.

## 6. What remains, in priority order

1. **Item 11** — *done* (§5). Its l10n follow-up (the messages are still English literals) remains, and needs
   `build_runner`.
2. **Item 1** — *attempted and reverted* (§5). The three copies are still where they were. It needs a
   toolchain: the change looks correct and fails 68 tests, and only the test names will say why.
3. **Item 8** — one "when to offload PGN work" helper; the 8 KB and 64 KB thresholds must be reconciled
   deliberately, which is a behaviour decision, not a refactor.
4. **Item 14** — presentation importing `db/` and `persistence/` (QUALITY.md §1.1). A wider sweep than the
   first pass found a **third** file: `view/analysis/analysis_hub_screen.dart:9` (`persistence/persistence.dart`,
   read at `:175`, watched at `:190`) alongside `view/settings/srs_settings_screen.dart:7` and
   `view/review/study_chapters_screen.dart:9` (`:46`, `:93`).
5. **Item 9** — the triplicated scope setup in `startSession`; worth doing with the test file runnable
   (`test/review/review_service_test.dart`, `review_side_scope_test.dart`, `review_order_test.dart` cover it).
   Note it would introduce a record return type, which nothing in `lib/` uses today — decide that first.
6. **Items 10, 15, 19** — each deserves its own PR with `flutter analyze` + the focused test file available.
7. **Items 12, 13, 17, 18, 20** — deferred as before: codegen, wide renames, or product decisions.

A follow-up session with the toolchain available can take items 14 → 9 in that order, then the l10n pass over
the strings item 11 left as English literals.
