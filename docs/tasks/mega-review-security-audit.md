# Security & Data Integrity Audit — ChessSRS

**Auditor:** security-auditor (mega-review swarm)
**Date:** 2026-11-17
**Scope:** Full codebase under `lib/src/`, configuration, and persistence layer

---

## Executive Summary

ChessSRS is a **local-first** app with optional Lichess sign-in. Its attack surface
is narrow: no server of its own, no cloud data store, no user-generated content
shared between devices. The main risks are credential handling on the Lichess
OAuth path, SQLite data integrity, and malicious-PGN resilience.

**Overall posture: Solid.** The codebase demonstrates good security awareness —
comprehensive log redaction, parameterized SQL throughout, PKCE OAuth with state
verification, WAL mode, transactional writes, and input size limits. The findings
below are refinements, not emergencies.

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 4 |
| Low | 5 |
| Info | 5 |

---

## Findings (Priority Order)

---

### H-1 · Email/username fallback to query string exposes credentials in transit logs (High)

**Files:** [auth_repository.dart](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/model/auth/auth_repository.dart#L302-L317), [auth_repository.dart](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/model/auth/auth_repository.dart#L337-L361)

**Finding:** `requestEmailLoginCode` and `signInWithEmailCode` both attempt a
body-only POST first, then fall back to putting `email`, `username`, and `code`
in the **query string** when the server responds 404/400. While the app's own
`http_log` table is protected by `redactUriForLogging`, query-string parameters
are visible to:

1. **Proxy / corporate firewall logs** between the device and Lichess — these see
   the full URL in the CONNECT or GET line.
2. **Server access logs** on the Lichess side (the sender cannot control this).
3. **Crash-report / analytics SDKs** that capture the last HTTP request URL.

The fallback exists because Lila's `queryStringGet("email")` reads the query
string on some endpoints. SPEC INV-006 acknowledges and accepts this ("secrets
are body-first with a redacted query-string fallback").

**Exploitation:** A network observer (e.g. corporate TLS-intercepting proxy) can
read the user's email, username, and one-time login code from the URL. The code
is single-use and short-lived, limiting the window, but the email is durable PII.

**Severity rationale:** Elevated to **High** because the email is personal data
under GDPR/CCPA, and the code, while time-limited, is a bearer credential for
the duration of its validity.

**Remediation:**
- Coordinate with Lila to accept body-only on these endpoints and remove the
  query-string fallback entirely.
- If the fallback must stay, document the risk in SPEC INV-006 and ensure the
  code TTL is as short as feasible.
- Consider adding an `X-Sensitive-Request: true` header so proxies with
  such awareness can suppress logging (defense-in-depth only).

---

### M-1 · `kLichessWSSecret` hardcoded with sentinel default (Medium)

**Files:** [constants.dart](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/constants.dart#L11-L14), [bearer.dart](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/model/auth/bearer.dart#L6-L14)

**Finding:** The WebSocket secret is provided via `--dart-define` with a default
of `'somethingElseInProd'`. When the secret equals the default, `signBearerToken`
returns the token unsigned — a correct shortcut for development. However:

1. The sentinel is **committed in source** and can never be used in production
   without signalling "skip signing."
2. If a release build is accidentally compiled without the define, every bearer
   token goes unsigned and the WebSocket connection authenticates with the raw
   token. For Lichess's server this is harmless (it ignores the HMAC suffix for
   public OAuth tokens), but it is a silent misconfiguration.

**Remediation:**
- Assert at startup that the secret is *not* the sentinel when `kReleaseMode`
  is true, failing fast rather than silently degrading.
- Alternatively, move the sentinel check to a compile-time constant or add a CI
  check that production builds pass a real secret.

---

### M-2 · `allowInsecureConnections: kDebugMode` in OAuth (Medium)

**File:** [auth_repository.dart](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/model/auth/auth_repository.dart#L163)

**Finding:** `flutter_appauth`'s `allowInsecureConnections` is `true` in debug
mode. This is intentional (local Lila development), but it is worth documenting
that:

- A debug build on a hostile network (public WiFi) would accept an OAuth redirect
  over plain HTTP, making the authorization code interceptable.
- This cannot happen in release builds (`kDebugMode` is `false`).

**Remediation:** Already correct for the intended use. Add a code comment or
SPEC note confirming the debug-only scope so future auditors do not re-flag it.

---

### M-3 · Desktop loopback OAuth binds to `0.0.0.0` equivalent (Medium)

**File:** [auth_repository.dart](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/model/auth/auth_repository.dart#L190)

**Finding:** `HttpServer.bind(InternetAddress.loopbackIPv4, 0)` binds to
`127.0.0.1`, which is correct — but only IPv4. On a dual-stack desktop, another
process on `::1` (IPv6 loopback) cannot reach this, which is fine. However:

- The ephemeral port is unguarded except by the `state` parameter. The state
  verification in `awaitOAuthCallback` (line 93) correctly rejects callbacks
  with a mismatched state, which is good.
- The `/callback` path filter and state check are properly implemented.

**Actual concern:** The 5-minute `timeout` on the callback means the loopback
server holds a port open for up to 5 minutes. Any local process that knows the
port and can guess the state parameter (32 bytes of `Random.secure()`, so this
is infeasible) could inject a callback. This is adequately mitigated.

**Remediation:** Satisfactory as-is. Consider logging a warning if the port
stays open the full 5 minutes (timeout hit).

---

### M-4 · `VACUUM INTO` path-injection edge case (Medium)

**File:** [database.dart](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/db/database.dart#L593-L614)

**Finding:** The `_archiveNewerDatabase` function constructs a SQL statement:
```dart
await source.execute("VACUUM INTO '${_escapeArchivePath(destination)}'");
```
`_escapeArchivePath` escapes single quotes (`'` → `''`), which is the correct
SQLite escaping for a string literal. The path comes from `getApplicationSupportDirectory()`,
which is OS-controlled and not user-supplied, so injection is not exploitable
in practice.

**Remediation:** Satisfactory. The escaping is correct and the input is trusted.
No action needed. Document the trust boundary in a code comment.

---

### L-1 · `saveChapters` performs node replacement outside the transaction (Low)

**File:** [sqlite_study_repository.dart](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/persistence/sqlite_study_repository.dart#L430-L443)

**Finding:** `saveChapters` batches the chapter inserts, commits them, then loops
through each chapter calling `_replaceChapterNodes(_db, chapter)` individually.
Each `_replaceChapterNodes` call deletes and re-inserts the node rows outside
the chapter batch's transaction. If the app crashes between the chapter write and
the node write, the chapter exists but its nodes do not.

This is distinct from `saveImportResult` (line 100), which correctly wraps
everything in a single transaction.

**Impact:** Orphaned chapters with missing node data. The app would need to
re-import the PGN to fix this. Low severity because the window is tiny and the
consequence is recoverable.

**Remediation:** Wrap the whole `saveChapters` body in a `_db.transaction(...)`.

---

### L-2 · User-Agent includes user ID in plaintext (Low)

**File:** [http.dart](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/network/http.dart#L222-L232)

**Finding:** `makeUserAgent` includes `as:${user?.id ?? 'anon'}` in the
User-Agent header. This is intentional and matches Lichess Mobile's behavior —
it allows server-side debugging. The user ID is their public Lichess username,
so it is not private PII. However, it is sent on *every* HTTP request, including
to non-Lichess hosts (opening explorer, tablebase), because `DefaultClient` does
not filter by host.

**Remediation:** `LichessClient.send()` correctly sets the user ID only for the
main host (line 410). `DefaultClient` uses a UA constructed at provider creation
time, which includes the user at that instant. This is benign but could be
tightened by omitting the user ID for third-party requests if desired.

---

### L-3 · App log persistence stores log messages without redaction in debug mode (Low)

**File:** [app_log_service.dart](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/model/log/app_log_service.dart#L74-L77)

**Finding:** In release mode, there is a comment `// Redact credentials before
persisting` but no actual redaction code at the `LogRecord` level. However, the
`AppLogStorage.save()` method (app_log_storage.dart:82-84) **does** apply
`redactLogText()` to message, error, and stackTrace at the write boundary, so
credentials are redacted before reaching the database. The in-memory LRU list
(`_logs`) stores the raw `LogRecord` without redaction.

**Impact:** The in-memory log buffer (1024 entries) may contain unredacted URLs
for the duration of the app session. These are not persisted to disk and are lost
on restart. If the app exposes an in-memory log viewer, credentials could
theoretically be visible there for the session.

**Remediation:** Apply `redactLogText` to the `LogRecord` before adding it to
`_logs`, or ensure the in-memory log viewer redacts on display.

---

### L-4 · No explicit crash-report SDK, but exception messages may carry PII (Low)

**Finding:** The codebase does not integrate Crashlytics, Sentry, or similar.
However, exception messages from `ServerException` and `ClientException` include
the request URL, which is correctly redacted via `redactUriForLogging(url)` at
construction time (http.dart:707, 722). The `reportSignInFailure` function logs
the raw error object, which could contain the original URL in its `toString()`,
but `redactLogText` at the storage boundary catches these.

**Remediation:** Satisfactory. If a crash-reporting SDK is added in the future,
ensure it passes through the same redaction pipeline.

---

### L-5 · No rate-limiting on local PGN import (Low)

**File:** [pgn_importer.dart](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/import/pgn_importer.dart#L185)

**Finding:** PGN input is size-limited to 10 MB (`kMaxPgnInputBytes`), which is
good. However, there is no limit on the *number* of games within that size or the
*depth* of variation trees. A crafted PGN under 10 MB could contain deeply nested
variations that cause excessive recursion in `_buildRoot`, potentially causing a
stack overflow.

**Impact:** App crash (DoS against the user). No data corruption.

**Remediation:**
- Add a recursion depth limit (e.g. 200 half-moves) to `_buildRoot`.
- Add a game count limit (e.g. 500 chapters per import).

---

## Positive Findings (Info)

### I-1 · SQL injection: Not present ✅

**All** SQL queries in `sqlite_study_repository.dart` and `database.dart` use
parameterized queries (`whereArgs`, `?` placeholders). The only string
interpolation in SQL is for **table names** (`$kTableSrsStudy`, etc.), which are
compile-time constants defined in `srs_schema.dart`. No user input is ever
interpolated into SQL.

The `IN (?)` placeholder lists are constructed with `List.filled(chunk.length, '?').join(',')`,
which is the correct pattern — the count comes from the list length, not from
user input.

---

### I-2 · Transaction boundaries are correct ✅

The critical write paths use transactions properly:

| Operation | Transaction? | File:Line |
|-----------|-------------|-----------|
| `saveImportResult` | Yes, full import in one `_db.transaction()` | sqlite_study_repository.dart:100 |
| `deleteStudy` | Yes, cascade delete in one transaction | sqlite_study_repository.dart:310 |
| `deleteChapter` | Yes, full cascade in one transaction | sqlite_study_repository.dart:532 |
| `savePositionKnowledgeState` | Yes, canonical + mirrors in one transaction | sqlite_study_repository.dart:906 |
| `saveAnswerBatch` | Yes, knowledge + mirrors + event in one transaction | sqlite_study_repository.dart:972 |

The import FIFO (`_importInFlight` Completer) correctly serializes concurrent
imports, preventing the duplicate-check TOCTOU race.

---

### I-3 · HTTPS enforcement is correct ✅

**File:** [http.dart](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/network/http.dart#L56-L64)

`lichessUri` uses `https` by default and falls back to `http` only for
`localhost`, `10.*`, and `192.168.*` hosts. `lichessWSUri` follows the same
pattern with `wss`/`ws`. This is the standard pattern for local development.

---

### I-4 · Downgrade safety is complete ✅

**File:** [database.dart](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/db/database.dart#L489-L543)

The old `onDatabaseDowngradeDelete` has been replaced with
`_onDatabaseDowngradeRefuseDowngrade`, which throws `DatabaseNewerVersionException`
instead of deleting the database. The `openAppDatabase` wrapper catches this and
writes a `VACUUM INTO` snapshot before rethrowing.

The implementation is correct:
- The archive runs **after** the refused open closes its connection (avoiding
  the in-transaction VACUUM INTO limitation).
- The staging-then-swap pattern prevents a failed archive from destroying the
  previous snapshot.
- The original database file is never modified or deleted.

Tests exist at `test/db/downgrade_archive_test.dart`.

---

### I-5 · WAL mode and foreign keys are enabled ✅

**File:** [database.dart](file:///home/mohamed/Desktop/Github/ChessSRS/lib/src/db/database.dart#L115-L131)

`onConfigure` enables WAL journal mode (for SQLite ≥ 3.7.0), `PRAGMA foreign_keys = ON`,
memory-mapped I/O, and a 64 MiB page cache. WAL mode allows concurrent readers
while a write is in progress, which is correct for a single-process mobile app.

---

## Concurrency Safety Assessment

| Area | Assessment |
|------|-----------|
| **Review answer persistence** | ✅ `saveAnswerBatch` uses a single transaction for knowledge state, review state mirrors, and review event (INV-001 compliant). |
| **Study import** | ✅ The `_importInFlight` Completer serializes imports. The duplicate-check-then-write runs atomically within the same critical section. |
| **Database access** | ✅ WAL mode. sqflite's `Database` instance serializes writes internally. The app is single-process. |
| **Auth state changes** | ✅ Generation counter (`_generation`) fences all auth state mutations, preventing stale responses from corrupting state. `SocketClient.onAuthChanged()` correctly clears queued messages on identity change. |

---

## Data Privacy Assessment

| Data | Storage | Protection |
|------|---------|-----------|
| OAuth token | `flutter_secure_storage` (Android Keystore / iOS Keychain) | ✅ Hardware-backed on modern devices |
| Email (sign-in only) | Not persisted. Sent via POST body (with query-string fallback). | ⚠️ See H-1 |
| Lichess username | Stored in `AuthUser` JSON in secure storage. Included in User-Agent. | ✅ Public info |
| PGN data | SQLite database in app-private storage | ✅ OS sandbox |
| Review history | SQLite database in app-private storage | ✅ OS sandbox |
| HTTP request log | SQLite, 7-day TTL, URLs redacted via `redactUriForLogging` | ✅ |
| App log | SQLite, 7-day TTL, messages/errors/stacks redacted via `redactLogText` | ✅ |

---

## Schema Migration Safety

The upgrade path from v1 to v23 uses `IF NOT EXISTS` guards, idempotent
top-up migrations, and post-batch data migrations. Each migration step is
gated on `oldVersion < N`, preventing re-application.

The v18 ghost-FK removal correctly rebuilds tables via `CREATE TABLE _new` →
`INSERT INTO _new SELECT * FROM old` → `DROP old` → `RENAME _new TO old`,
preserving all data.

**One concern:** The `onUpgrade` callback commits the DDL batch, then runs
data migrations (v14, v15, v16, v20, v21, v22, v23) outside any transaction.
If the app crashes between the schema commit and a data migration, the version
number is already at 23 but the data migration has not run. The `onOpen` top-up
(`backfillDecisionCanonicalStateIds`, `_ensureLateSrsColumns`) covers some of
these, but not all. This is a known SQLite pattern limitation, not a bug per se.

---

*End of audit. No critical findings. One high-severity finding related to
query-string credential exposure, which is documented and accepted in SPEC
INV-006.*
