# REVIEW-FIX-02 — Transposition miss: FEN normalisation differs between import and review

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

Two places compute a 4-field FEN key (placement, side, castling, en-passant) for
the same position, but they do it differently:

* **Import** (`lib/src/import/pgn_importer.dart:175` and `lib/src/import/pgn_importer.dart`
  uses `positionIdentity` — which delegates to `dartchess` `Setup.parseFen(...).fen`
  normalisation. Dartchess clears an illegal en-passant square to `-` and
  canonicalises castling order.

* **Review transposition** (`lib/src/domain/review/review_session.dart:848-871`,
  `_findTransposedNode`) does:

```dart
final parts = next.fen.split(' ');
if (parts.length < 4) return null;
final key = '${parts[0]} ${parts[1]} ${parts[2]} ${parts[3]}';
```

Raw `String.split(' ')` with no normalisation. So a position where `Setup` would
emit `... - ...` but the FEN string carries `... e3 ...` (illegal ep square) gets
key `'... e3'` here and `'... -'` in the decision's stored `fenKey`. The lookup
`_nodesByFenKey[key]` then returns nothing, and a legal transposition is graded
`incorrect` (INV-065 violated).

**User-visible symptom**: playing a correct transposing move (e.g. `1. Nf3 d5 2. d4`
reaching the same position as `1. d4 d5 2. Nf3`) is marked wrong when the
intermediate FEN carries a non-normalised ep/castling field. Sporadic and hard to
reproduce, because it depends on whether the preceding move left an illegal ep
target in the stored FEN.

## 2. Files to read before touching anything

1. `lib/src/domain/review/review_session.dart:840-890` — `_findTransposedNode` and `_resolvePlayedMove`
2. `lib/src/import/pgn_importer.dart:170-185` — `positionIdentity` / `fenKey` derivation
3. `lib/src/domain/repertoire_node.dart` — how `RepertoireNode.fenKey` is populated
4. `lib/src/domain/domain.dart` — barrel, confirm whether `positionIdentity` or fen helpers are exported
5. `test/domain/review_session_test.dart` or `test/review/review_session_test.dart` — transposition tests
   (search `transpose`, `Transpos` across `test/`)
6. `ARCHITECTURE.md` §5 — position identity = normalised 4-field FEN (§5, §10)

## 3. The fix

Normalise the transposition FEN the same way import does. Prefer reusing a single
helper so the two sites cannot drift again.

### Option A — reuse existing helper (preferred if it is reachable)

If `positionIdentity` or an equivalent `fenKeyOf(String fen) -> String` / `fenKeyOf(Position)` is
importable from `domain/` or `import/` without pulling Flutter/sqflite into domain:

```dart
// lib/src/domain/review/review_session.dart  — inside _findTransposedNode, replace raw split:

// BEFORE
final parts = next.fen.split(' ');
if (parts.length < 4) return null;
final key = '${parts[0]} ${parts[1]} ${parts[2]} ${parts[3]}';

// AFTER — normalise via dartchess (same invariant as import)
final key = _fenKey(next.fen); // or positionIdentity(next), or fenKeyFromPosition(next)
```

If the helper is not reachable without a layer violation, add a tiny pure-Dart
helper in `lib/src/domain/` (e.g. `lib/src/domain/fen_key.dart`) that does only:

```dart
import 'package:dartchess/dartchess.dart';

String fenKeyFromFen(String fen) {
  try {
    return Setup.parseFen(fen).fen.split(' ').take(4).join(' ');
    // or: return Chess.fromSetup(Setup.parseFen(fen)).fen  — check what import uses;
    // match it exactly. Some paths use Chess.fromSetup(...).fen, some use Setup.parseFen(...).fen
  } catch (_) {
    return fen.split(' ').take(4).join(' '); // fail-closed: same shape as before
  }
}
```

Then `_findTransposedNode` calls `fenKeyFromFen(next.fen)`.

### Also fix the import-side drift if you find one

Some branches compute `fenKey` as `Setup.parseFen(...).fen`, others as `pos.fen`.
Both normalise, but they normalise different things (one canonicalises the setup,
the other round-trips through `Chess`). Pick the one `positionIdentity` uses and
make `_findTransposedNode` match it. One helper, two call sites, zero divergence
— that is the point. See `docs/tech-debt-inventory.md` item 6 / ARCHITECTURE §5.

### What NOT to change

* Do not change the `_nodesByFenKey` indexing in `ReviewSession` constructor
  (`_indexNodes`) — it already stores `node.fenKey`, which is populated by the
  importer using the normalised form.
* Do not add Flutter, sqflite, or `logging` to the helper; it must stay pure Dart
  (`ARCHITECTURE.md` §2 invariant 1, `scripts/gates/banned_apis_check.py`).

## 4. How to make the work verifiable (no guessing)

### 4.1 Worktree setup — required

```bash
git worktree add ../chesssrs-review-fix-02 -b fix/review-fix-02-transposition-fen origin/main
cd ../chesssrs-review-fix-02
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze   # 0 issues before you start
```

### 4.2 Failing test first — RED

Add a test that fails on the current code and passes after the fix.

**Scenario** — craft two lines reaching the same position where one path leaves a
non-normalised ep square in its FEN:

* Use `dartchess` directly to build positions, or reuse the PGN fixtures already
  in `test/` that contain transpositions.
* Easier deterministic repro: mock a `ReviewSession` with a stored `fenKey` of
  `'<placement> w KQkq - 0 1'` and a `next.fen` of `'<placement> w KQkq e3 0 1'`
  (illegal ep). Call `_findTransposedNode` (or `submitMove` end-to-end) with a
  move that reaches that position. Before the fix the lookup misses; after it
  hits. The PGN `1. e4 e5 2. Nf3` vs `1. Nf3 e5 2. e4` style transposition is a
  more realistic end-to-end variant — pick whichever is easiest with the existing
  test helpers.

Place the test alongside existing transposition tests (search `INV-065`):

```dart
// SPEC INV-065: transposition acceptance within scope.
// A move reaching a position that exists in scope must be graded correct
// even when the raw FEN's ep field differs but dartchess normalises it away.
```

Run targeted:

```bash
fvm flutter test test/review/review_session_test.dart --plain-name 'transposition normalises ep'
# or the file you used
```

Must fail before edit, pass after.

### 4.3 Implement the fix — GREEN

Edit `lib/src/domain/review/review_session.dart` (and if needed add
`lib/src/domain/fen_key.dart` and export it from `lib/src/domain/domain.dart`).

If you add a file, ensure it is pure Dart (no Flutter).

### 4.4 Verify

```bash
fvm flutter test test/review/review_session_test.dart --plain-name 'transposition normalises ep'
fvm flutter test test/review/review_session_test.dart   # whole file, once
git stash && fvm flutter test test/review/review_session_test.dart --plain-name 'transposition normalises ep'
# must fail on the stashed (old) code
git stash pop
fvm flutter analyze
git add lib/src/domain/review/review_session.dart lib/src/domain/fen_key.dart test/review/review_session_test.dart
git commit -m "fix(review): normalise transposition FEN the same way import does"
./scripts/gates.sh t1
```

### 4.5 Push & PR

```bash
git push -u origin fix/review-fix-02-transposition-fen
gh pr create -R cassandre60/ChessSRS --title "fix(review): normalise transposition FEN the same way import does" --body "Closes REVIEW-FIX-02. See docs/tasks/REVIEW-FIX-02-transposition-fen-normalisation.md."
```

## 5. Constraints

* Do not edit `SPEC.md`, `GATES.md`, `QUALITY.md`, `TEST_STRATEGY.md`, `AGENTS.md`,
  `pubspec.yaml`, `analysis_options.yaml`, `.gates/`, `scripts/gates/`, `.github/`.
* Pure domain layer stays pure — no `package:flutter`, `chessground`, `sqflite` in
  `lib/src/domain/` (`G03` banned APIs gate enforces this).
* One fix per PR. No drive-by refactors.
* Targeted tests only locally; full suite is CI's job (`AGENTS.md` §3.1).
* No local release builds.

## 6. Done when

* [ ] Failing test added, fails on old code, passes on new
* [ ] `fvm flutter analyze` 0 issues on touched files
* [ ] `./scripts/gates.sh t1` green on the committed branch
* [ ] PR open against `cassandre60/ChessSRS`
