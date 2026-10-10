# Whole-codebase review program

This is the plan for a multi-round, whole-codebase review, plus the record of each round as it
completes. It sits beside `review-index.md`, which covers the four scheduler-stack reviews that
came before. Those findings are not re-reported here. They are carried into the rounds below.

## How each round runs

1. **Review.** Read the code in the round's scope. Check every candidate against the call graph
   (is the path reachable in production?) before assigning severity. This is the lesson of
   `review-index.md` ("four findings were wrong about impact").
2. **Record.** Every finding gets an ID (`R<round>-F<n>`) and a disposition: *Fixed (PR)*,
   *Open (reason)*, *Dismissed (why it is not a defect)*, or *Checked, sound*.
3. **Fix.** One PR per round, from the session branch `arena/e97f199a-chesssrs`, containing only
   the fixes that round produced. Each defect fix carries a regression test that fails on the old
   code, as `GATES.md` requires for bugfix PRs.
4. **Verify.** No Dart toolchain was available while doing this review (see *Constraints*), so
   every fix is verified by reading and by the `Tests` and `Gates` workflows on the PR. A PR is
   not "verified" until those checks have run green.
5. **Advance.** The next round starts from `main` after the previous round's PR is merged, so
   each PR contains only its own round.

## Constraints

- **No Dart SDK in the review environment**, and `pub.dev` is not reachable. Nothing here has
  been compiled or run. CI (`test.yml`, `gates.yml`) is the only compiler.
- Gates forbid editing the referee (`SPEC.md`, `GATES.md`, `.gates/`, `pubspec.yaml`, ratchet
  baselines). Findings that need a referee change are recorded, not fixed.
- The `domain_loc` ratchet (`.gates/ratchet-baseline.json`, currently 3200 ± 150) is a protected
  path. Any round that adds to `lib/src/domain` must check the ratchet's headroom on the branch
  it is written against, and raise a baseline change with the owner rather than edit it.

## Inventory (at `be6941e`)

| Area | Files | Lines | Nature |
|---|---|---|---|
| `lib/src/view` | — | 23,840 | Mostly Lichess foundation; ChessSRS screens under `view/review`, `view/study` |
| `lib/src/model` | — | 22,518 | Mostly Lichess foundation; ChessSRS controllers and auth |
| `lib/src/widgets`, `design` | — | 8,820 / 3,671 | Shared UI and design system |
| `lib/src/domain` | — | 3,226 | **ChessSRS core** (scheduler, decisions, sessions) |
| `lib/src/network` | — | 2,736 | HTTP and socket clients (Lichess foundation) |
| `lib/src/review` | — | 2,206 | **ChessSRS** review engine and controller |
| `lib/src/utils` | — | 1,966 | Mixed |
| `lib/src/persistence`, `db` | — | 1,773 / 453 | **ChessSRS** SQLite storage and migrations |
| `lib/src/import` | — | 1,050 | **ChessSRS** PGN import and export |
| `lib/l10n`, `translation/` | 106 / 6,514 | — | Generated ARB and translation sources |
| `test/` | 194 | — | Suite, plus `.gates/`, `scripts/gates`, `redteam/` |

Lichess foundation code is reviewed only where ChessSRS has changed it or depends on it. Upstream
issues belong upstream.

## The rounds

