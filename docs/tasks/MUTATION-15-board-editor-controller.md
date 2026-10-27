# MUTATION-15 — mutation audit of `board_editor_controller.dart`

**Date:** 2026-10-27
**Stream:** 1 (Mutation Testing & Test-Gap Elimination)
**Class:** test-only (no production code)
**Target:** `lib/src/model/board_editor/board_editor_controller.dart`
**Mapped test:** `test/model/board_editor/board_editor_controller_test.dart`
**Content hash under test:** `git hash-object` = `5f64770e1` (never audited before;
selected via `ledger.py next --stream A` after the work-gate skipped the
already-covered `pgn_offload.dart` offer).

## Engine settings used

```bash
python3 scripts/autonomous/mutation_engine.py \
  --source lib/src/model/board_editor/board_editor_controller.dart \
  --test-cmd "fvm flutter test test/model/board_editor/board_editor_controller_test.dart --concurrency=1" \
  --max-mutants 500 \
  --timeout 210 \
  --output-json /tmp/mut_board_editor.json \
  --output-issue docs/tasks/mutant_issue.md
```

## Totals

| Outcome | Count |
|---|---|
| Killed by the old suite | 5 |
| Survived | 44 |
| Uncompilable | 3 |
| Timed out | 0 |
| Kill rate before | 10.2% (5/49 killable) |

## Triage (this round)

9 survivors closed by 6 new tests (4 → 10 tests in the mapped file). Each
closed mutant has a per-mutant red run (mutant applied → the named test fails)
and the tree was restored and verified byte-identical after each, with the full
file green (10/10) on clean code. Format + analyze clean on both touched files;
`lib/` byte-identical throughout.

| Mutant (line) | Gap closed | Killing test |
|---|---|---|
| L119–122 `false → true` (×4) | `clearBoard` must clear every castling right, not leave any set | `clearBoard clears all castling rights and pieces` |
| L71 `== → !=` | `editSquare` places the piece on first click and removes it on a second click of the same piece | `editSquare places the piece on first click and removes it on a second` |
| L189 `== → !=` | `toggleEnPassantSquare` toggles between the square and null | `toggleEnPassantSquare toggles between the square and null` |
| L326 `== → !=` | `activePieceOnEdit` exposes the selected piece in edit mode | `activePieceOnEdit returns the selected piece in edit mode` |
| L329 `== → !=` / `&& → \|\|` / `== null → != null` | `deletePiecesActive` is true in edit mode with no piece selected, and false outside edit mode | `deletePiecesActive is true in edit mode with no piece selected` + `deletePiecesActive is false outside edit mode` |

## Open survivors (deferred to the next wake)

The remaining 35 survivors are recorded here so the next wake does not re-run
the engine. They fall into three families:

- **En-passant calculation** (L160–180, ~12 mutants): side inversion, off-by-one
  on rank offsets, `&& → ||` on the guard conditions, file-boundary inversion.
  Needs dedicated positions with pawns on the 5th/4th rank.
- **Castling possibility / rights part** (L276–317, ~15 mutants): `&& → ||`
  on the king/rook/side-can-castle conjunctions, `!= null → == null` on the
  chess960 candidate. Needs positions exercising each castling side and
  chess960 back-ranks.
- **Build / variant / move / mode / chess960 initial FEN** (L34, L62, L176–178,
  L189 already closed, L329 closed): L34 chess960 vs standard initial FEN
  (randomness makes it hard to pin deterministically); L62 `movePiece`
  origin==destination guard (likely equivalent — removing then re-adding the
  same square is a no-op); L176–178 side/pawn conjunctions inside the
  en-passant loop (folded into the en-passant family above).

## Mechanics worth recording

- `Piece` constants are `Piece.whiteQueen` etc. (static consts), not
  `Piece.white.queen`.
- `Square.e4` is a const field, so local `const square = Square.e4;` is valid
  and satisfies `prefer_const_declarations`.
- The engine's `clearBoard` castling mutants are four separate single-line
  mutations (L119–122); the single test (all values false) kills all four.

## Honest status

- Ran: one full-window engine pass (52 candidates, one targeted test file per
  mutant; source restored and `git diff --exit-code -- lib/` verified after
  every mutant and every hand re-application); 9 per-mutant hand
  re-applications for triage; full mapped file green on clean code (10/10).
- Not run: full suite and CI (belongs to CI per TEST_STRATEGY §2).
- Tests added: 6 (4 → 10 in `test/model/board_editor/board_editor_controller_test.dart`);
  no product code changed.
- Open: 35 survivors documented above for the next wake; ledger row to follow
  after this PR merges.
