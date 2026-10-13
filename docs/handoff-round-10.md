# Round 10 Handoff: Performance Audit & Optimization

This document is the operational handoff for **Round 10** of the whole-codebase review
program (`docs/review-program.md`). It records the exact state of the repository, what
rounds 1–9 delivered, the open items in the carry-forward log, and the concrete execution plan
for Round 10.

---

## 1. Current Repository State

- **Branch / Tip**: `origin/main` @ `70fbf87f9`
- **Working Tree**: Clean (`git status` clean, no dirty files).
- **CI Status**: Green across all GitHub Actions workflows (`Tests`, `Gates`).
- **G05 Spec Traceability**: 43 invariants in `SPEC.md`, 43 referenced by tests (100% covered).
- **G07 Protected Paths**: Intact; referee files untouched.
- **G10 Ratchets**:
  - `direct_dependencies`: 65
  - `analyzer_suppressions`: 17
  - `test_skips`: 10
  - `test_declarations`: 1743
  - `domain_loc`: 3337 (ceiling: 3350; headroom: ~13 lines)

---

## 2. Review Rounds 1–9 Completion Matrix

| Round | Focus Area | PR | Commit | Key Accomplishments |
|---|---|---|---|---|
| **1 & 2** | Trust Boundaries & Persistence | #32 | `b05275d7a` | PGN tag escaping (§8.1.1); desktop OAuth loopback 404-and-wait loop; fixed `onUpgrade` tie-break crash in legacy canonical state backfill. |
| **Gates** | Gate Maintenance | #40 | `c50ac3e50` | Regenerated stale red-team patches `rt-03` and `rt-05` against post-library directive code; restored 100% recall (9/9). |
| **3** | Scheduling Domain | #41 | `8f8e84a80` | Derived `completedCount` from quota set; preserved pending re-tests across daily quota cut; due-aware continuation selection; `StateError` guard on empty expected moves; restored full 18% λ0 contagion haircut (`-(depth-1)/τ`). |
| **4** | Network & Sync | #42 | `c014fa25b` | Parameterized secret redaction in exception messages and URLs; desktop OAuth `state` binding (verified against Lila source + live `/oauth` probe); cancelled orphaned version-gap retry timer on socket disconnect. |
| **5** | State & Lifecycle | #43 | `bb1e5477b` | Discarded stale pending advancements when study toggle/delete replaces the session; prevented practice mode from inflating daily reviewed counts. |
| **6** | UI & Accessibility | #56 | `a5a11f0f6` | Fixed `ink3` token contrast to meet WCAG AA (4.5:1 on light/dark grounds); selected-row quiet label step-up to `ink2`; 44px hit targets on accent dots and clear search; resolved 900px first-launch breakpoint overflow. |
| **7** | Localisation | #70 | `f343495c7` | Reconnected 21 unmanaged ARB keys into `translation/source/mobile.xml` as pipeline-owned `mobile*` keys; migrated ~90 review-surface strings; preserved surgical formatting pattern; added fallback rendering test. |
| **8** | Dependencies & Build | #83 | `bd22864e6` | Pruned dead iOS capabilities (photo library usage, background modes, push entitlement); removed dead `/tv`, `/broadcast`, `/tournament` link patterns; patched npm advisories (`js-yaml` dropped, `xml2js` bumped to 0.6.2); verified 0 OSV pub advisories. |
| **9** | Tests & Gates | #86 | `70fbf87f9` | Replaced vacuous 0-assertion `/tv` test with honest rejection check; closed G02 double-quote import blind spot in `domain_boundary_test.dart`; replaced 13 load-sensitive `pumpAsync` sleeps with deterministic `pumpUntilFound` polling (TEST-FIX-19); documented G08 multiline skip blind spot. |

---

## 3. Carry-Forward Log (Open Items from Prior Rounds)

These items are documented in `docs/review-program.md` and `docs/review-register.md`. They are
not blockers for Round 10, but must remain tracked:

1. **review-1 C4**: Switching `schedulerType` reinterprets `stability` (needs product decision on migration vs warn-and-confirm).
2. **review-1 C6**: `isColdStart` never re-arms after a lapse (needs product definition of "forgotten").
3. **review-1 D5**: `repetitionCount` semantics differ between FSRS and simple schedulers (needs domain unification design).
4. **R6-F3**: `SrsSegmented` 44px height is blocked on analysis layout redesign (taller tab strip shifts touch coordinates to Forward button).
5. **time-i18n**: Relative time strings in review controller need ICU plural syntax with English edge semantics.
6. **srs-settings copy**: ~40 settings labels and descriptions remain hardcoded English pending copy freeze.
7. **chapters copy**: `StudyChaptersScreen` is a legacy Lichess surface pending cut decision; copy translation deferred.
8. **multistockfish +4**: Git pin is 4 commits behind upstream main; fast-forwardable by engine maintainers.
9. **Arabic placeholder**: `mobilePlayersMatchingSearchTerm` dropped `{param}` upstream in Crowdin; tracked for translators.
10. **domain_loc ratchet**: Currently 3337 lines against the 3350 ceiling (~13 lines headroom); any domain expansion requires an owner-approved baseline bump.