| Round | Scope | Why this order |
|---|---|---|
| **1** | Trust boundaries and untrusted input: PGN import/export, deep links, shared PGN, OAuth, Android/iOS manifests, backup rules, TLS | Input from outside the app is where a small bug becomes a user-visible failure or a security issue |
| 2 | Persistence and data integrity: SQLite schema, migrations, transactions, the open review-4 C1/C2 items (latency erasure, offset-less timestamps) | Data loss is the most expensive defect class, and migrations are hard to undo |
| 3 | Scheduling domain: `lib/src/domain`, the review engine, the open review-1/2/3 items | Correctness of the product's core promise; needs hand-checked arithmetic |
| 4 | Network and sync: `network/http.dart`, `socket.dart`, retry, timeout, cancellation, token refresh, log redaction | Failure-mode handling and secret handling on every request |
| 5 | State and lifecycle: ChessSRS controllers and providers, `ref.onDispose`, async races, leaks | Races and stale state show up only under real use |
| 6 | UI and accessibility: `view/review`, `view/study`, shared widgets. Semantics, tap targets, contrast, text scaling, empty and error states | The owner is a beta tester on phones; this is what they will feel |
| 7 | Localisation: ARB key parity, placeholder mismatches, hard-coded user-facing strings, generated-file drift | Silent, widespread, and cheap to fix once found |
| 8 | Dependencies, build, and release: `pubspec` (git-pinned `lc0`), Gradle, fastlane, iOS plist, release workflow, licence notices | Supply-chain and licence obligations under GPL-3.0 (`AGENTS.md` §7) |
| 9 | Test suite and gates: weak or load-sensitive tests, coverage gaps in `domain/` and `persistence/`, gate blind spots | A test that cannot fail gives false confidence in every later round |
| 10 | Performance: large-PGN import, study load, review on large trees, asset sizes, startup | `docs/performance.md` exists; this checks it against the code |
| 11 | Docs and spec drift: `SPEC.md` vs code, `IMPLEMENTATION_PLAN.md` status, dead code, duplicated guides | Last, because it depends on what the earlier rounds decided |

The open items from the four earlier reviews are assigned to rounds 2 and 3, and are not
re-reported here.

---

## Round 1 — trust boundaries and untrusted input

**Scope read:** `lib/src/import/pgn_importer.dart`, `pgn_exporter.dart`,
`lib/src/app_links_service.dart`, `lib/src/shared_pgn_service.dart`,
`lib/src/model/auth/auth_repository.dart`, `android/app/src/main/AndroidManifest.xml`,
`android/app/src/main/res/xml/backup_rules.xml`, plus grep sweeps for TLS overrides, cleartext
URLs, and secret storage across `lib/`.

### Findings

| ID | Finding | Severity | Disposition |
|---|---|---|---|
| R1-F1 | PGN export wrote tag values unescaped. A study or chapter title containing `"` or `\` closed the tag early, and a line break split it. Titles are user-editable (rename dialog), so the exported file was malformed. | Low–medium | **Fixed in this PR.** `_tagValue` escapes per PGN §8.1.1 and folds line breaks. Regression tests added (INV-014). |
| R1-F2 | Desktop OAuth (Linux, Windows, macOS): the loopback server took the **first request on any path** as the callback. A browser prefetch of `/favicon.ico`, or any local process hitting the port, ended sign-in with "Authorization code missing". | Low | **Fixed in this PR.** `awaitOAuthCallback` answers non-`/callback` requests with 404 and keeps waiting. Regression test added. |
| R1-F3 | Desktop OAuth sends no `state` parameter (RFC 6749 §10.12, RFC 8252 §8.9 recommend it). | Low (hardening) | **Open.** PKCE already blocks code injection: a code issued for an attacker's challenge fails the exchange with this app's verifier. Adding `state` needs confirmation that Lichess echoes it on the redirect, or sign-in breaks for everyone. Needs that check before a change. |
| R1-F4 | `_writeNodeMoves` silently drops a subtree when a stored move fails to replay (`_playMove` returns null). The export is then missing moves with no warning. | Low | **Open.** Unreachable with well-formed data. Should log, and ideally surface, in a later round. |
| R1-F5 | `}` inside a comment would end a PGN brace comment early on export. | Low | **Open, not fixed.** Comments cannot be edited in the app, and imported comments cannot contain `}`, so no in-app path reaches it. Recorded so it is not rediscovered. |

### Checked and sound

- **Deep links** (`app_links_service.dart`): `open-web` links accept only `http`/`https`, and the
  refusal is deliberate and tested. Browser fallback is off for app links, which prevents a loop.
  First-party URL matching compares the parsed host and port exactly, not by prefix.
- **Shared PGN** (`shared_pgn_service.dart`): string payloads only, routed through the import
  screen. No file-system access.
- **PGN import** (`pgn_importer.dart`): parse and move errors are collected per chapter and the
  skipped subtree is counted. An input with no moves for the chosen side is reported as an error,
  not a success. A bad FEN skips only its chapter.
- **Hash prefix in the import log line** (`pgn_importer.dart:208`): `hash.substring(0, 8)` would
  throw on a short `pgnHash`. Every caller passes a computed 64-character SHA-256, so it is not
  reachable.
- **TLS and transport:** no `badCertificateCallback`, no `HttpOverrides`, and no `http://` base
  URL anywhere in `lib/`. The only `http://` is the loopback redirect, which is intended.
