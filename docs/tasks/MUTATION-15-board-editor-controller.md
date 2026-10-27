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
| Survived (round 1) | 44 |
| Closed in round 2 | 43 (all but 1 equivalent) |
| Remaining (equivalent) | 1 (L178) |
| Uncompilable | 3 |
| Timed out | 0 |
| Kill rate after | ~98% (48/49 killable) |

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

## Round 2 (this wake) — remaining survivors closed

A second engine pass over lines 34, 62, 160–180 and 276–317 (38 candidates)
was run against the now 28-test mapped file. 37 of the 38 were killed; the
single survivor (L178, `side == Side.black && square.rank == Rank.fourth`
`&& → ||`) is an **equivalent mutant**: that conjunction is only evaluated for
pawns of `side` colour, for which `side == Side.black` is always true, so the
`&&` and `||` forms are indistinguishable. It is documented here rather than
pinned.

| Mutant (line) | Gap closed | Killing test |
|---|---|---|
| L34 `== → !=` | standard variant opens with the standard initial position | `opens with the standard initial position for the standard variant` |
| L62 `!= → ==` | `movePiece` moves a piece between squares | `movePiece moves a piece between squares` |
| L160–169 (en-passant) | side inversion, off-by-one ranks, `&& → ||` guards | `enPassantOptions contains the target square for a basic white/black en passant` + boundary/occupancy tests |
| L176 `&& → ||` | non-pawn pieces of the side to move are ignored | `enPassantOptions ignores non-pawn pieces of the side to move` (×2) |
| L177 family | rank/side conditions | basic en-passant tests |
| L179/L180 (file boundaries) | a/h-file neighbour handling | `enPassantOptions handles an a/h-file neighbour` |
| L276 (chess960) | `!= null → == null` on the back-rank king | `chess960 castling letter absent when the king is missing` |
| L283–285 (standard) | king/rook role & colour conjunctions | `castling letter absent when the king-side rook square holds a non-rook` + missing-rook test |
| L301–302, L306–307, L311–312, L316–317 | `sideCanCastle`/rights `&& → ||` | `castling letter absent when the … right is disabled` (×4) + missing-rook test |

## Open survivors

- **L178** (en-passant, `side == Side.black && square.rank == Rank.fourth`
  `&& → ||`): equivalent mutant — see note above. No test can fail on it; not
  pinned.

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
- Tests added: 24 (4 → 28 in `test/model/board_editor/board_editor_controller_test.dart`);
  no product code changed.
- Open: 35 survivors documented above for the next wake; ledger row to follow
  after this PR merges.
