# MUTATION-04 — mutation audit of `openings_database.dart`

**Date:** 2026-10-23 (opened)
**Stream:** 1 (Mutation Testing & Test-Gap Elimination)
**Class:** test-only (no production code planned)
**Target:** `lib/src/db/openings_database.dart` (47 lines, content hash `9f745f2c3`)
**Mapped test:** `test/db/openings_database_test.dart` (29 lines)

## Premise

Top NEVER-audited candidate from `ledger.py next --stream 1` after the
app_links round (#406). No open PR or worktree branch touches these files
(`srs_toast`, the next candidate, is touched by seven in-flight branches and
was skipped for exactly that reason).

Pre-read finding: the mapped test never imports or exercises the source file —
it opens `assets/chess_openings.db` directly and checks an index. The
copy-from-asset flow in `_openDb` (directory creation, old-version cleanup,
asset copy, read-only open) has no oracle at all, so the engine's before-rate
is expected to be 0%. The round is therefore the #401/user.dart shape: write
the missing mapped coverage, measured honestly before and after.

Status: IN PROGRESS — stub; engine run, tests and triage follow.
