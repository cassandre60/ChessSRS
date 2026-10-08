# Read-only repository audit report
## Scope and snapshot
- Audited snapshot: a1c8452c9
- Current worktree: 2db730ef97faa62601a75b154bd6eb86fdf34724
- Worktree status: clean
- Current branch: main, tracking origin/main
- No fixes, formatting, commits, resets, or generated-file changes were made.
The repository advanced externally during the audit through later cleanup commits. All cited implementation files remain unchanged at the current HEAD; the only changed file in the selected audit paths was the unrelated `lib/src/model/settings/brightness.dart`.
Excluded generated files, build output, dependencies, lockfiles, and vendored artifacts.
Severity meanings:
- High: security, authentication, persistent data loss, or core correctness failure.
- Medium: user-visible incorrect behavior, recoverable state corruption, or substantial reliability issue.
- Low: edge-case, UX, performance, or tooling issue with limited blast radius.
## Verification status
- fvm flutter analyze against the current checkout: passed, no issues.
- Focused audit test batch: 226 tests passed against the audited snapshot.
- Separate focused UI/settings run: 5 failures:
- 2 stale settings-label expectations.
- 3 move-times semantics/accessibility/contract failures.
- GitHub Actions:
- Last completed run 35930320258: success.
- Current run 35997336693 was still in progress at the final check, so the current HEAD is not claimed to have passed CI.
# High severity
## H1 — OAuth callback uses a different custom URI scheme from the native apps
**Confidence: High**
**Evidence**
- lib/src/constants.dart:31
- kLichessCustomUriSchemeName = 'org.lichess.mobile'
- lib/src/model/auth/auth_repository.dart:12-21
- OAuth redirect is built as org.lichess.mobile://login-callback.
- android/app/src/main/AndroidManifest.xml:145-158
- Android callback receiver accepts only org.chesssrs.app://login-callback.
- ios/Runner/Info.plist:105-114
- iOS registers only org.chesssrs.app.
**Trigger**
Completing the browser-based OAuth flow.
**Impact**
The browser returns to a URI scheme that the installed ChessSRS app does not register. The OAuth flow can remain stuck or fail to return to the app. The account menu itself is reachable through More → account; this is a broken authentication completion path, not an unreachable menu.
**Fix direction**
Choose one application-owned scheme and derive the Dart constant, Android intent filter, and iOS URL scheme from the same identity. Add an end-to-end OAuth callback test for both platforms.
## H2 — Authentication transitions are not generation- or identity-fenced
**Confidence: High**
**Evidence**
- lib/src/network/http.dart:432-468
- A request captures the current authUser.
- On HTTP 401, checkToken() is invoked without awaiting it.
- lib/src/model/auth/auth_controller.dart:87-100
- checkToken() checks one user, awaits the network, then deletes storage and clears the current state without verifying that the same account is still active.
- lib/src/model/auth/auth_controller.dart:76-85
- signOut() waits 500 ms, then revokes a token and clears state.
- lib/src/model/auth/auth_repository.dart:177-179
- Sign-out uses the current client and can therefore use a different account's token if another sign-in completes during the delay.
**Trigger**
- A request from account A receives a 401 while the user signs out or signs into account B.
- Sign-out and sign-in overlap.
- Multiple 401 responses trigger concurrent token checks.
**Impact**
- Account B can be logged out by a stale validation for account A.
- A delayed sign-out can revoke account B's newly stored token.
- Storage and in-memory auth state can diverge.
- A stale request can clear a valid newer session.
**Fix direction**
Serialize auth operations, attach an auth generation/session ID to every transition, and only commit validation or sign-out results if the captured token and account still match the active session.
## H3 — Bearer credentials are attached to absolute non-main-host requests
**Confidence: High**
**Evidence**
- lib/src/network/http.dart:407-445
- LichessClient.send() adds the stored bearer token to every request that does not already contain an Authorization header.
- lib/src/network/http.dart:552-555
- Absolute URLs retain their supplied host.
- lib/src/model/explorer/opening_explorer_repository.dart:225-277
- Master, Lichess, and player explorer requests use the authenticated client with absolute explorer URLs.
- lib/src/model/explorer/tablebase_repository.dart:22-36
- Tablebase requests also use the authenticated client with an absolute tablebase URL.
**Trigger**
A logged-in user queries Opening Explorer or tablebase services.
**Impact**
The user's Lichess bearer token is disclosed to separate service hosts, including hosts that can be changed with compile-time environment configuration. A misconfigured or compromised external host receives a reusable credential.
**Fix direction**
Restrict bearer attachment to the main Lichess API host. Use an explicitly unauthenticated client for explorer, tablebase, CDN, and other external services. Add a host-policy test for absolute URLs.
## H4 — OTP, email, and FCM credentials are written to logs
**Confidence: High**
**Evidence**
- lib/src/network/http.dart:103-143
- The HTTP logging wrapper stores the complete request URL.
- lib/src/model/auth/auth_repository.dart:103-140
- Email login URLs contain username, email address, and one-time code in query parameters.
- lib/src/model/notifications/notification_service.dart:460-472
- The FCM registration token is logged and placed in the request path.
- lib/src/db/database.dart:263-295
- HTTP and application logs are persisted in SQLite.
**Trigger**
Requesting an email login code, exchanging the code, or registering for push notifications.
**Impact**
Short-lived OTPs, email identifiers, and long-lived device notification tokens remain in local diagnostic storage and may be exported through diagnostics. This is a credential and privacy exposure.
**Fix direction**
Redact query parameters and sensitive path segments before logging. Suppress auth and token-registration request bodies/URLs entirely, and add regression tests that assert secrets never reach `http_log` or `app_log`.
## H5 — Review answers mutate the in-memory session before persistence succeeds
**Confidence: High**
**Evidence**
- lib/src/review/review_service.dart:165-211
- session.submitMove() mutates queue position, canonical review state, graph side effects, and session state.
- Only afterward does the service call saveAnswerBatch().
- lib/src/review/review_controller.dart:836-865
- The controller awaits submitMove() but has no rollback or session reload on persistence failure.
- lib/src/persistence/sqlite_study_repository.dart:495-564
- The actual database transaction is atomic, but it is called only after the in-memory mutation.
**Trigger**
SQLite write failure, disk-full condition, database closure, or transaction exception after a move is submitted.
**Impact**
The in-memory session advances while durable state remains unchanged. A restart loses the answer, graph side effects, and queue progress; a retry may operate on an already-mutated prompt and produce duplicate or inconsistent scheduling.
**Fix direction**
Use a session snapshot/transaction boundary: either persist before exposing the transition, or roll back/reload the session on failure. Add fault-injection tests around `saveAnswerBatch()`.
## H6 — Offline game work is not fenced to the game that started it
**Confidence: High**
**Evidence**
- lib/src/model/offline_computer/offline_computer_game_controller.dart:245-291
- startNewGame() and loadGame() replace state without invalidating in-flight engine, practice, animation, or analysis work.
- lib/src/model/offline_computer/offline_computer_game_controller.dart:372-500
- Practice evaluation waits across multiple asynchronous boundaries and mostly checks only ref.mounted.
- lib/src/model/offline_computer/offline_computer_game_controller.dart:694-736
- _playEngineMove() awaits the opponent and then applies the result to whatever state is current.
- lib/src/model/offline_computer/offline_computer_game_storage.dart:70-79
- Saves write directly to the final file and swallow failures.
- lib/src/view/offline_computer/offline_computer_game_screen.dart:155-168
- Lifecycle events can initiate overlapping saves.
**Trigger**
Start or load another offline game while an engine move, practice evaluation, opening lookup, or save is still running.
**Impact**
- An old engine move can be applied to a new game.
- A delayed practice result can be written to the wrong move/step.
- Overlapping lifecycle saves can overwrite newer state with older state.
- A storage failure is logged but not surfaced to the caller.
**Fix direction**
Give each offline game a monotonically increasing generation, cancel old searches/subscriptions, and verify the generation and game ID after every await. Save through a temporary file followed by atomic rename, and serialize saves.
## H7 — Canonical review identity is lossy and can merge different repertoire positions
**Confidence: High**
**Evidence**
- lib/src/import/pgn_importer.dart:531-567
- A decision's canonical state is derived from the first child move:
canonicalKey(node.fenKey, primaryMove.uci).
- The decision may contain multiple accepted moves.
- lib/src/domain/review/review_session.dart:59-69
- Decisions are indexed by canonical ID and accepted-move keys.
- lib/src/domain/review/review_session.dart:78-99
- All-scope queues deduplicate decisions by canonical ID.
- lib/src/domain/review/review_session.dart:712-733
- Sibling graph nodes are selected by FEN key and canonical IDs.
- lib/src/import/pgn_importer.dart:60-95
- Tree fingerprints depend on child iteration order.
**Trigger**
Two repertoire positions have the same FEN and primary move but different accepted continuation sets, or the same continuation is represented in a different child order.
**Impact**
- SRS state can be applied to a different repertoire decision.
- Graph contagion and sibling updates can affect the wrong branch.
- One occurrence can suppress another in the all-scope review queue.
- Reimports can be treated as duplicates or diverge depending on child order.
**Fix direction**
Define canonical identity from the complete position/answer/branch contract, not the first child. Keep occurrence identity separate from shared position knowledge, enforce uniqueness, and add collision tests for multi-move and reordered trees.
## H8 — Study collaboration writes are sent but incoming edits are not applied
**Confidence: High**
**Evidence**
- lib/src/model/study/study_controller.dart:480-504
- The client emits anaMove, anaDrop, promote, and deleteNode events.
- lib/src/model/study/study_controller.dart:291-308
- The study-specific socket handler only processes liking after delegating to the chat mixin.
- lib/src/model/chat/chat_mixin.dart:200-231
- The parent handler only handles chat messages.
**Trigger**
Another contributor edits the same study while this controller is open.
**Impact**
The local tree remains stale. Subsequent edits can be based on an obsolete path, overwrite remote changes, or make collaboration appear one-way.
**Fix direction**
Implement incoming collaboration event reconciliation, including event/version ordering, idempotency, and chapter identity checks. Add two-controller tests for concurrent moves, promotion, and deletion.
## H9 — Socket messages queued before an account change can be sent under the new account
**Confidence: High**
**Evidence**
- lib/src/network/socket.dart:188-198
- _resendWhenOpen and _acks store encoded messages without an auth identity.
- lib/src/network/socket.dart:254-278
- Reconnect reads the current session and uses it for the new connection.
- lib/src/network/socket.dart:338-357
- All queued messages are flushed after reconnect.
- lib/src/network/socket.dart:398-436
- Messages sent while disconnected are queued for later delivery.
- lib/src/network/socket.dart:869-878
- Auth changes reconnect the socket but do not clear or segregate queues.
- lib/src/network/socket.dart:995-1003
- The global pool listens for auth events and reconnects.
**Trigger**
A study move, chat message, or other message is queued while offline or disconnected, then the user signs out and signs into another account before reconnection.
**Impact**
Messages created by account A can be sent with account B's bearer token. This can cause cross-account mutations, incorrect chat delivery, or unauthorized study writes.
**Fix direction**
Tag queued messages and acknowledgements with the auth identity that created them. Drop or quarantine messages on identity mismatch, and clear acknowledgement state on logout.
# Medium severity
## M1 — Server-analysis request and socket lifecycle has stale-request and null-client races
**Confidence: High**
**Evidence**
- lib/src/model/analysis/server_analysis_service.dart:70-158
- Each request creates a socket and completer, but there is no request generation.
- A game request sets _currentAnalysis after an awaited HTTP request at lines 118-140.
- A study request chains firstConnection.timeout(...).onError(...).whenComplete(...) at lines 144-152.
- _cancelAnalysis() nulls _socketClient.
- The timeout future at lines 155-157 is not awaited or error-handled.
**Trigger**
- Request A followed quickly by request B.
- Study socket connection timeout.
- Cancellation while the connection future is completing.
**Impact**
- A completed old request can overwrite _currentAnalysis for a newer request.
- The study whenComplete callback can dereference a null socket after timeout/cancellation.
- Timeout errors can become unhandled asynchronous errors.
- Analysis listeners can be attached to the wrong source or lost.
**Fix direction**
Use a request generation and capture the socket/completer locally. Check identity before and after every await, handle timeout errors explicitly, and make cancellation invalidate all callbacks.
## M2 — Socket version gaps are retried without a recovery path
**Confidence: High**
**Evidence**
- lib/src/network/socket.dart:504-531
- If an incoming event version is greater than version + 1, the same event is retried up to ten times.
- The code never changes the version, requests missing events, or reconnects from a known version.
**Trigger**
One or more WebSocket events are missed while the connection remains apparently alive.
**Impact**
The same future event is repeatedly discarded, leaving the local stream permanently incomplete. The application eventually reports a gap failure instead of recovering.
**Fix direction**
Implement the protocol's resynchronization/reconnect strategy from the last committed version. Treat the retry timer as a bounded recovery attempt, not as a replay of the same future event.
## M3 — Engine release and search callbacks can outlive the user request
**Confidence: High**
**Evidence**
- lib/src/model/engine/position_evaluator.dart:253-274
- release() pauses and schedules _releaseEngine() but does not increment _generation.
- lib/src/model/engine/position_evaluator.dart:321-343
- _acquireEngine() checks only the captured generation after asynchronous spec resolution.
- lib/src/model/engine/position_evaluator.dart:478-487
- Search info subscriptions and bestMove.then(...) callbacks are not stored or cancelled.
- lib/src/model/engine/position_evaluator.dart:508-570
- Callbacks check the engine/search identity only partially and can still emit old work.
**Trigger**
- Turn the engine off while NNUE/spec resolution is pending.
- Rapidly replace one evaluation with another.
- Stop or release while a search is still reporting.
**Impact**
- A late spec resolution can resurrect an engine after release.
- An old search can overwrite the current evaluation or emit a result for the wrong work.
- Search subscriptions can remain alive until the engine eventually completes.
- A failed bestMove future has no attached error handler.
**Fix direction**
Invalidate the evaluator generation on release, tag every search with its generation/work, cancel subscriptions, handle search errors, and reject callbacks from non-current searches.
## M4 — Cloud evaluation requests are uncorrelated and can hang or apply stale results
**Confidence: High**
**Evidence**
- lib/src/model/engine/evaluation_mixin.dart:298-335
- _fetchCloudEvalHttp() has no timeout, cancellation, or request-generation check.
- lib/src/model/engine/evaluation_mixin.dart:356-380
- The HTTP request is launched independently from socket evaluation.
- lib/src/model/offline_computer/offline_computer_game_controller.dart:522-568
- _getCloudEval() sends evalGet before subscribing to socketClient.stream.
- Correlation uses only the UCI path; there is no request ID or variant/multi-PV fence.
**Trigger**
- Slow cloud endpoint.
- Rapid node navigation.
- Two requests for the same path.
- A fast socket response arriving between send() and stream subscription.
**Impact**
- Requests can wait indefinitely.
- A response for an old path or request can be accepted.
- Offline hints can receive no response even when the server already answered.
- Stale evaluations can be shown until a deeper local result happens to replace them.
**Fix direction**
Subscribe before sending, add a request ID and generation, cancel on navigation/disposal, enforce a timeout, and validate all request dimensions before applying a response.
## M5 — Loaded offline games do not resume their clock and terminal starting positions are not normalized
**Confidence: High**
**Evidence**
- lib/src/model/offline_computer/offline_computer_game_controller.dart:276-291
- loadGame() restores saved time values but never resumes the clock.
- lib/src/model/common/local_game_clock.dart:66-75
- setupClock() creates state with activeClock: null.
- lib/src/model/common/local_game_clock.dart:117-123
- Resuming is a separate operation.
- lib/src/model/offline_computer/offline_computer_game_controller.dart:993-1024
- Custom FENs are accepted while the new game is always initialized with GameStatus.started.
- lib/src/model/offline_computer/offline_computer_game_controller.dart:287-290
- Load logic assumes the saved status and position are playable.
**Trigger**
- Load a timed offline game and resume play.
- Start from a FEN that is already checkmate, stalemate, variant-end, or insufficient material.
**Impact**
- The player can think without the clock running.
- A terminal position may remain marked playable and reach the engine/UI as an invalid game.
- The result can be inconsistent with the loaded board.
**Fix direction**
Resume the clock only after validating the saved state, derive terminal status from the loaded position, and reject or normalize terminal starting FENs during creation and load.
## M6 — Offline repetition and material accounting use insufficient position identity
**Confidence: High**
**Evidence**
- lib/src/model/offline_computer/offline_computer_game_controller.dart:332-336
- Threefold repetition compares only position.board.
- lib/src/model/game/material_diff.dart:38-66
- Captured material is calculated relative to Position.initialPosition(position.rule), not the game's actual starting material.
**Trigger**
- Positions have the same piece placement but different side-to-move, castling rights, or en-passant state.
- A custom starting FEN omits or adds material.
**Impact**
- False threefold repetition claims.
- Incorrect clearing of a repetition claim after a move.
- Negative or incorrect captured-piece counts for custom positions.
**Fix direction**
Use the repository's normalized position identity/FEN contract for repetition. Capture material relative to the actual game root and preserve variant-specific rules.
## M7 — Study chapter selection and gamebook timers can operate on the wrong chapter
**Confidence: High**
**Evidence**
- lib/src/model/study/study_controller.dart:146-166
- goToChapter() awaits a repository request without a selection generation.
- lib/src/model/study/study_controller.dart:311-323
- The opponent-first-move timer captures no chapter/path identity.
- lib/src/model/study/study_controller.dart:337-348
- The gamebook navigation timer is not stored or cancelled.
- lib/src/model/study/study_controller.dart:773-779
- Chapter navigation and title getters assume valid nonempty/current chapter lists.
- lib/src/model/study/study_controller.dart:182-183,713-723
- Permissions are captured into state from the account observed at load time.
**Trigger**
- Select chapter A, then chapter B before A's request completes.
- Change account while a study is open.
- Invoke next-chapter navigation at the end of the chapter list.
**Impact**
- The older request can replace the newer chapter.
- A timer can advance or play a move in a newly selected chapter.
- A stale permission snapshot can allow or reject writes using the previous account's identity.
- Empty/malformed chapter data can cause an out-of-range access.
**Fix direction**
Use a chapter request generation, cancel timers on chapter changes, capture chapter/path identity in callbacks, watch auth changes, and guard all chapter index accesses.
## M8 — Review scope reloads and session refreshes can commit out of order
**Confidence: High**
**Evidence**
- lib/src/review/review_controller.dart:381-405
- changeScope(), reload(), and practice-mode transitions await _loadState() without an operation generation.
- lib/src/review/review_service.dart:73-87,145-158
- ReviewService has one mutable _activeSession that is replaced by whichever load finishes last.
- lib/src/review/review_controller.dart:628-669
- Advancement waits for animations, then uses _service.activeSession! rather than verifying that it still corresponds to currentState.
**Trigger**
- Change scope twice quickly.
- Toggle study activity or delete a study while a review transition is animating.
- Reload while an answer is being processed.
**Impact**
The displayed prompt can belong to one scope while the service advances another. State, active session, and persistence can become mismatched.
**Fix direction**
Serialize transitions or attach a generation/session ID to every load and advancement. Capture the session in the transition and verify it is still current after every delay.
## M9 — Retry handling loses quota credit and can bypass session limits
**Confidence: High**
**Evidence**
- lib/src/domain/review/review_session.dart:215-217
- Initial correct answers add the canonical decision to _completedDecisionIds.
- lib/src/domain/review/review_session.dart:339-363
- A correct retry calls _continueWithCorrectMove() but does not add the decision to _completedDecisionIds.
- lib/src/review/review_controller.dart:753-755
- Daily count increments only for isFirstAttempt.
- lib/src/review/review_controller.dart:448-450
- Activity-toggle session refresh does not pass remainingDailyQuota.
- lib/src/review/review_controller.dart:502-509
- Delete-study refresh also starts a session without the remaining quota.
- lib/src/persistence/sqlite_study_repository.dart:825-837
- Daily quota is calculated with a UTC-midnight string boundary while event timestamps are generated from local DateTime values.
**Trigger**
- Answer incorrectly, then answer correctly on retry.
- Toggle a study or delete one after reaching a quota boundary.
- Review near local midnight in a non-UTC timezone.
**Impact**
- A successfully retried position may not count toward the in-memory daily quota.
- Refreshes can create sessions beyond the configured daily limit.
- UI counts, session queue length, and persisted quota can disagree.
- Timezone boundaries can undercount or misclassify reviews.
**Fix direction**
Count each canonical position once on successful completion, separate attempt history from quota identity, pass quota through every session refresh, and perform date-boundary calculations in one explicit timezone/UTC representation.
## M10 — Retry side effects and deletion leave SRS ownership incomplete
**Confidence: High**
**Evidence**
- lib/src/review/review_service.dart:216-223
- retryMove() returns session side effects but does not persist them.
- lib/src/domain/review/review_session.dart:455-468
- Auto-traversal can update exposure state for later decisions during a retry.
- lib/src/persistence/sqlite_study_repository.dart:173-248
- Study deletion removes review events by decision ID and conditionally removes canonical state.
- lib/src/persistence/sqlite_study_repository.dart:320-346
- Chapter deletion removes decision-ID state/events but does not perform equivalent canonical-state cleanup.
- lib/src/persistence/sqlite_study_repository.dart:552-559
- New review events are stored with canonical decision IDs.
**Trigger**
- Retry a correct answer after auto-traversing a learned continuation.
- Delete a study or chapter that has already been reviewed.
**Impact**
- Auto-traversal exposure changes can disappear on restart.
- Canonical review events remain after deletion because they are keyed differently from the IDs used by deletion.
- Deleted positions can still affect daily quota and diagnostics.
**Fix direction**
Persist retry side effects or explicitly mark them non-persistent. Add ownership columns for study/chapter/occurrence, delete events by the correct identity, and clean canonical state only when no remaining occurrence owns it.
## M11 — SRS v10 migration creates canonical storage without a backfill
**Confidence: High**
**Evidence**
- lib/src/db/database.dart:135-156
- Migration to schema v10 creates canonicalStateId and position_knowledge_state.
- No INSERT ... SELECT backfill from existing srs_review_state rows is present.
- lib/src/persistence/sqlite_study_repository.dart:760-777
- Session startup still reads legacy per-decision review states.
- lib/src/persistence/sqlite_study_repository.dart:600-620
- Canonical state lookup is separate.
**Trigger**
Upgrade an existing installation with prior review history and shared/transposed positions.
**Impact**
Legacy per-decision state and canonical state can disagree. Different occurrences may start with divergent SRS values, and the first new answer can overwrite or supersede prior state unexpectedly.
**Fix direction**
Perform a transactional migration that derives canonical states from legacy rows, defines deterministic conflict resolution, verifies counts, and records a migration marker only after successful backfill.
## M12 — PGN orientation ignores the actual starting side
**Confidence: High**
**Evidence**
- lib/src/import/pgn_importer.dart:341-356
- resolveChapterOrientation() accepts startTurn.
- lib/src/import/pgn_importer.dart:359-417
- The function never uses startTurn; its final fallback is always Side.white.
- lib/src/import/pgn_importer.dart:260-295
- Decision derivation uses the resolved chapter orientation.
**Trigger**
Import a custom FEN with Black to move and no explicit Orientation/title/player heuristic.
**Impact**
The chapter is marked White-oriented, so Black's repertoire decisions are omitted or trained on the wrong side.
**Fix direction**
Honor the starting turn when no stronger signal exists, or require an explicit orientation for ambiguous custom starts. Add a test with a black-to-move FEN.
## M13 — PGN import reports malformed and truncated input as successful
**Confidence: High**
**Evidence**
- lib/src/import/pgn_importer.dart:182-223
- A zero-game parse returns an empty result with no ImportError.
- lib/src/import/pgn_importer.dart:254-311
- Recoverable move errors produce truncated chapters while errors are only returned as data.
- lib/src/view/review/repertoire_import_dialog.dart:184-202
- The dialog always shows a success message for non-duplicate imports and does not display result.errors.
- lib/src/review/review_controller.dart:1035-1045
- The empty/truncated result is saved and opened as a study.
**Trigger**
Empty/header-only PGN, malformed move text, or a game containing an illegal move.
**Impact**
Users receive a success notification for an empty or incomplete repertoire and may not realize that moves were discarded.
**Fix direction**
Treat zero usable chapters/moves as a failed or explicitly partial import, surface chapter/move errors in the UI, and require confirmation before saving a partial repertoire.
## M14 — PGN duplicate identity ignores repertoire side and is order-dependent
**Confidence: High**
**Evidence**
- lib/src/import/pgn_importer.dart:21-48,68-95
- Hashing uses FEN plus recursively serialized child order.
- repertoireSide is not included.
- lib/src/review/review_controller.dart:981-1022
- An existing PGN hash causes the import to be skipped and the existing study to be opened.
**Trigger**
Import the same tree for White and then Black, or import a reordered equivalent tree.
**Impact**
The second side can be incorrectly treated as a duplicate, or an equivalent tree can be imported twice because child order changes the hash.
**Fix direction**
Include repertoire orientation/side in identity where it affects decisions, canonicalize child ordering, and distinguish exact tree duplicates from semantically equivalent trees.
## M15 — Large imports still hash synchronously on the UI isolate
**Confidence: High**
**Evidence**
- lib/src/review/review_controller.dart:991-995
- computePgnHash(pgnText) runs before the large-import branch.
- lib/src/review/review_controller.dart:1025-1039
- Only the later parse is moved to importPgnAsync().
- lib/src/import/pgn_importer.dart:51-58
- An asynchronous hash helper exists but is not used here.
**Trigger**
Import a large multi-megabyte PGN.
**Impact**
The UI parses and hashes the entire PGN synchronously before background work begins, causing visible frame drops or input stalls.
**Fix direction**
Use the asynchronous hash helper, pass the resulting hash into the worker, and avoid parsing the same PGN twice.
## M16 — Opening Explorer move selection is off by one
**Confidence: High**
**Evidence**
- lib/src/widgets/move_list.dart:97-105,195-198
- Move callbacks are already one-based.
- lib/src/view/explorer/opening_explorer_screen.dart:227-241
- The callback subtracts one before calling jumpToNthNodeOnMainline().
**Trigger**
Tap the first or any move in the explorer inline move list.
**Impact**
The first move navigates to the root rather than the first move; subsequent selections are similarly shifted.
**Fix direction**
Pass the one-based move index directly, or make the navigation API explicitly zero-based and remove the extra adjustment. Add first-move and last-move widget tests.
## M17 — Offline game-history pagination loses scope and filter context
**Confidence: High**
**Evidence**
- lib/src/model/game/game_history.dart:166-192
- Explicit profile users always take the network branch, even when offline.
- The local next-page branch omits userId and filter.
- It uses createdAt as the cursor while local storage orders and filters by lastModified.
- lib/src/model/game/game_storage.dart:33-62
- SQL filtering is limited before post-query perf/side filtering.
- GameFilterState.opponent is not applied locally.
- lib/src/model/game/game_filter.dart:28-40
- setFilter() copies only perfs and side, silently dropping opponent.
**Trigger**
- Load a profile history while offline.
- Change filters and request another page.
- Use a profile/opponent filter.
- Games have different creation and modification times.
**Impact**
The next page can come from the anonymous account, fail despite local data being available, ignore the selected opponent, skip/repeat games, or terminate pagination early.
**Fix direction**
Keep account/filter context in the state, apply filters in SQL or fetch until enough matching rows are collected, use the same timestamp as the storage ordering, and preserve opponent in filter updates.
## M18 — History providers can retain old pages across rebuilds
**Confidence: High**
**Evidence**
- lib/src/model/game/game_history.dart:98-145
- _list is cleared only on provider disposal.
- A rebuild appends the new result to the existing list.
- Auth, connectivity, server-status, and preference changes can rebuild the same family instance.
**Trigger**
Account sign-in/sign-out, connectivity transition, or server status change while the history provider remains alive.
**Impact**
Old-account or old-filter games remain visible alongside newly fetched games, and pagination operates on a mixed list.
**Fix direction**
Make each build generation own a fresh accumulator, or explicitly clear and invalidate the list whenever account/filter/source inputs change.
## M19 — The local game cache has no production writer
**Confidence: High**
**Evidence**
- lib/src/model/game/game_storage.dart:84-91
- GameStorage.save() exists.
- lib/src/model/game/game_repository.dart:28-52
- The repository reads storage as an offline fallback but does not save fetched games.
- Repository-wide search under lib/ found no production call to GameStorage.save().
**Trigger**
Fetch a game while online, then open it later while offline.
**Impact**
The documented offline fallback has no newly cached data and commonly fails with “cannot be found in local storage.”
**Fix direction**
Persist successfully fetched games, including account ownership, or remove the fallback contract until a real cache population path exists.
## M20 — Declared App Links are not associated with the ChessSRS application identity
**Confidence: High for the repository mismatch; Medium for current external endpoint state**
**Evidence**
- android/app/build.gradle.kts:21,39
- Android application ID is org.chesssrs.app.
- ios/Runner.xcodeproj/project.pbxproj:572,849
- iOS runner bundle ID is org.chesssrs.app.
- android/app/src/main/AndroidManifest.xml:72-78
- lichess.org is marked autoVerify="true".
- ios/Runner/Runner.entitlements:7-10
- The app claims applinks:lichess.org.
- During the audit, both assetlinks.json and apple-app-site-association listed the official org.lichess.mobileV2 identity, not org.chesssrs.app.
**Trigger**
Install ChessSRS and tap a supported `lichess.org` study/game/profile link.
**Impact**
Android verification and iOS universal-link handoff can fail, leaving the link in a browser or chooser instead of opening the app.
**Fix direction**
Publish association records for the actual ChessSRS package/bundle IDs and signing identities, or remove the verified-link claim until those records are deployed. Recheck the external endpoints during release validation.
## M21 — iOS Share Extension activation uses the wrong PGN UTI
**Confidence: High**
**Evidence**
- ios/Runner/Info.plist:123-151
- The app exports and declares org.chesssrs.pgn.
- ios/ShareExtension/Info.plist:27-36
- The extension activates only for attachments conforming to org.lichess.pgn.
**Trigger**
Share a PGN represented using the app's exported `org.chesssrs.pgn` type.
**Impact**
The Share Extension is not offered or activated for the app's own PGN type.
**Fix direction**
Use the exported UTI in the activation rule, or explicitly conform it to the legacy UTI and test both paths on a physical iOS device.
## M22 — Opening-database update script can leave the database empty
**Confidence: High**
**Evidence**
- scripts/update_openings_db.py:29-41
- The script opens the production database, executes DELETE FROM openings, commits, then inserts the new rows in a second transaction.
**Trigger**
Malformed source TSV, insertion error, disk-full condition, or process interruption after the delete commit.
**Impact**
The bundled openings database remains empty or partially populated.
**Fix direction**
Build a temporary database, validate row counts/content, then atomically replace the asset. At minimum, wrap deletion and insertion in one transaction and retain a backup.
## M23 — Preference writes are not serialized, and accent selection is not persisted
**Confidence: High**
**Evidence**
- lib/src/model/settings/preferences_storage.dart:48-57
- Saves write storage before updating state, with no operation generation or serialization.
- lib/src/model/settings/preferences_storage.dart:80-89
- Session preferences capture the account before an asynchronous write and do not fence the result to that account.
- lib/src/model/settings/general_preferences.dart:42-59
- Rapid toggle methods derive new values from the current state.
- lib/src/design/theme_bridge.dart:10-18
- SrsAccentNotifier stores accent only in memory and always rebuilds to the default.
- design/docs/05-flutter-implementation.md:113-120
- The design contract requires accent to be persisted like other preferences.
**Trigger**
- Rapidly toggle a setting twice.
- Change accounts while a session preference is saving.
- Select an accent, restart the app, or return to the settings screen.
**Impact**
- One rapid toggle can be lost.
- An old account's asynchronous write can update the new account's visible state.
- Accent selection resets on restart despite the settings contract.
**Fix direction**
Serialize preference writes, attach account/generation tokens, use rollback or optimistic versioning, and persist accent through the existing preferences store.
## M24 — Default HTTP requests have no application-level deadline
**Confidence: High**
**Evidence**
- lib/src/network/http.dart:575-605
- DefaultClient.send() awaits the inner request without a timeout.
- lib/src/model/auth/auth_repository.dart:106-140
- Email-login requests use this client without a caller timeout.
- lib/src/network/http.dart:250-318
- Downloads can also wait indefinitely for headers/body completion.
**Trigger**
A server accepts a connection but never completes headers or the response body.
**Impact**
Authentication, import, or download operations can remain pending indefinitely and leave the UI in a loading state.
**Fix direction**
Apply a default deadline to `DefaultClient`, wrap body consumption separately, and expose cancellation to callers.
## M25 — `expectedLength` is not enforced for truncated downloads
**Confidence: High**
**Evidence**
- lib/src/network/http.dart:263-281
- expectedLength is used as totalLength for progress reporting.
- lib/src/network/http.dart:301-318
- Final validation only checks contentLength; when the response has no Content-Length, a received file shorter than expectedLength can still return true.
**Trigger**
A chunked/truncated response with no `Content-Length` but with a caller-supplied expected length.
**Impact**
A partial engine/database/download asset is accepted as complete and may later fail checksum, parsing, or runtime use.
**Fix direction**
Validate the final byte count against `contentLength ?? expectedLength` and require a positive, known expected size where completeness is promised.
# Low severity
## L1 — Log paginators permit concurrent duplicate page loads
**Confidence: High**
**Evidence**
- lib/src/model/log/http_log_paginator.dart:43-56
- lib/src/model/log/app_log_paginator.dart:45-60
Both `next()` methods lack an in-flight guard. Two scroll notifications can observe the same cursor before either updates state.
**Impact**
Duplicate rows, skipped/overlapping pages, and extra database work.
**Fix direction**
Add a request generation or `_isLoading` mutex and ignore/reject stale page requests.
## L2 — Desktop builds expose engine availability even though native evaluation is unsupported
**Confidence: High**
**Evidence**
- lib/src/model/engine/position_evaluator.dart:46-49
- Native engine support is limited to Android/iOS/test environments.
- lib/src/model/engine/position_evaluator.dart:321-327
- Unsupported platforms set the engine to AsyncData(null).
- lib/src/model/analysis/analysis_controller.dart:862-863
- Availability is based on feature state and preferences, not platform support.
- lib/src/model/study/study_controller.dart:728-731
- Study engine availability has the same platform-independent check.
**Trigger**
Enable the engine on Linux or another unsupported desktop platform and open analysis/study/practice.
**Impact**
The UI offers an engine path that can never produce an evaluation and may wait for the full practice timeout.
**Fix direction**
Gate the setting and action on `isNativeEngineSupported`, or provide a supported desktop backend.
## L3 — Malformed app-link paths fail silently; open-web accepts arbitrary URI schemes
**Confidence: Medium; conditional**
**Evidence**
- lib/src/app_links_service.dart:100-111
- /study assumes a second path segment.
- lib/src/app_links_service.dart:136-155
- /@ assumes a username segment.
- lib/src/app_links_service.dart:164-172
- open-web forwards any parsed URI to launchUrl.
- lib/src/app_links_service.dart:66-71
- Exceptions are logged but not surfaced to the user.
**Trigger**
A malformed external link, or an externally invoked `open-web` link containing a non-web URI.
**Impact**
Malformed links produce no navigation or user feedback. If the custom scheme is externally invokable, arbitrary URI schemes are passed to the platform launcher.
**Fix direction**
Validate required path segments and restrict `open-web` to an explicit `http`/`https` allowlist. Treat the security impact as conditional until scheme reachability is verified.
# Cleared suspicions
These were investigated and are not included as confirmed bugs:
- Root.fromPgnGame variation traversal.
- Within-chapter study/analysis next/previous navigation.
- Promotion payload omission in the normal move path.
- Core saveAnswerBatch transaction atomicity; the transaction itself is sound. The confirmed issue is the caller's pre-persistence mutation and retry handling.
- Normal inactive-study filtering in the standard all-scope path.
- Cold-start app-link double handling; the current stream design intentionally avoids calling both the stream and getInitialLink().
- Inclusive HTTP/app-log cursor boundaries themselves; the confirmed issue is concurrent paginator calls.
- Native iOS shared-PGN handling through the App Group/native Share Plugin path.
- A separate “unreachable account menu” finding. The menu is reachable through More; the confirmed problem is the OAuth callback identity mismatch.
# Overall priority
1. Standardize the OAuth/native application identity and remove cross-host credential exposure.
2. Redact authentication and device-token material from logs.
3. Add generation/cancellation fences to server analysis, sockets, engine work, offline games, cloud evaluation, study chapter loads, and review transitions.
4. Make SRS identity, quota accounting, deletion ownership, migration, and persistence transactional and occurrence-aware.
5. Correct offline clock/position handling and local history/cache behavior before relying on those paths for offline-first guarantees.
