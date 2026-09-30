# Audit disposition

The 37 findings in `audit.md`, and what became of each. `audit.md` itself is
accurate as a *description* of the problems but its status is out of date — it was
written against a tree that has since changed substantially, and several of its
line references no longer point at the code it describes.

This file is the record of what was verified and what was decided. It exists so
the next person does not have to re-derive it from eleven pull requests, and so
the reasoning behind the judgement calls is available rather than implied.

**How to read the categories.** *Fixed* means the code changed. *Closed* means no
code change was warranted — the finding was already handled, was inherited
upstream unchanged, or was wrong. *Out of scope* means the underlying behaviour is
real but is upstream's and was deliberately left alone. *Open* means it still
needs a decision or work this session could not do.

## Summary

| | Count |
|---|---|
| Fixed | 23 |
| Closed without a change | 9 |
| Out of scope by the inherited-code rule | 3 |
| Open | 2 |
| **Total** | **37** |

M24 moved from *out of scope* to *fixed*, as a deliberate divergence from upstream
rather than an oversight — the reasoning is under its entry below.

Two findings are counted in *closed* but are softer than the rest: **M23**, where
only one of three sub-claims was in scope, and **H1**, where the audit's evidence
was stale and the finding was overruled rather than fixed.

## Fixed

| # | Finding | Change |
|---|---|---|
| H5 | Review answers mutate the session before persistence | Roll back the in-memory session when the write fails |
| H6 | Offline game work not fenced to its game | Generation counter on the game controller |
| H7 | Canonical review identity is lossy | Identity is the full answer set; v14 rekey migration |
| H8 | Study collaboration ignores incoming edits | Apply promote, delete, anaMove, anaDrop |
| H9 | Socket queue survives an account change | Drop both queues on auth change |
| M1 | Server-analysis stale-request race | Request generation |
| M2 | Socket version gaps retried without recovery | Reconnect from the last committed version |
| M3 | Engine callbacks outlive the request | Fence to the generation that started the work |
| M4 | Cloud eval uncorrelated | Generation, 5s deadline, and a test that a reply arriving before a listener is dropped |
| M7 | Chapter selection on the wrong chapter | Publish the chapter that was switched to |
| M8 | Review scope reloads commit out of order | Generation on both `ReviewService` and the controller |
| M9 | Retry loses quota credit | Retries count toward the daily quota |
| M11 | v10 migration has no backfill | v14 rekey with backfill |
| M12 | PGN orientation ignores starting side | Honour the side the line starts on |
| M13 | Malformed PGN reported as success | Refuse to store an untrainable study |
| M14 | Duplicate identity ignores side | Side-aware lookup in SQL, without a hash format change |
| M21 | Share extension uses the wrong UTI | Aligned identifiers across plist, manifest and Swift |
| M22 | Opening DB script can leave it empty | Build to temp, validate, atomically replace |
| M25 | `expectedLength` not enforced | Hold downloads to the expected length |
| L1 | Log paginators permit duplicate loads | In-flight guard |
| L2 | Engine offered on unsupported platforms | `isLocalEngineOffered` gates on platform |
| L3 | Truncated links throw silently | Guard the missing path segments; refuse non-web `open-web` targets |
| — | *Not in the audit:* "rate this app" opened the upstream app | Derive store links from this app's own identity |
| — | *Not in the audit:* accent selection was never persisted | Stored with the other general preferences |

**M24 — no deadline on `DefaultClient`, fixed as a deliberate divergence.**
`LichessClient.send` had a 15s `defaultRequestTimeout` and `DefaultClient.send` had
none, so a server that accepted the connection and then went quiet left the request
pending forever. `DefaultClient` now takes the same constant, referenced rather
than restated so the two cannot drift, and overridable per client.

It is in *Fixed* rather than *Out of scope* because it was changed, and that was a
judgement call worth recording. It is inherited upstream code, unchanged, and the
standing rule is that upstream behaviour is not this fork's to change unilaterally.
The reasoning for doing it anyway: this fork amplifies the consequence rather than
inheriting it as-is. It is local-first, and the opening database, NNUE weights and
Maia book all download through this client, where upstream's traffic is mostly
short cloud calls. A stall on a multi-megabyte download is an app sitting and
waiting with no way out.

The test demonstrates the symptom rather than describing it: against the unfixed
client it does not fail, it hangs until the test framework's own 30-second timeout
fires — which is what a user would have experienced.

## Closed without a change