- **Android:** `autoVerify` is deliberately absent and the reason is documented in the manifest.
  Intent filters are limited to PGN MIME types and `.pgn` content URIs.
- **Backup:** `backup_rules.xml` excludes `FlutterSecureStorage`. The auth token is in secure
  storage (`auth_storage.dart`), so it is not included in Android backups.
- **OAuth mobile flow:** PKCE via `flutter_appauth`, with cancellation mapped to
  `SignInCancelledException`.
- **OAuth desktop flow:** the verifier is 32 random bytes from `Random.secure()`, and the
  challenge is S256. The server is bound to `127.0.0.1` only, with a 5-minute timeout and
  `server.close(force: true)` in `finally`.

### Not covered in Round 1 (carried)

- iOS `Info.plist` and the Share Extension's App Group handling. Round 8.
- `auth_repository.dart` beyond sign-in: email-code login and rate-limit handling. Round 4.
- The HTTP-log redaction work (H4). It is documented as implemented, and Round 4 checks it.

### Verification status of this round's PR

- Nothing compiled. Expect CI to be the first compiler. If `dart format` or `flutter analyze`
  reports anything, the PR must be fixed before merge.
- The exporter test relies on dartchess tolerating escaped tag values when it re-parses the output.
  The test asserts only the escaped header text and the mainline moves. If CI disagrees, the
  finding stands and the test assertion needs to change, not the escaping.

---

## Round 2 — persistence and data integrity

**Scope read:** `lib/src/db/database.dart` (open, `onConfigure`, `onOpen`, `onCreate`, every
`onUpgrade` branch through v16), `lib/src/persistence/srs_schema.dart`,
`canonical_rekey_migration.dart`, `sqlite_study_repository.dart` (deletes, saves, and the
transaction boundaries), and the matching tests in `test/persistence/`.

### Findings

| ID | Finding | Severity | Disposition |
|---|---|---|---|
| R2-F1 | `backfillCanonicalStatesFromLegacy` throws when two legacy occurrences tie on repetitions, last review, stability and lapses. The comparator's last tie-break reads `canonicalId` from the raw legacy row, which has none, so the null check fails. The throw is inside `onUpgrade` for any install below v16, so the upgrade rolls back and the database fails to open. | Medium (crash on upgrade). Likelihood low: a tie needs identical stats and timestamps. | **Fixed in the PR for this round.** The candidate row is built with its canonical id before it is compared, and the comparator is null-safe. A regression test fails on the old code. |
| R2-F2 | `ON DELETE CASCADE` is declared in the schema, but `PRAGMA foreign_keys` is never set, so the cascades never run. Deletes are hand-written and correct today. | Low (design risk) | **Open.** Issue text in `review-register.md`. |
| R2-F4 | The v11 migration writes `DEFAULT "white"`, a double-quoted identifier that works only through SQLite's legacy string fallback. | Low (hygiene) | **Open.** Issue text in `review-register.md`. |
| R2-F3 | `srs_review_event` has no retention policy and grows by one row per answer, with JSON state on each row. | Info | **Not filed.** Growth is small at repertoire scale. Revisit with Round 10 (performance). |

