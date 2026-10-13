# REFACTOR-FIX-21 — Hand-written `Pick` helpers with no callers

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

Nothing is *broken* — this is a cleanup. `deep_pick` generates `*.deep_pick.dart`
from `@DeepPick` annotations, but the conversion helpers themselves are
**hand-written** inside `extension IDPick on Pick` and its siblings. Several have
no caller anywhere in the tree.

These look used because they sit beside live siblings in the same extension. The
generated file is a red herring: the `OrNull`/`OrThrow` pair is handwritten and
will not reappear if you delete it.

## 2. Verify the list before touching anything

Every symbol below was declaration-only when this brief was written. **Re-run the
command; if a symbol now has a caller, drop it from your diff.**

```bash
for s in asStringIdOrNull asGameIdOrNull asGameFullIdOrNull asPuzzleIdOrNull \
         asUserIdOrNull asChallengeIdOrNull asBroadcastTournamentIdOrNull \
         asBroadcastRoundIdOrNull asBroadcastGameIdOrNull asFideIdOrNull \
         asTeamIdOrNull isGameId; do
  n=$(rg -c "\b$s\b" lib test scripts | wc -l)
  printf '%-32s %s\n' "$s" "$n"
done
```

**Already fixed?** Any line reporting more than one file has a live caller. If
*every* line does, this brief is done — delete it and say so in the PR. That is
a correct outcome, not a failure.

Files: `lib/src/model/common/id.dart`, `lib/src/model/common/chess.dart`
(`asSquareOrNull`), `lib/src/model/common/speed.dart` (`asSpeedOrNull`),
`lib/src/model/game/game_status.dart` (`asGameStatusOrNull`).

## 3. Constraints that make this safe, and how to keep it that way

- **Do not touch the `OrThrow` siblings.** They are the recovery path
  `OrNull` delegates to and may be called from generated code. Only remove the
  `OrNull` names listed above.
- **Do not remove the `@DeepPick` annotation or any `extension type`.** Those are
  load-bearing; the annotations drive codegen for the *generated* helpers.
- **Do not delete a symbol whose only other mention is in `test/`.** G08 treats a
  removed test declaration as weakening and needs a human `Ack-G08` signature —
  do not write one for yourself. If a symbol has a test caller, leave it and
  note it in the PR.

## 4. How to prove it

Two checks, both cheap, neither a full-suite run:

```bash
fvm flutter analyze lib/          # must be clean
fvm flutter analyze test/         # must be clean
```

`flutter analyze test/` is the load-bearing one: any surviving reference to a
removed symbol becomes a compile error there. Together the two cover every caller
that could exist. The full suite is CI's job.

Expect orphaned imports to surface in `analyze lib/` and remove only those the
analyzer names.

## 5. What this is worth

Low, and that is fine. `docs/tech-debt-inventory.md` §3 tracks these as
maintenance cost rather than runtime cost: they inflate the reachability ratchet
and mislead the next reader into thinking an id-parsing surface is in use.