**H1 — OAuth callback scheme.** The audit reported the Dart side building
`org.lichess.mobile://login-callback` while the native apps registered
`org.chesssrs.app`. Not so: `constants.dart` has carried `org.chesssrs.app` since
the first fork commit, and `kOAuthRedirectUri` is derived from it. What was missing
was a check, so one was added asserting all three agree — it fails if a future
rename reaches one and not the others.

**H3 — credentials on cross-host requests.** Already fixed by the fork: the
`Authorization` header is gated on `isMainHost` at `http.dart:442`, and the fork
went further, also gating the User-Agent identity and the server-status check.

**H2 — auth transitions not fenced.** Also already fixed by the fork, and the
fixing is thorough: `AuthController` carries a generation, `checkToken` captures it
before the network call and re-checks both it and the token's identity afterwards,
`signOut` re-checks around its 500ms delay, and concurrent validations for one
token are de-duplicated. The 401 handler passes the *captured* user, so a stale
response cannot act on a newer session — which was the finding's central claim.
None of it was tested, and the 401 path is unawaited by design, so a test now pins
it. The first version of that test passed for the wrong reason: the provider is
`autoDispose`, and a bare read with no listener collects it immediately, so
`checkToken` returned before doing anything at all.

**H4 — credentials in logs.** Was open; a partial implementation was lost before
this audit pass reached it. Specified in `h4-credential-redaction.md` and
implemented. Three secrets reached two SQLite tables: the one-time login code, the
email and username, and the FCM token. Note the severity is narrower than it first
appears — Crashlytics forwarding requires `SEVERE` or above and every affected
site logs below that, so this was local persistence plus in-app visibility, not
remote disclosure.

**M18 — history providers retain old pages.** Not reachable. `_list` is cleared in
`ref.onDispose`, and `onDispose` fires on rebuild as well as on disposal, so a
rebuild does not carry pages across. Confirmed by instrumenting a notifier: the
instance is reused across the rebuild, yet the accumulated list holds only the
newest build's entry. A test now pins the account-switch behaviour.

**M16 — opening explorer off by one.** Not a defect. `UciPath.penultimate` returns
empty for a single-pair path, so a "walk to root" loop stops one node short by
design.

**M5 (terminal-position half) and M6 (material accounting).** Both inherited from
upstream unchanged. M5's terminal half would also have required a product
decision — reject or normalise — which is not this session's to make.

**M17 — game-history pagination.** Every one of its six sub-claims is accurate as
a code fact, and every one is inherited unchanged: `page()` and `setFilter()` are
byte-identical to upstream. Four are additionally unreachable, because nothing in
this fork writes the game-storage table — upstream's `_storeGame` lived in
`game_controller.dart`, which the fork deleted. One sub-claim is simply wrong: it
says profile users "always take the network branch, even when offline", and the
code does the opposite.

## Out of scope by the inherited-code rule

These are real behaviours, upstream's, and left alone deliberately. Changing any of
them is a conscious divergence and should be recorded as one.

**M10 and M15** ship unproven. M10's retry path was settled by instrumentation —
the path is live and the fix is not dead code — but no test proves it, because
every attempt built a session where the retry had nowhere to advance to. M15's
hash-offloading is unproven and unreachable under test. Both are recorded in
`audit-unverified-fixes.md`.

**M23, two of three sub-claims.** The audit also reported that preference writes
are unserialized and that `SessionPreferencesStorage` does not fence a write to the
account that requested it. Both are inherited unchanged — the fork's diff to
`preferences_storage.dart` is import renames, enum syntax and two dropped upstream
categories, and the `save`/`fetch` bodies do not appear in it. The lost toggle is a
real bug; it is not a regression this fork introduced. Only the accent claim was in
scope, and it is fixed.

**M24 — no deadline on `DefaultClient`.** Accurate, and asymmetric:
`LichessClient.send` has a 15s `defaultRequestTimeout` and `DefaultClient.send` has
none. `DefaultClient.send` is inherited unchanged, and no project invariant
requires a deadline — `QUALITY.md` §3 covers PGN degradation and deterministic
clocks, §4 is performance.

**Worth the owner's judgement anyway**, because this fork amplifies the
consequence: it is local-first, and the opening database, NNUE weights and Maia
book all download through the client with no deadline, where upstream's traffic is
mostly short cloud calls. A stall there leaves the app waiting with no way out. The
change would be one line — give `DefaultClient` the timeout its sibling has.

**M24 — no deadline on `DefaultClient`.** Fixed, as a deliberate divergence from
upstream rather than an oversight. The reasoning is under *Fixed* below, because
the reason matters more than the diff.

