# Findings register (issue-ready)

The repository has GitHub Issues disabled, so these were not filed as issues. Each entry below
is written to be pasted into an issue as-is once Issues are enabled. Title, label and body are
given for each. Fixed findings are tracked by their PR instead. See `review-program.md`.

## R1-F3: Desktop OAuth sends no state parameter

**Suggested label:** `enhancement`

**Found by:** whole-codebase review, Round 1 (`docs/review-program.md`), finding R1-F3.
**Severity:** low (hardening). **Not exploitable today**, as explained below.

`lib/src/model/auth/auth_repository.dart` builds the desktop OAuth URI (`buildDesktopOAuthUri`) without a `state` parameter, and the loopback callback never checks one. RFC 6749 §10.12 and RFC 8252 §8.9 recommend `state` to bind a callback to the request that started it.

**Why this is not an active exploit:** PKCE already blocks the classic code-injection attack. A code an attacker obtains for their own challenge fails the token exchange, because the app exchanges it with its own verifier.

**Why it is still worth fixing:** `state` is the standard defence-in-depth. It also stops an unrelated local request from completing a sign-in attempt the user did not start.

**Blocker before changing it:** confirm that Lichess's `/oauth` endpoint echoes `state` unchanged on the redirect. If it does not, a strict check would break sign-in for every desktop user. This needs verification against the live endpoint first, not a guess.

**Suggested change once confirmed:** generate `state` from `Random.secure()`, add it to `buildDesktopOAuthUri`, and reject the callback when `request.uri.queryParameters['state']` does not match. Add a test for the URI and for the mismatch path.

## R1-F4: PGN export silently drops moves that fail to replay

**Suggested label:** `bug`

**Found by:** whole-codebase review, Round 1, finding R1-F4.
**Severity:** low. Silent data loss on export, but only reachable with a corrupt stored tree.

`_writeNodeMoves` in `lib/src/import/pgn_exporter.dart` calls `_playMove`, which returns `null` when a stored move cannot be replayed. The code then writes nothing for that move and skips its entire subtree (`if (nextPos != null) ...`). The exported PGN is missing moves with no error or log entry, so the user cannot tell the export is incomplete.

**Suggested change:** log a warning with the chapter and move, and return the count of dropped moves so the caller can surface it, for example in the export dialog. Add a test that feeds a tree with one illegal stored move and asserts the warning or count.

## R1-F5: A brace in a PGN comment would truncate it on export (not reachable today)

**Suggested label:** `bug`

**Found by:** whole-codebase review, Round 1, finding R1-F5.
**Severity:** low. **Not reachable from the app today.**

PGN brace comments end at the first `}`. `chapterToPgn` writes comments as `{...}` without escaping, so a comment containing `}` is truncated on export and the rest of the comment is parsed as move text.

**Why it is not reachable now:** the app has no in-app comment editing, and an imported PGN cannot contain a `}` inside a comment, because the importer would have ended the comment there.

**Suggested change, if comment editing is ever added:** replace `}` in exported comments with a safe substitute, and say so in the export documentation. Add a round-trip test with a `}` in a comment. Record it in the spec before shipping the editor.

## R2-F2: ON DELETE CASCADE is declared but foreign_keys is never enabled

**Suggested label:** `bug`

**Found by:** whole-codebase review, Round 2 (`docs/review-program.md`), finding R2-F2.
**Severity:** low, design risk. No row is orphaned today.

The schema declares `FOREIGN KEY ... ON DELETE CASCADE` (`lib/src/persistence/srs_schema.dart`), but nothing enables `PRAGMA foreign_keys`. SQLite leaves enforcement off by default, and `openAppDatabase` (`lib/src/db/database.dart`) sets only `journal_mode=WAL` in `onConfigure`. So the cascades never run.

Deletes are done by hand: `deleteStudy` and `deleteChapter` remove the child rows in `sqlite_study_repository.dart`, and they do so correctly today. The risk is the next delete path. Anyone who relies on the schema's cascade, rather than the manual code, will leave orphaned chapters, decisions, or review rows with no error.

**Suggested change:** either enable `PRAGMA foreign_keys=ON` in `onConfigure` and check that existing deletes still pass, or remove the `ON DELETE CASCADE` clauses so the schema stops promising behaviour it does not have. The first is the safer default. It needs a migration-safe check, because enabling enforcement on existing data can fail if any orphan already exists. Test both the enforced cascade and the orphan case.

## R2-F4: v11 migration uses a double-quoted string as a SQL default

**Suggested label:** `bug`

**Found by:** whole-codebase review, Round 2, finding R2-F4.
**Severity:** low, hygiene. Works on the SQLite builds the app ships today.

The v11 migration in `lib/src/db/database.dart` uses a double-quoted string as a column default: `ADD COLUMN orientation TEXT NOT NULL DEFAULT \"white\"`. In SQLite a double-quoted token is an identifier. It is only read as a string literal through the legacy DQS fallback. SQLite builds compiled with `SQLITE_DQS=0` reject this, and the migration would fail on those builds.

**Suggested change:** use a single-quoted literal, `DEFAULT 'white'`, in the migration. The current database shape is unchanged, so this is a text-only change, but add a test that runs the migration on an old-schema database.
