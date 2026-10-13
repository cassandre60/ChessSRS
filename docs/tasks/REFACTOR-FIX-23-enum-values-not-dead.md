# REFACTOR-FIX-23 — Enum values that look dead and must not be deleted blindly

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. **This brief is an investigation. It is not permission to delete.**

## 1. What is broken

The same declaration-only sweep that produced REFACTOR-FIX-21 and -22 also
returned ~30 enum values with no source reference:

- `lib/src/model/engine/opponent_level.dart` — `level2`, `level5`, `level8`,
  `level9`, `level10`, `level11`, `level12`, `maia1200`, `maia1800`
- `lib/src/model/settings/general_preferences.dart` — `futuristic`, `piano`,
  `sfx`, `lisp`
- `lib/src/model/user/profile.dart` — `bluesky`, `vkontakte`, `chessCom`,
  `chessMonitor`, `chessTempo`
- `lib/src/model/game/game.dart`, `clock/chess_clock.dart` — several clock/move
  helpers

**These are not dead code, and deleting them is the most likely way to cause a
real data-loss bug in this codebase.** An enum value with no source reference can
still be:

1. **Persisted in the user's database.** `general_preferences.dart` is backed by
   shared-preferences storage. A sound theme saved as `sfx` must still parse after
   an upgrade, or every user who picked it falls back to a default — silently.
2. **Reachable only from data.** `opponent_level.dart` values look like engine
   levels; if any are written into a study or a preferences blob, they are read
   back by value with no source reference anywhere.
3. **Selected by index or ordinal.** A `values[index]` lookup or an
   `.index` round-trip makes a value live without naming it.

This is the same trap as DOMAIN-FIX-33 and REVIEW-FIX-02 in the pruned queue:
both proposed deleting something that turned out to be deliberate.

## 2. Investigate, and record what you find

For each group, answer one question: **can this value be written to, or read
from, anything that outlives the binary?**

```bash
# Where is the enum persisted?
rg -n 'GeneralPreferences|SoundTheme' lib/src/model/settings/general_preferences.dart | head -20

# Does anything round-trip by ordinal or index?
rg -n '\.index\b|\.values\[' lib/src/model/engine/opponent_level.dart lib/src/model/settings/general_preferences.dart

# Does the storage layer persist these as names?
rg -n 'toJson|fromJson' lib/src/model/settings/general_preferences.dart | head
```

Then write the answer down. **The deliverable is a finding, not a diff.**

## 3. What to do with the finding

- **A value is genuinely unreachable AND never persisted** → it may be removed,
  and you should say in the PR exactly which of the three reasons above ruled it
  safe. Say which one; that is the part worth reviewing.
- **A value is persisted or ordinal-addressed** → leave it, and record why in
  this file so the next agent does not re-derive it.
- **You cannot tell** → leave it and say so. "Inconclusive" is a valid, useful
  result here. A confident wrong deletion is not.

## 4. What counts as proof

Not tests — this is not a behaviour change. Proof is a citation: the line that
shows a value can be read back, or the line showing nothing can. Quote it.

**Already investigated?** If this file has a "Findings" section recording the
answer, the investigation is done. Only delete a value whose entry says it is
unreachable *and* never persisted, and only with the quoted evidence intact.

## 5. Why this brief exists

Every other brief in `docs/tasks/` asks for a deletion. This one asks for a
finding, because the highest-value outcome of a dead-code sweep is knowing which
of its candidates must survive. The queue README recommends stating a premise as
a runnable command; this is that idea applied to the dangerous half.