Round 1's R1-F3, R1-F4 and R1-F5 are also open. Their text is in `review-register.md`.

### Dismissed

- **`savePositionTree` and `saveDecisions` are not atomic with each other, so a crash could leave a tree and its decisions out of step.** No production code calls either method. A search of `lib/` finds callers only in tests, so the concern is dead code, not a live defect. It goes to Round 11 (dead code).
- **`deleteStudy` removes review state that other studies share.** It does not. The shared-canonical guard keeps any state whose canonical id another study's decision still references, and it is tested.

### Checked and sound

- **Migration chain.** Each version step from v1 to v16 is present, and the schema is created in `onCreate` with the same shape as the upgrade path. The data migrations run after `batch.commit()`, so they see the upgraded tables.
- **Transactions.** `saveImportResult` (study, chapters and decisions) and `saveAnswerBatch` (knowledge states and event) are each one transaction. `deleteStudy` and `deleteChapter` delete inside a transaction.
- **Rekey idempotency.** A decision already on the new key recomputes to its own id and is skipped, so a second run is a no-op. The test for this exists.
- **Rekey collisions.** Two old ids that land on one new id merge deterministically, and the test "merges two old keys that resolve to one" covers it.
- **Backfill never overwrites a newer canonical row.** Covered by the existing test "an existing canonical state is never overwritten by a legacy one".
- **Study timestamps.** `createdAt` is preserved when set. Only the `null` case falls back to now.
- **Backup exclusion of secure storage.** Covered in Round 1.

### Verification status of this round's PR

- **Stacked.** The branch is `arena/e97f199a-chesssrs`, and the PR's base is `main`. Until PR #32 merges, the PR diff also shows PR #32's Round 1 commits. Its own change is the single commit labelled as Round 2.
- **Not compiled or run here.** Same constraint as Round 1. CI is the first compiler.
- **Tie test.** The new test in `canonical_rekey_migration_test.dart` is written to fail on the old code and pass on the fix. The reason it fails is the thrown null check, not an assertion. Reviewers should check the failure message on the base to confirm that.

### Process notes

- **GitHub Issues are disabled on this repository.** `gh issue create` returns "the repository has disabled issues". The findings are written as issue-ready text in `docs/review-register.md` instead. Enabling Issues is a repository setting, which is yours to change.
- **Local clone reset during the session.** The local branch was found reset to `be6941e` between turns, with the remote branch intact at `eb5a39a`. I restored the branch from `origin` and confirmed the Round 1 files match the committed versions before committing anything new.

---

## Round 3 — scheduling domain

