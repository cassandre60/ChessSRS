# Handoff: email login is merged but unverified

Status as of 2026-09-29. Written after a six-Take upstream application run
(`docs/upstream-audit-2026-09-29.md`, PR #95 — still open at the time of writing;
this file is self-contained if that PR is not merged).

**Nothing in the product is blocked by this.** The app is local-first: review, import,
studies and settings all work signed out. Login exists only to import *private or
unlisted* Lichess studies (C3, `CUT_PROPOSALS.md`). This document exists so the next
agent does not re-spend a day on it.

---

## 1. What is waiting

**PR #94 — `fix(auth): send email login credentials in POST body, not query string` — is
merged and green, but has never run against the real server.**

It moves the login code, email and username out of the query string of
`POST /auth/mobile-code/{email,bearer}` and into the form body. Query strings land
verbatim in proxy access logs and in the app's own 7-day `http_log` table, so the
one-time code was sitting in plaintext local storage. Upstream merged the equivalent
(`a99dad8a1`, `214bb0353`) with a note that the matching lila change had to deploy
first, so server support is *presumed* present but was never confirmed for this fork.

**The single remaining check:** one successful email-code sign-in against production.

**If it fails**, the revert is small and known-good: restore the two `lichessUri(path,
{...})` call sites in `lib/src/model/auth/auth_repository.dart` and revert the three
updated test assertions in `test/model/auth/auth_repository_test.dart` and
`test/view/auth/email_login_screen_test.dart`. Nothing else depends on it.

---

## 2. The actual blocker, and why it is not a code bug

The app targets the **Lichess dev server by default**:

```dart
// lib/src/constants.dart:4
const kLichessHost = String.fromEnvironment('LICHESS_HOST', defaultValue: 'lichess.dev');
```

This is inherited upstream behaviour, documented in `docs/setting_dev_env.md` ("Lila
Server"), and correct for server development. It means a plain

```
fvm flutter run -d linux
```

talks to `lichess.dev`, where `/auth/mobile-code/*` and `/api/player/autocomplete`
behave differently from production. The user-visible symptom is
**"We couldn't find any user by this name"**, which points at the *typed username*
and sends you hunting through validation code that is already correct.

**To verify #94, run with the production host:**

```
fvm flutter run -d linux --dart-define=LICHESS_HOST=lichess.org
```

## 3. What was already ruled out — do not redo this

Each of these was checked line by line against `upstream/main`. All are identical to
official Lichess mobile apart from Dart 3.12 constructor spelling, one translated
title, formatting, and #94 itself:

| Suspect | Verdict |
|---|---|
| `_emailRegExp` in `email_login_screen.dart` | Byte-identical to upstream. Accepts dotted, plus-tagged, capitalised, sub-domain and quoted addresses; rejects only domains with no dot. |
| `AuthRepository.requestEmailLoginCode` / `signInWithEmailCode` | Identical apart from #94's body params. |
| `AuthController` | Identical apart from constructor syntax. |
| `UserRepository.usernameExists` | Identical. It lowercases the term and requires a verbatim match among autocomplete completions, which is correct for Lichess (usernames are lowercase-only). |
| A widget test through the real `EmailLoginScreen` with the owner's address | **Passes** — moves to the code step. The screen does not reject the address. |

Verified live against production: `GET https://lichess.org/api/player/autocomplete`
returns real accounts for correct terms, and the WebSocket failures visible in run logs
(`/socket/v5` → 400) are an artifact of the dev-server default too, not a defect.

**Also not a bug:** there is no password field, and there never will be. No Lichess
client may accept a password — lila exposes only OAuth/`flutter_appauth` and the
email-code exchange. Official Lichess mobile has exactly the same two options
(browser, email code). The owner's expectation of "user + password" cannot be met by
any client-side change.

---

## 4. The other half of the wasted day: a stale checkout

The owner's local `main` sat at `ea1d09678` (2026-09-29) for the whole session while
seven PRs merged to `origin/main` (`388b38f3e`). Every `fvm flutter run` rebuilt the
old app. The visible symptom was **"the Account section is missing from Settings"** —
it arrived in PR #84, after the frozen commit. Combined with a second, correctly
configured app being launched from a worktree, there were two windows on screen with
different features, which produced a long loop of contradictory observations.

The Account section is the first section of `SrsSettingsScreen` and is unconditional;
it cannot hide. If it is ever absent from a build that is on current `main`, that is a
real bug and should be reported as one.

**Rule for the next agent:** the owner's own `flutter run` is the acceptance gate for
a batch of Takes. After merging, pull `main` in the primary checkout and say so
explicitly, or the next session starts from stale code again. Verify with
`git log --oneline -1` in the primary checkout versus `origin/main`.

---

## 5. Suggested next steps

1. `git pull --ff-only` in the primary checkout (it is now current; it was not during
   the session that produced this note).
2. Run once with `--dart-define=LICHESS_HOST=lichess.org` and complete one email-code
   sign-in. Success closes #94; failure starts the revert above.
3. Consider whether the fork wants the production host as the default, or an
   `AGENTS.md` note that any auth verification needs the flag. This is a product-owner
   decision, not an agent decision — the dev default is correct for server work.
4. Sign-in is not needed for anything in the MVP. Do not spend MVP time on it beyond
   the single verification above.
