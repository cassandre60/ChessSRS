# Lichess sign-in: what was actually wrong, and how it was verified

Status: **resolved** 2026-10-02. Supersedes the "merged but unverified" version
of this file, which described a single outstanding check that turned out to be
five separate defects.

**Sign-in works.** Verified on Linux desktop against `lichess.org`: the owner
signed in through the browser, the session survived navigation, and a private
study imported (`GET /api/study/Gg4E2sIS.pgn → 200` in the app's `http_log`).

---

## Why this file exists

It was written on 2026-09-29 to stop the next agent re-spending a day on the
symptom *"We couldn't find any user by this name"*. That advice was correct and
is preserved below, but the conclusion it reached — that PR #94 was the only
thing standing between the app and a working sign-in — was wrong. It is kept
because the ruled-out list is what makes the next occurrence cheap to dismiss.

## The symptom, and what it was not

The app reported *"We couldn't find any user by this name"* for a real address,
while `curl https://lichess.org/api/player/autocomplete` returned accounts.

Ruled out on 2026-09-29, still true, do not re-investigate:

- `_emailRegExp`, `AuthRepository`, `AuthController` and
  `UserRepository.usernameExists` are **byte-identical to upstream**. The bug was
  never in them, and the repository was not modified in the ways that would have
  explained it.
- A widget test through the real `EmailLoginScreen` accepts the owner's address,
  so the address is not being mangled in transit.
- **No Lichess client accepts a password.** A "user + password" request is not
  implementable and must never be treated as a bug to fix.

## The five defects, in the order they had to be fixed

| # | Defect | Fix |
|---|---|---|
| 1 | `kLichessHost` defaulted to `lichess.dev` (correct upstream, wrong for a consumer app), so a plain `fvm flutter run` sent `/auth/mobile-code/*` to the dev server | #124 — `lichess.org` by default; **no `--dart-define` needed any more** |
| 2 | The mobile-code endpoints were called with credentials in the POST body only; lila reads them from the query string | #123 — body first, retry with query parameters on 404 |
| 3 | `flutter_appauth` is Android/iOS-only, so there was no desktop sign-in path at all | #125 — loopback PKCE over a local `HttpServer` plus `url_launcher` |
| 4 | `authControllerProvider` was `autoDispose`, so the session died on navigation. Safe upstream only because cut subsystems (lobby, friends carousel) kept listeners alive | #126 — de-`autoDispose`d |
| 5 | Every WebSocket handshake was refused with `HTTP 400`: the `sri` query parameter was never sent | #129 — `queryParameters['sri'] = sri` |

Defects 1 and 5 are the ones that cost the most time, and both produced a
symptom pointing somewhere else entirely.

### Defect 5 in full, because it is the one that hides

The account menu's ping tile read `Offline` after a successful sign-in. It was
not the device being offline — `Connectivity` logged `isOnline: true` throughout.
The app's own `app_log` held the answer nobody was reading:

```
Socket|WARNING|WebSocket connection to /socket/v5 failed (for 2519s now),
retrying in 60000ms: WebSocketException: Connection to
'https://socket.lichess.org:0/socket/v5#' was not upgraded to websocket,
HTTP status code: 400
```

Lila identifies a socket by the `sri` query parameter and refuses the upgrade
without it. Confirmed against production with a standalone `dart:io`
`WebSocket.connect` probe: no `sri` → `400`; `?sri=<value>` → `101` and a pong.
The `User-Agent` is **not** read for this, in any format — upstream's own
`LichessMobile/… sri:x` agent string fails identically. This is inherited from
`lichess-org/mobile`, whose `connect()` is the same, so it never worked on any
platform.

Knock-on effect: cloud Stockfish evaluation and study sync had no live socket
for the entire life of the app.

## What "study sync" means here

Not editing studies inside the app. `StudyController.handleSocketEvent` handles
lila's `promote`, `deleteNode`, `anaMove`, `anaDrop` and `liking` topics — so it
is **live following of edits made to a study elsewhere**: you change the study
in a browser tab on lichess.org, or someone else does, and the app applies it to
the open tree while you are looking at it. Edits to a chapter you are *not*
viewing are ignored (`_isRemoteEditForCurrentChapter`). The app never writes to a
study.

This matters for C3: the app's relationship to a Lichess study is read and
import, never author.

## Still unverified

**Email-code sign-in on Android and iOS.** No device was attached during this
work, so the mobile path — defects 1 and 2 above — has never run against
production. Desktop uses OAuth and is verified. If a phone build is ever run,
that is the one remaining check, and the query-parameter fallback in #123 is what
it exercises.

## Sixth defect (2026-10-09): `scope=web:mobile` on the mobile OAuth request

Sign-in on a phone stopped at Lichess's *Bad authorization request / Invalid
scopes* page. The mobile path goes through `flutter_appauth`, which serialises
its `scopes` list into the authorize URL's `scope` parameter — and that list was
`['web:mobile']`.

`web:mobile` is a scope lila **owns**: it is the scope of its `lichess_mobile`
signed client, and `OAuthSignedClients.forReq` refuses the whole request unless
the `client_id` and redirect origins match that registered client. So no
third-party `client_id` — `chess_srs` included — can ever be granted it, and
asking for it is what 400s. `web:polygon` behaves the same for `takex3`.

Verified against production with the exact query from the owner's screenshot
(`client_id=chess_srs`, `redirect_uri=org.chesssrs.app://login-callback`):

| `scope` | `/oauth` answer |
|---|---|
| `web:mobile` | 400 Invalid scopes |
| `web:polygon` | 400 Invalid scopes |
| `study:read study:write preference:read` | 303 → /login (accepted) |
| *(absent)* | 303 → /login (accepted) |

So *any* ordinary scope is accepted for a third-party client; only the
client-owned `web:*` names are refused. The fix asks for the three scopes this
app's endpoints actually need — `study:read` (`GET /api/study/:id.pgn`),
`study:write` (`POST /api/study/:id/import-pgn`), `preference:read`
(`GET /api/account/preferences`) — and the regression tests assert that no
client-owned name can come back.

The trap worth remembering: the previous sign-in fix read *bad scope* and
concluded "this app must send no scope", removed it from the desktop URI, and
left the mobile list holding the one scope that can never be granted. Study and
preference names are ordinary scopes, not "token capabilities" — that comment was
what kept the wrong value in place.

**Not fixed, and not fixable by scope:** `POST /api/account/preferences/:name` is
`ScopedBody(_.Web.Mobile)` in lila, so a third-party token can never write an
account preference. Reads work; the settings screen's writes still fail while
signed in, on every platform (the desktop path has the same failure, since it
requests no scope at all). Worth its own bug report before beta.

## Regression coverage

| What | Where |
|---|---|
| mobile-code query-parameter fallback | `test/model/auth/auth_repository_test.dart` |
| session survives navigation | `test/model/auth/auth_controller_test.dart` |
| sri in the socket query string | `test/network/socket_test.dart` |
| mobile OAuth scopes never include a client-owned `web:*` name | `test/model/auth/auth_repository_test.dart` |

The sri case could not be gated: G05 judges a PR's test citations against the
**base** ref's `SPEC.md`, so no PR can introduce a new SPEC invariant. That
blocker, and a second bug where `gates.yml` omits `labeled` from its trigger
types (so adding `gate-approved` never re-runs the gate), are recorded in the
`GATES.md` escapes log.