**Scope read:** `lib/src/domain/chess_fsrs_scheduler.dart`, `scheduler.dart`, `review_state.dart`,
`graph_aware_review_coordinator.dart`, `lib/src/domain/review/` (`review_session.dart` at 1016
lines, `review_engine.dart`, value types), the importer decision derivation
(`pgn_importer.dart:626-669`) for the one open question review-3 left ("can a user node have more
than one continuation?"), plus the open review-1/2/3 items from `docs/review-index.md`.

**Environment difference from rounds 1–2:** a Dart toolchain was available, so every fix below
was run locally (new tests fail on base, pass on the fix) rather than verified by CI alone.

### Findings

| ID | Finding | Severity | Disposition |
|---|---|---|---|
| R3-F1 | `completedCount` (hand-incremented int) and the quota set counted different things: a lapse corrected on re-test counted twice, a retry-driven session reported zero (review-3 C1). | Medium | **Fixed in this PR.** `completedCount` derives from `_completedDecisionIds.length`; the field and its checkpoint slot are gone. Regression test + INV-031. |
| R3-F2 | The quota cut cleared both queues including re-queued lapses, voiding the re-test promise (review-3 C2). | Medium | **Fixed in this PR.** New `_pendingRetest` set (checkpointed): the cut drops new work only and keeps going while a re-test is owed; re-tests cost nothing since the set already holds them. Regression test + INV-021, INV-031. |
| R3-F3 | Auto-traversal followed `children.first` at user junctions although variations are first-class siblings, so alternative lines were never traversed nor credited (review-3 C3). The invariant question is settled: the importer derives decisions from nodes with children and recurses into all of them, so multi-continuation user nodes are real. | Medium | **Fixed in this PR.** Due-density selection among user continuations (ties keep list order, so no-due behaviour is unchanged) plus exposure credit for the first decision below each passed-over alternative. Two regression tests + INV-022, INV-010. |
| R3-F4 | `prompt.expectedMoves.first` threw `StateError` on an empty list (review-3 C4). Unreachable from the importer (decisions need children) but representable in the DB. | Low | **Fixed in this PR.** Grades incorrect through the scheduler directly, no throw. Regression test + INV-020. |
| R3-F5 | `retryMove`'s fresh-state fallback used the occurrence id where `submitMove` used the canonical id (review-3 C5). | Low | **Fixed in this PR.** Both use `canonicalId`. Regression test + INV-016. |
| R3-F6 | Contagion entered at depth 1 with `exp(-depth/τ)`, delivering 51.3% of the documented λ0 at every depth (review-2 C2). Two of three sources (prose, `:104` comment) say the immediate child takes 18%. | Medium | **Fixed in this PR.** Exponent is now `-(depth-1)/τ`; §B.1 formula aligned (that doc is not a protected path). Existing decay expectations updated with an `Ack-G08:` trailer, plus a pinning test. INV-027. |
| R3-F7 | `recordAutoTraversalExposure` returned a fresh `ReviewState.initial` for unknown nodes, which the session persisted as rows for unengaged positions (review-2 C3). | Low | **Fixed in this PR.** Returns null; the call site already null-checks. Regression test + INV-028. |
| R3-F8 | `GraphNode.parentId` required but never read (review-2 D3). | Hygiene | **Fixed in this PR.** Dropped (4 lib sites, 13 test sites; compiler-verified). |
| R3-F9 | `InMemoryReviewStateRepository` shipped in `lib/` although production never uses it (review-2 D4). | Hygiene | **Fixed in this PR.** Moved to `test/domain/in_memory_review_state_repository.dart`. |
| R3-F10 | `movePlayed` constructed three times with two shadows (review-3 D2). | Hygiene | **Fixed in this PR.** Built once per entry point. |

### Deliberately not fixed

- **Review-1 C4 (scheduler switch reinterprets stability):** still deferred — every remedy mutates stored memory; needs the product decision recorded in review-1 §6.
- **Review-1 C6 (`isColdStart` never re-arms):** stays open. A failed first attempt yielding weaker memory than a clean one is arguably intended grading; re-arming needs a product definition of "forgotten".
- **Review-1 D4 / review-4 C2 (offset-less timestamps):** stays open. A migration with data risk; it was Round 2's assigned scope and Round 2 did not take it (see gap note below).
- **Review-1 D5 (`repetitionCount` semantics differ per scheduler):** stays open. Live consumers exist (`review_service.dart:493`, `review_controller.dart:1034`); unifying means changing two schedulers' lapse behaviour — bigger than this round.
- **Review-1 D7, review-3 D4:** no action (self-consistent / trivial forwarder).
- **Review-2 D1 (throttle/rollback conflation), review-3 D1 (extract grading block):** working code; the refactors' risk outweighed their value inside the `domain_loc` headroom (3308 of 3350 at PR time).
- **Review-4 C1/C3/D1–D4:** out of scope (Round 2's assignment). They are now the only confirmed scheduler-stack findings with neither a fix nor a register entry — see gap note.

### Gap note (for Round 4+ planning, not this PR)

Round 2's scope line claimed "the open review-4 C1/C2 items (latency erasure, offset-less
timestamps)" but its findings table never dispositioned them, and the register has no entries for
review-4 C1–C3. The highest-ranked open item in `review-index.md` (review-4 C2, timezone-shifting
due dates) is therefore tracked nowhere but the review-4 doc. This round adds the three missing
register entries without claiming the fixes.

### Checked and sound (do not re-raise)

- **Review-1 C1/C2/C3 fixes on main:** the same-day difficulty freeze, the false-start single-Again, and the clamped preview are all present with their tests.
- **Review-2 C1 fix on main:** the persisted exposure throttle and its restart test are present.
- **Traversal prompting off-queue due spine items** (`_continueWithCorrectMove` prompting a due decision not in the queue) is existing intended behaviour, not a quota bypass: the quota truncation keeps the most urgent N, and the walk surfaces what is due along the line.
- **`_selectWeighted` empty-candidate path** cannot fire: every caller guards non-emptiness first.
- **`childMoves` `!` on `incomingMove`:** the importer always sets it; decisions are never derived at childless nodes.

### Verification status of this round's PR

- New tests fail on base (wrong-reason-free): coordinator proof worktree 10 pass / 3 fail on `origin/main`; engine proof 30 pass / 6 fail. Failure reasons recorded in the PR (double-count 4-vs-3, `Bad state: No element` at `:416`, occurrence-vs-canonical id, 0.9076-vs-0.82 decay, first-listed-continuation walked). The checkpoint test references the new checkpoint field, so it cannot compile on base by construction.
- Full files green on the fix: coordinator 13/13, engine 37/37; the rollback, contagion-persistence, and retry-side-effects service tests pass by name.
- `fvm flutter analyze` clean on all touched files; `dart format` stable; `domain_loc` 3308 against the 3350 ceiling (no re-baseline needed).

---

## Round 4 — network and sync

**Scope read:** `lib/src/network/http.dart` (1075 lines, all), `socket.dart` (1152, all),
`aggregator.dart`, `connectivity.dart`, `server_status.dart`, `lib/src/model/auth/` (all six
files), the FCM-registration remnants, the H4 redaction implementation against
`docs/h4-credential-redaction.md`, and every request URL built app-wide for secret-bearing
query strings. Unlike rounds 1–2, a Dart toolchain was available, so fixes were run locally.

### Findings

| ID | Finding | Severity | Disposition |
|---|---|---|---|
| R4-F1 | Four log sites and eleven exception constructors interpolated the raw URL: `_checkResponseSuccess`, `readNdJsonStream`, and two `downloadFile` lines logged `$url`, and every `ClientException`/`ServerException` thrown by the `ClientExtension` helpers stored the raw `url` — whose `toString()` renders it into the UI, the logs and crash reports. No current caller passes secrets there (the auth endpoints deliberately throw with the clean URL), but the vector was open for any future one. | Low–medium | **Fixed in this PR.** All wrapped with `redactUriForLogging`; nothing reads `.url`/`.uri` programmatically (only `statusCode`/`message`), so nothing is lost. Guard test extended with the three `$url` patterns; message + `toString` regression tests. |
| R4-F2 | Desktop OAuth sent no `state` (open since Round 1 as R1-F3, blocked on Lichess confirmation). | Low (hardening) | **Fixed in this PR.** The blocker is resolved from lila source (`AuthorizationRequest` parses `Option[State]`; `RedirectUri.code/error` echo it) plus a live probe (`/oauth?...&state=PROBE123XYZ` survives the login redirect in the referrer). `buildDesktopOAuthUri` takes an optional state, `_desktopSignIn` generates one per attempt, `awaitOAuthCallback` 404s non-matching callbacks while waiting. R1-F3 register entry removed (fixed items are tracked by PR). |
| R4-F3 | `_versionGapRetryTimer` was not cancelled in `_disconnect`, so a gap retry scheduled before a disconnect reprocessed its stale event on the replacement connection — and after a `close()` with no replacement, its retries ran out and scheduled a reconnect, resurrecting a deliberately closed client. | Low | **Fixed in this PR.** One-line cancel in `_disconnect`, covering connect/close/dispose/channel-gone. Regression test proves the old code opens a second channel. |
| R4-F4 | The `kSensitiveQueryParameters` doc claimed `http_redaction_test.dart` fails if any app-wide query parameter goes unclassified — a test that does not exist (the classification-guard attempt was dropped for false positives). | Hygiene | **Fixed in this PR.** Comment now says review discipline, not automation, guards the list, and names the per-review sweep. |

### Checked and sound (do not re-raise)

- **H4 redaction as implemented (#10):** the helper, the denylist (case-insensitive), the FCM path prefix, and all six request/error log sites route through it; the `http_log` row stores the redacted URL. The guard test's two patterns held before this round and still hold with three more.
- **Auth endpoints throw with the clean URL:** `requestEmailLoginCode`/`signInWithEmailCode` build their `ServerException`s from the body-first URL, never the query-fallback one — so even the failure path after a fallback carries no code, email or username.
- **FCM is fully cut:** no `FirebaseMessaging` reference remains in `lib/`; the `/mobile/register/firebase` redaction prefix is now a dormant guard, kept deliberately.
- **Secret-bearing URLs app-wide:** only the two mobile-code fallbacks (denylisted params, redacted at every log site). `/report?username=` carries public profile ids, over-redacted harmlessly by the same denylist.
- **Socket auth and routes:** bearer fully in headers (never logged), routes are bare paths with sri/version added inside `connect()`; the pool's default client is never disposed because its constructor passes no `onStreamCancel`, so no idle timer is ever armed for it (noted at the declaration now). `onAuthChanged` drops both queues before reconnecting as the new account.
- **Reconnect/backoff/epoch/timer bookkeeping** in `SocketClient` and the revision fencing in `connectivity.dart` read correctly; `isOnline` probes are HEAD-only (hence absent from `http_log` by construction) and the quiet header's strip is pinned by test.
- **`checkToken` dedup, generation fence, startup swallow** (F-AUTHTOKEN) all present; `kLichessWSSecret` comes from `--dart-define`, defaulting to a no-op placeholder — not bundled.
- **`reportSignInFailure` stays local:** `Logger('Auth')` at WARNING never reaches the Crashlytics SEVERE gate, and the errors it can carry hold clean URLs (see above).

### Left open deliberately

- **R1-F4, R1-F5, R2-F2, R2-F4, review-4 C1–C3:** other rounds' scope; untouched.
- **Response bodies in exception messages** (`_checkResponseSuccess` appends the body): server-controlled content, no secret-bearing echo endpoint in use. Accepted, flagged for the day one appears.
- **`send()` after `dispose()` queues into `_resendWhenOpen`:** upstream pattern; the client is discarded with its queue, so growth is bounded by a caller that no longer exists. Not touched.
- **HEAD requests absent from `http_log`:** the only HEAD sender is the connectivity probe, so the gap is exactly "probes leave no rows" — accepted as diagnostic quietness, not fixed.

### Verification status of this round's PR

- New tests fail on base: redaction file 10 pass / 4 fail on stashed `http.dart` (guard + all three message tests); socket resurrection test fails on stashed `socket.dart` with 2 channels opened where 1 is expected. The state tests reference the new `state:`/`expectedState:` parameters, which do not exist on base — verified by grep that old `auth_repository.dart` contains no state plumbing, so they cannot pass there by construction.
- On the fix: redaction 14/14, auth 23/23, socket 47/47, `http_test.dart` 25/25 (download + quiet groups).
- `fvm flutter analyze` clean on all touched files; `dart format` stable; `./scripts/gates.sh t1` run pre-push (see PR checks for the committed-range result).
