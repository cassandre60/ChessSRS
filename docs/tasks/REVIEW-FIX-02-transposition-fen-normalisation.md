# REVIEW-FIX-02 — WITHDRAWN — Transposition FEN normalisation (non-bug)

> **Status 2026-10-26: withdrawn after source-level verification. Do not implement.**
> A worktree agent audited the premise against the actual tree and proved both sides
> already normalise identically. The fix is a no-op and the prescribed test is vacuous.
> This file is kept as an audit trail — read §1 before doing anything.

## 1. Withdrawal notice (read first)

**Finding — worktree clean, finding filed 2026-10-26:**

> *REVIEW-FIX-02's premise doesn't match the code. Not applying the fix.*
>
> - `positionIdentity` (`lib/src/model/common/chess.dart:444`) is a **raw 4-field split** — no `Setup.parseFen`, no normalisation.
> - Import keys: `fenKey(position.play(san).fen)` (`pgn_importer.dart:596-605`).
> - Review keys: raw split of `Chess.fromSetup(Setup.parseFen(prompt.fen)).play(move).fen` (`review_session.dart:869-871`).
> - Both derive from **`Position.fen`**, and `dartchess 0.14.0`'s `Position.fen` getter (`lib/src/position.dart`) outputs `Setup(... epSquare: _legalEpSquare() ...).fen` — it **clears illegal ep squares** via `_legalEpSquare()`. So both sides are already normalised, **identically**.
> - Empirically: `import path play().fen → ... b KQkq - 0 1` and `review path parse+play .fen → ... b KQkq - 0 1` (identical). `Setup.parseFen(fen).fen` (the brief's proposed normalisation) **preserves** the illegal `e3` — it normalises nothing; the brief has it backwards.
> - The proposed test (hand-injected `e3` FEN strings) exercises inputs `play()` can never produce — a **vacuous test**. Shipping it would be gaming the gates, not fixing a bug.

**Verdict: correct. The brief is withdrawn.**

### What the brief got wrong

| Claim in the brief | Reality in the tree |
|---|---|
| `positionIdentity` delegates to `dartchess` normalisation | `positionIdentity` (`chess.dart:444-447`) is `fen.split(' ').take(4).join(' ')` — raw. |
| Import normalises via `Setup.parseFen(...).fen`, review does not | Both sides normalise via **`Position.fen`** (which calls `_legalEpSquare()`), not via `Setup`. Their raw 4-field splits are on **already-normalised** strings, so they agree. |
| `Setup.parseFen(fen).fen` as the fix | On dartchess master, `Setup.fen` does **not** filter ep — it round-trips the parsed `epSquare`. The agent confirmed `Setup.parseFen("… e3 ").fen` still emits `e3`, while `Chess.fromSetup(Setup.parseFen(...)).fen` would clear it. The brief picked the wrong layer. |
| `next.fen.split(' ').take(4)` vs `positionIdentity(next.fen)` diverges | They are the same function on the same input — both are raw splits on `Position.fen`. |

No code change is warranted for this item. A correct follow-up would be to audit transposition acceptance at a different layer (e.g. castling-rights canonicalisation across move orders), not to restate the withdrawn fix.

## 2. Original brief (retained for reference — do not execute)

The text below is the original task as drafted 2026-10-26, left intact so the audit trail reads.

---

## Original: 1. What was claimed to be broken

Two places compute a 4-field FEN key (placement, side, castling, en-passant) for
the same position, but they were claimed to differ:

* **Import** (`lib/src/import/pgn_importer.dart:175` and `lib/src/import/pgn_importer.dart`
  uses `positionIdentity` — claimed to delegate to `dartchess` `Setup.parseFen(...).fen`
  normalisation. Dartchess clears an illegal en-passant square to `-` and
  canonicalises castling order.

* **Review transposition** (`lib/src/domain/review/review_session.dart:848-871`,
  `_findTransposedNode`) does:

```dart
final parts = next.fen.split(' ');
if (parts.length < 4) return null;
final key = '${parts[0]} ${parts[1]} ${parts[2]} ${parts[3]}';
```

Claimed: raw `String.split(' ')` with no normalisation, so a position where `Setup` would
emit `... - ...` but the FEN string carries `... e3 ...` (illegal ep square) gets
key `'... e3'` here and `'... -'` in the decision's stored `fenKey`.

That claim is false — see §1.

## Original: 2. Files to read before touching anything

1. `lib/src/domain/review/review_session.dart:840-890` — `_findTransposedNode` and `_resolvePlayedMove`
2. `lib/src/import/pgn_importer.dart:170-185` — `positionIdentity` / `fenKey` derivation
3. `lib/src/domain/repertoire_node.dart` — how `RepertoireNode.fenKey` is populated
4. `lib/src/domain/domain.dart` — barrel, confirm whether `positionIdentity` or fen helpers are exported
5. `test/domain/review_session_test.dart` or `test/review/review_session_test.dart` — transposition tests
   (search `transpose`, `Transpos` across `test/`)
6. `ARCHITECTURE.md` §5 — position identity = normalised 4-field FEN (§5, §10)

## Original: 3. The fix (WITHDRAWN — do not implement)

(Former text described normalising the transposition FEN via `Setup.parseFen(fen).fen`
or a `fenKeyFromFen` helper. On the actual tree that helper preserves the illegal ep
and is therefore the wrong direction; `Position.fen` is already the normalised form.)

## Original: 4. How to make the work verifiable (WITHDRAWN)

The prescribed vacuous test (hand-injected `e3` strings) is not shipped. A real
transposition regression test belongs to a different invariant (actual side/castling
divergence after legitimate move orders), not to this withdrawn ep case.

## 5. Status after withdrawal

* This task is **done as "withdrawn with evidence"** — no PR is expected against it.
* Any future revisit must start from a new reproducer against the actual tree and
  the actual `dartchess` version pinned in `pubspec.yaml` (`0.14.0`), not from this
  file's §3 text.
* The orchestrator's queue for fresh agents currently points at **`REVIEW-FIX-01,
  REVIEW-FIX-03, REVIEW-FIX-04, POLISH-FIX-09, ARCH-FIX-05`** — not this file.
