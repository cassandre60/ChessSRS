# REFACTOR-FIX-22 — Dead predicates and providers in `lib/src/model/`

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

Nothing is *broken* — this is a cleanup. A tree-wide sweep for declarations with
exactly one occurrence in `lib/` + `test/` + `scripts/` found these. Each is
hand-written, none is an `@override`, none is referenced.

They survived earlier dead-code passes because each sits in a different file, so
no single pass caught them all.

## 2. Verify the list before touching anything

```bash
for s in hasEval hasColorAdjustments hasDropMoves isCustom matrixPresets \
         isPlaySupported setPremove amIOwner isServerAnalysisAllowed \
         currentServerAnalysis linesForPendingMove crosstableProvider \
         selectionLabel gamePreferencesProvider; do
  n=$(rg -l "\b$s\b" lib test scripts | wc -l)
  printf '%-28s %s\n' "$s" "$n"
done
```

A `1` means declaration-only and safe to remove. Anything higher has a live
caller — drop it. **If every line is higher than 1, this brief is done; delete it
and say so.** That is a correct outcome.

Check for `@override` before removing each one:

```bash
rg -B2 '\bhasEval\b' lib | rg -c '@override'
```

The count must be `0`. An `@override` member is implementing something the
compiler enforces, and removing it breaks the build — the analyzer will say so,
but check first because the intent matters.

## 3. Files and one caveat

| Symbol | File |
|---|---|
| `hasEval` | `lib/src/model/common/eval.dart` |
| `hasColorAdjustments` | `lib/src/model/settings/board_preferences.dart` |
| `hasDropMoves`, `isPlaySupported` | `lib/src/model/common/chess.dart` |
| `isCustom`, `matrixPresets` | `lib/src/model/common/time_increment.dart` |
| `setPremove` | `lib/src/model/account/account_preferences.dart` |
| `amIOwner`, `isServerAnalysisAllowed` | `lib/src/model/study/study_controller.dart` |
| `currentServerAnalysis` | `lib/src/model/analysis/server_analysis_mixin.dart` |
| `linesForPendingMove` | `lib/src/model/analysis/analysis_controller.dart` |
| `crosstableProvider` | `lib/src/model/user/user_repository_providers.dart` |
| `selectionLabel` | `lib/src/model/game/game_filter.dart` |
| `gamePreferencesProvider` | `lib/src/model/game/game_preferences.dart` |

**Caveat on the last one.** `lib/src/model/game/game_preferences.dart` is pinned
as `_knownUnreachable` in `test/reachability/reachability_test.dart`. Removing a
symbol from an unreachable file does **not** move the reachability ratchet, and
deleting the file itself is a separate product decision tracked as tech-debt #20.
Remove the symbol or skip it — do not delete the file.

## 4. How to prove it

```bash
fvm flutter analyze lib/
fvm flutter analyze test/
```

Both clean. `analyze test/` is the one that matters: any surviving reference
becomes a compile error. Remove only the imports the analyzer names as unused.

## 5. What this is worth

Low. These mislead maintainers into thinking a surface is live — `crosstableProvider`
and `gamePreferencesProvider` are the sharpest examples, since a provider with no
reader looks like a feature someone is about to wire up.