## Open, each with a default taken

Two items remain. Neither is a bug this audit failed to close, and neither blocks
anything — both are decisions, and both now carry a default so that *not* deciding
is a choice rather than a stall. The defaults are the ones this audit would ship;
overriding either is a small change.

**M19 — the local game cache has no writer.** Upstream's `_storeGame` was in a file
the fork deleted, so the cache is never populated. The three resolutions (cache
everything, cache above a size threshold, drop the offline promise) have different
consequences, so this is a product decision.

**Default taken: leave it.** No writer means no behaviour change and no risk, and a
cache nothing populates is dead weight either way. Writing one is only worth doing
as part of the game-import feature, which supersedes it — so this closes as
superseded if that goes ahead, and stays open on its own merits if it does not.
Revisit with that feature, not before.

**M20 — App Links identity. Closed as far as this fork can take it.** The app no
longer claims verified `lichess.org` links it cannot be verified for, since the
published association files name the official Lichess identity.

The "publish the records" half of the original fix direction is **not available to
this fork at all**: the association file that would name `org.chesssrs.app` is
served from lichess.org, and only Lichess's operators can publish it. That is not a
task waiting on anyone here — it is permanently out of reach, on any timeline. The
remaining option, and the one taken, is for the app to stop claiming what it cannot
prove. This becomes ordinary app-links work only if ChessSRS gets its own domain.

**`firebase_options.dart` still declares `iosBundleId: 'org.lichess.mobileV2'`.**
Found while fixing H1 and not in the audit. It is a generated file, so the fix is a
Firebase-console decision about which project owns iOS telemetry; a code edit would
be overwritten on the next regeneration.

## The unresolved thread, closed

`test/app_test.dart` — the startup token check — was **skipped and blamed on a
machine difference**. That was wrong, and the thread is now resolved. The test has
been removed; the behaviour it claimed to cover is still untested, and that is
recorded below rather than hidden.

**The cause: the test asserted on a side effect of a provider the harness replaces.**
`makeTestProviderScope` overrides `preloadedDataProvider` with a static tuple, and
that provider is the only code in the app that reads the stored token and issues
`/api/token/test`. With it stubbed, the request cannot be issued by anything, so
`tokenTestRequests` was structurally `0` and `expect(tokenTestRequests, 1)` could
never pass. The stub has been in `test/test_provider_scope.dart` since the fork's
foundation commit.

A diagnostic that counted HTTP clients settled it in one run: the app created
**one** client, for the FCM registration. No client was ever built for the token
check, because no code that would build one ran.

Two things followed from that, and both are why the earlier diagnosis kept failing:

- **It was never a CI-only difference.** The test fails identically on a developer
  machine — verified by un-skipping the pristine file and running it locally. The
  "passes here, fails on the runner" behaviour in the old comment was a misreading
  of a run where the test was still skipped.
- **Its precondition passed vacuously.** The test asserted that
  `preloadedDataProvider.future` carried a non-null `authUser` before asserting the
  request. It was reading the *stub*, whose `authUser` is the test's own input
  parameter. That assertion could never fail, while looking exactly like coverage of
  the path under test.

The mock interception theory was also wrong, and was wrong twice: the `quick_actions`
mock added to `test/binding.dart` was a real fix (it aborted app startup on
Android and iOS), but it was never the cause of this failure.

**What is still untested, stated plainly:** when Lichess reports a stored token is
no longer valid, the app deletes it (`preloaded_data.dart`, the `if (token != null)`
branch). That branch is credential-handling and has no test. It is not reachable
from an app-level test, because reaching it means running the real
`preloadedDataProvider`, which needs `package_info_plus`, `device_info_plus` and
`path_provider` — none of which the shared binding mocks. Testing it properly means
either mocking those three channels and giving the helper a way to *not* stub the
provider, or lifting the token check into a provider of its own that depends only on
`authStorageProvider` and `httpClientFactoryProvider`. Both are real work; neither
is a five-minute fix, and the second changes production structure for testability.

**Decided: deferred, not done.** The owner reviewed this and the call is to leave the test
unwritten for now, on the grounds that it belongs with the study-import work rather than
ahead of it. Recorded in `IMPLEMENTATION_PLAN.md` under Future Horizon so it is picked up
with that work rather than rediscovered later.

**A correction, because the reasoning above was wrong in one respect.** An earlier draft
of this note claimed the branch was effectively unreachable because study import had not
been built. **That is false, and it came from misreading two other findings.** M19 (the
offline *game* cache with no writer) and M17 (an unreachable table) are about game
history, not study import.