---

## 4. Round 10 Execution Blueprint: Performance

**Objective**: Audit the critical interaction and startup paths against `docs/performance.md`,
verify existing optimizations, benchmark large trees/imports, and address identified bottlenecks.

### 4.1 Prior Work Already Landed on Main
The following major performance tasks have already been implemented and tested:
- **PERF-FIX-21 (#84)**: `ReviewService.getDueSummary` was converted from full-table scan (`getAllReviewStates()`) to targeted chunked queries (`getReviewStatesByIds` + `getKnowledgeStatesByCanonicalIds`).
- **PERF-FIX-32 (#67, #68)**: `ReviewSession` constructor cost was benchmarked on a 10k-decision dataset in `test/review/session_constructor_cost_test.dart`. Linear scaling (~4µs/decision, ~3.7ms for 2,000 decisions, well inside the 16ms frame budget) was verified.
- **POLISH-FIX-10 (#69)**: PGN parsing and hashing offload was unified to a single 8KB threshold (`shouldOffloadPgnWork` in `lib/src/import/pgn_offload.dart`).
- **Subtree Due-Count Memoization (#51)**: `ReviewSession._countDueDecisionsInSubtree` is memoized during auto-traversal, reducing traversal from $O(\text{depth} \times \text{subtree})$ to $O(\text{tree})$.
- **Move Latency Oracle (INV-050)**: `test/review/move_latency_test.dart` proves that move validation + incremental persistence completes in ~2.8ms median (budget: 16ms).

### 4.2 Targeted Audits for Round 10

#### A. Inactive Study Tree Deserialization in `startSession`
- **Location**: `lib/src/review/review_service.dart:214-224`
- **Observation**: For `ReviewScope.all()`, `startSession` loads all studies, filters to `activeStudies`, but then queries `repository.getChaptersByStudy` for all active studies while `allStudies` is passed into `_getActiveDecisions`. Check whether inactive study chapters or decisions are ever deserialized unnecessarily.

#### B. Asset Sizes & Memory Footprint
- **Audit Target**: `assets/` directory (~7.5 MB total):
  - `assets/chess_openings.db` (1.1 MB)
  - `assets/sounds/` (2.1 MB)
  - `assets/maia/` (1.3 MB)
  - `assets/pieces/` (1.1 MB)
  - `assets/images/` (1.0 MB)
  - `assets/fonts/` (824 KB)
- **Investigation**: Confirm whether `chess_openings.db` or large JSON files are held in memory permanently or queried on demand. Ensure image/piece assets are not decoded at excessive resolution.

#### C. Database Query Plans & Indices
- **Audit Target**: `lib/src/persistence/srs_schema.dart`
- **Investigation**: Check whether the SQLite indexes cover the hot query paths:
  - `srs_decision(studyId, chapterId, canonicalStateId)`
  - `srs_review_event(whenTimestamp)`
  - `srs_study(pgnHash)`
  - `position_knowledge_state(canonicalId)`

#### D. Startup Path Parallelization
- **Audit Target**: `lib/src/model/common/preloaded_data.dart` and `lib/src/app.dart`
- **Investigation**: Verify that `preloadedDataProvider`'s 7 platform futures (`PackageInfo`, `DeviceInfo`, `SecureStorage`, etc.) execute concurrently via `().wait`. Confirm that `startupTokenCheckProvider` and secondary services in `_AppState.initState` remain non-blocking.

---

## 5. Working Guidelines for the Next Turn

1. **Worktree Isolation**:
   ```bash
   git worktree add ../chesssrs-review-r10 -b fix/review-perf-round10 origin/main
   cd ../chesssrs-review-r10
   fvm flutter pub get
   fvm dart run build_runner build --delete-conflicting-outputs
   ```
2. **Local Budget Discipline**:
   - Run only targeted tests covering modified code.
   - Do not run `./verify` or wide test suites locally.
   - Run `fvm flutter analyze` on touched files.
3. **Commit Attribution**:
   Include the required trailer in PR creation:
   ```markdown
   ---
   Harness: OpenCode
   Model: <actual model>
   ```
4. **Documentation**: Append Round 10 findings and verification evidence to `docs/review-program.md` before opening the PR.
