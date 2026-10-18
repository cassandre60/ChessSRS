# TASK-04 — Table-driven merges (PGN importer, design tokens)

> **Pick this up in a fresh worktree.** `git worktree add ../chesssrs-table-merge -b refactor/table-merge origin/main` then `fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs`.

## Goal

Replace the most duplicate-heavy **example-test clusters** with **one table-driven file per cluster**, cutting ~400 lines with **no signal lost**.

## Why

`test/import/pgn_importer_test.dart` is **76 tests, 973 lines** of near-identical examples (one per PGN shape). `test/design/**` is **17 files** around the same harness (`folio_tokens`, `srs_accent`, `srs_dialog`, `srs_switch`, `theme_bridge`…). Both clusters raise cost and risk drift; each can be one `List<vector>` loop instead.

## Read before editing

- `docs/test-audit/inventory.csv` (look at `#tests` vs `runtime`/`behavior` for the two clusters).
- `docs/test-audit/audit-report.md` §Inventory buckets F + B and §Static smells — 17 design files share one harness; PGN has 76 near-duplicate cases.
- `.gates/mutants.json` — if TASK-02 expanded the corpus to cover import, use it as the oracle for "nothing lost".
- `GATES.md` G08 tripwire (test-weakening diffs) + `AGENTS.md` §10.5 (gates.sh t1 after committing).

## What to do (small commits — one cluster per commit)

### 4A — PGN importer table

1. Open `test/import/pgn_importer_test.dart` and group its 76 cases by shape: variation preservation (INV-010), malformed quarantine (INV-011), FEN roots (INV-012), round-trip (INV-014). Keep the grouping in comments.
2. Replace each group with a table:
   ```dart
   for (final v in importVectors) {
     test(v.name, () {
       final result = importPgn(v.pgn);
       expect(result.chapters.length, v.chapters);
       expect(result.chapters[0].treeJson, v.expectedTree);
     });
   }
   ```
   where `v` holds `name` + `pgn` + expected assertions. Keep the invariant comment (`// SPEC INV-0xx`) per vector so `spec_trace_check.py` still passes.
3. Add a single `lints` vector if needed to cover malformed depth (already covered by INV-011 vectors — just confirm).

### 4B — Design tokens → 2–3 files

1. Audit `test/design/**` (17 files) and split into **2 table-driven files**:
   - `tokens` (colors, typography, spacing) — e.g. `folio_tokens`, `srs_accent`, `srs_colors_contrast`, `theme_bridge`.
   - `components` (buttons, dialogs, switches, sheets) — e.g. `design_primitives`, `srs_dialog`, `srs_switch`, `srs_sheet_dismissible`, `srs_toast`, `top_bar_*`.
   Keep `board_squares` separate if it needs a board harness.
2. For each, build a `List<DesignCase>` and loop. Keep the visual assertion (`expect(find.text(...), findsOneWidget)` or theme check) — do not weaken the matcher.
3. Add a note in the file header that the table is the source of truth; adding a new token is adding a row.

## Not to do

- Do not delete any test that the table drops without **mutation + coverage proof** that nothing is lost (the brief's deletion rule). If the proof is not available yet, keep the old file as `pgn_importer_legacy_test.dart` for one PR and remove it only after TASK-02's new mutants kill green.
- Do not convert widget tests to pure `dart test` here (TASK-01 owns the lane).
- Do not widen tolerances, add `skip:`, or mock the subject under test (G08 tripwire will trip — and should).

## Done when

- [ ] `test/import/pgn_importer_test.dart` is one file with a `List` table (or one main table plus a few named vectors) and the same 76 cases still run.
- [ ] `test/design/**` is 2–3 table-driven files plus at most one board-specific file; the old 17 files are removed in a second commit with `Ack-G08: table-merge, same vectors, mutants green` if G08 would otherwise flag lost asserts.
- [ ] Targeted `fvm flutter test <touched file>` passes per file, `fvm flutter analyze` clean, and (if TASK-02 landed) `manual_mutation_runner.py` still kills the import/design-adjacent mutants.
- [ ] Commit body records the `rg -c` delta (decls before/after) and the `wc -l` delta.

## Evidence

- Per-file `fvm flutter test test/import/pgn_importer_test.dart --plain-name '<one vector>'` then full-file run.
- `python3 scripts/gates/spec_trace_check.py --spec SPEC.md --tests test --base-spec ...` if you moved INV citations.
- If TASK-02 expanded: `python3 scripts/gates/manual_mutation_runner.py --mutants .gates/mutants.json --test-cmd "fvm flutter test test/import/pgn_importer_test.dart --no-pub" --force`.

---
Source: `docs/test-audit/redesign.md` §4 + §5, `inventory.csv` PGN/design rows, `GATES.md` G08.
