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
