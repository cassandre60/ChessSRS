# Findings register (issue-ready)

The repository has GitHub Issues disabled, so these were not filed as issues. Each entry below
is written to be pasted into an issue as-is once Issues are enabled. Title, label and body are
given for each. Fixed findings are tracked by their PR instead. See `review-program.md`.

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

## Review-4 C1: every persisted answer erases latency telemetry

**Suggested label:** `bug`

**Found by:** scheduler-stack review 4 (`docs/review-4-orchestration-persistence.md`), finding C1.
Assigned to whole-codebase-review Round 2, which did not take it; recorded here by Round 3 so the
finding is tracked somewhere. **Severity:** medium (latent — no producer writes the fields yet).

`ReviewService` converts `ReviewState` into `PositionKnowledgeState` in three hand-written copies
(`review_service.dart:287-296`, `:303-312`, `:358-367`), each copying the same eight fields.
`latencyEmaMs` and `latencySampleCount` are absent — and cannot be present, because `ReviewState`
has no such fields. The write then lands with `ConflictAlgorithm.replace`
(`sqlite_study_repository.dart:584`), i.e. `INSERT OR REPLACE`: delete the row, then insert, with
the latency columns reset to NULL/0. One answer that walks a 6-ply line resets latency on all
seven positions, none of which the user was asked about.

**Suggested change:** (1) add `PositionKnowledgeState.fromReviewState` as the inverse of the
existing `toReviewState()` and use it at all three sites, so the omission becomes impossible
rather than merely fixed; (2) change the knowledge-state write to an upsert touching only the
columns being written, or read-modify-write the latency fields. Add a test that stores latency,
answers, and reads it back intact.

## Review-4 C2: timestamps are local time with no offset

**Suggested label:** `bug`

**Found by:** scheduler-stack review 4, finding C2 (same defect as review-1 D4). Assigned to
whole-codebase-review Round 2, which did not take it; recorded here by Round 3. **Severity:**
medium — the only finding that corrupts scheduling for real users with no unusual behaviour
required: changing timezone shifts every stored due date, and one direction flips future items
to overdue, manufacturing a backlog.

`SystemClock.now()` is local (`clock.dart:19`); writes use `toIso8601String()` with no offset
(`sqlite_study_repository.dart:548`, `:574-576`, `json_adapters.dart`); reads use
`DateTime.parse`, which interprets offset-less strings in the reader's current zone. A card due
at 10:00 in Tunis stored as `2026-10-08T10:00:00.000` reads as 10:00 New York after a flight —
five hours later than earned.

**Suggested change:** its own migration PR (see review-4 §C2 for the full trace and the
reinterpret-existing-rows-as-UTC caveat): write `toUtc().toIso8601String()`, read with
`.toUtc()`, or move to epoch-millisecond columns. Test with a fixed clock across a simulated
zone change.

## Review-4 C3: sub-millisecond precision is truncated on the round-trip

**Suggested label:** `bug`

**Found by:** scheduler-stack review 4, finding C3. Recorded for completeness, not as a defect.
**Severity:** low — the smallest meaningful scheduler quantity is one minute; a microsecond is
nine orders below anything scheduling expresses. Disappears for free if the timestamp columns
ever become epoch-milliseconds as part of the C2 fix.