Study import is built and reachable today:

- `ReviewController.importLichessStudy` calls `/api/study/$id.pgn` (`IMPLEMENTATION_PLAN.md`, Phase 6).
- The import dialog offers *Lichess Study* as a source alongside PGN text and file.
- `LichessClient` attaches `Authorization: Bearer <token>` automatically for main hosts (`network/http.dart:530`).
- Sign-in is reachable from the account menu (`view/account/account_menu.dart:170`).

So a signed-in user's token really is validated at the next launch, and really is deleted
when Lichess reports it dead. **This is live code, not dead code.**

**A second correction, 2026-09-29: the fourth bullet above was circular, and sign-in was not
reachable at all.** `account_menu.dart:170` is the `onPressed` of the sign-in button *inside*
`AccountMenuScreen`, so citing it as evidence the account menu was reachable proved nothing —
it is a line within the subtree whose reachability was the claim. The check that settles it is
reachability from the widget tree, not the presence of a handler:

- `AccountMenuButton` was never instantiated anywhere in the app. Its sole reference to
  `AccountMenuScreen.buildRoute` was inside its own closure, and no view constructed the button.
- `AccountMenuScreen` was referenced only from its own file.
- `showSignInOptions` was called only from inside `AccountMenuScreen`.
- `signOut` was invoked only from inside `AccountMenuScreen`.

So both signing in and signing out were impossible from the UI, which also made this note's
own claim that study import is "built and reachable" wrong in the part that matters most: a
private study needs a token, and there was no way to obtain one. The bullet above is retained
as written because this note is a record of what was believed on the date it was written, and
the correction belongs next to it rather than replacing it.

Fixed in PR #84 (merged 2026-09-29): an `Account` section in `SrsSettingsScreen` provides the
entry point, and the import dialog offers sign-in in context when a study import comes back 404
while signed out — the case that is ambiguous, since Lichess answers the same for a private
study as for one that does not exist.

The lesson generalises past this finding: **a reachability claim needs a reference from outside
the subtree it describes.** A handler inside an unreachable screen is not evidence the screen is
reachable, and the grep that seemed to confirm it — finding `AccountMenuScreen` at all — is
exactly the check that passes while the bug is live.

That does not change the decision, but it does change why the decision is defensible:

- It is **inherited upstream code, unchanged since the fork's foundation commit**, with years of production use behind it. The project's own rule is that inherited behaviour is not this fork's to change unilaterally, and reshaping working code purely so a test can reach it is the weakest version of that rule.
- The **failure mode is a nuisance, not a loss**: an unexpected logout, or staying signed in with a dead token until a later request 401s. No data loss and no credential exposure. The branch errs toward *deleting* a credential, and the `catchError` keeps a network blip from logging anyone out.
- It is **live but not urgent**, which is a different claim from unreachable. The natural time to test it is while the study-import UX is being shaped, because that is when the expectations around "signed in" get pinned down.

The distinction matters for whoever picks this up: the gap is real, and so is the argument
for leaving it alone. Neither was true of the earlier version of this note.

## What the ratings were worth

Six findings marked "High confidence" turned out to be already fixed (H1, H3, H4),
inherited-and-unreachable (M17), or wrong as written (M18, and one M17 sub-claim).
None of the ones that turned out to be live defects was found by trusting the
rating.

What did correlate was **file-level evidence pointing at fork-introduced code**.
That is the heuristic worth applying to a future audit of this fork, and it is
recorded in `AGENTS.md` for the same reason.

## 2026-09-30 release readiness audit

See `docs/release-audit-2026-09-30.md` for the full assessment. Summary of new
findings and actions:

| # | Finding | Disposition |
|---|---|---|
| F1 | Firebase still points at Lichess (`lichessv2`) | **Open — owner decision required** |
| F2 | Android notification icon was Lichess horse head | **Fixed** (`ic_stat_notification.xml`) |
| F3 | iOS display name "Lichess" in pbxproj | **Fixed** (`ed4f7a5b7`) |
| F4/F9 | iOS LichessWidgets extension is dead code | **Cut** (PR #100) |
| F5/F10 | Android broadcast widget is dead code | **Cut** (PR #100) |
| F7 | Dead hintUsed/multipleAttempts in FSRS scheduler | Not a bug — dead future-intent code |
| F8 | Silent exception swallowing in PGN hash | **Fixed** (`1182d7188`) |
