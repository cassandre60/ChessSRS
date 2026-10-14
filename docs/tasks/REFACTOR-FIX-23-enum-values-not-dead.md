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

## 6. Findings (Investigated 2026-10-14)

None of the audited enum values are dead. Every single group is live via
persistence, dynamic byName/nameMap lookups, file asset mapping, or ordinal
slider lookups. **Do not delete any of them.**

### Group 1: `SoundTheme` (`lib/src/model/settings/general_preferences.dart`)
- **Values:** `futuristic`, `piano`, `sfx`, `lisp` (alongside `standard`, `nes`).
- **Status:** **LIVE**. User-selectable settings with corresponding disk assets.
- **Evidence:**
  1. UI iteration: `lib/src/view/settings/sound_settings_screen.dart:73-75`:
     ```dart
     for (final theme in SoundTheme.values) theme.name: soundThemeL10n(context, theme),
     onChanged: (name) => onChanged(SoundTheme.values.byName(name)),
     ```
     The settings picker populates choices dynamically by mapping over `SoundTheme.values` and looks up selections via `.byName(name)`.
  2. Asset files: `assets/sounds/` contains directories for every theme:
     `futuristic/`, `piano/`, `sfx/`, `lisp/`, `nes/`, `standard/`.
     `SoundService.load` (`lib/src/model/common/service/sound_service.dart:76`) loads audio files dynamically via path string: `assets/sounds/${theme.name}`.
  3. Persistence: `GeneralPrefs.soundTheme` is persisted to `SharedPreferences` as JSON (`@Default(SoundTheme.standard) SoundTheme soundTheme`). Deleting an enum value causes deserialization failure for users with that theme saved.

### Group 2: `StockfishLevel` & `MaiaRating` (`lib/src/model/engine/opponent_level.dart`)
- **Values:** `level2`, `level5`, `level8`, `level9`, `level10`, `level11`, `level12`, `maia1200`, `maia1800` (and all intermediate levels).
- **Status:** **LIVE**. Ordinal slider addressing and JSON persistence.
- **Evidence:**
  1. Slider addressing: `lib/src/view/offline_computer/opponent_picker.dart:263-264`:
     ```dart
     values: StockfishLevel.values.map((l) => l.level).toList(),
     onChange: (value) => onChanged(StockfishLevel.values[value.toInt() - 1]),
     ```
     Users choose levels on a 1-12 slider that indexes directly into `StockfishLevel.values[level - 1]`.
  2. Maia slider addressing: `lib/src/view/offline_computer/opponent_picker.dart:323-328`:
     ```dart
     values: MaiaRating.values.map((r) => r.rating).toList(),
     widget.onChanged(MaiaRating.fromRating(value.toInt())!);
     ```
     `fromRating` queries `values.where((r) => r.rating == rating).firstOrNull`.
  3. Serialization: `StockfishOpponentSpec.toJson` and `MaiaOpponentSpec.toJson` write `{'level': level.name}` and `{'rating': rating.name}`. Deserialization in `OpponentSpec.fromJson` reads them back via `values.asNameMap()[json['level']]` and `values.asNameMap()[json['rating']]`.

### Group 3: `LinkSite` (`lib/src/model/user/profile.dart`)
- **Values:** `bluesky`, `vkontakte`, `chessCom`, `chessMonitor`, `chessTempo`.
- **Status:** **LIVE**. API data parsing via domain matching.
- **Evidence:**
  1. Dynamic lookup: `lib/src/model/user/profile.dart:79`:
     ```dart
     final site = LinkSite.values.firstWhereOrNull((e) => e.domains.contains(host));
     ```
     Lichess user profile social links from `/api/user/{username}` are parsed by matching URI hostnames against `LinkSite.values` domains (e.g. `bsky.app`, `vk.com`, `chess.com`).
     Deleting any value breaks social link categorization for users with those profile links.

### Group 4: `GameSource` & `GameRule` (`lib/src/model/game/game.dart`)
- **Values:** `pool`, `relay`, `unknown`, `noAbort`, `noClaimWin`.
- **Status:** **LIVE**. API payload string parsing.
- **Evidence:**
  1. Dynamic name lookup: `lib/src/model/game/game.dart:326, 338`:
     ```dart
     static final nameMap = IMap(GameSource.values.asNameMap());
     static final nameMap = IMap(GameRule.values.asNameMap());
     ```
     Game data from Lichess JSON responses is parsed via `nameMap[string]`.

### Conclusion
Zero enum values are safe to delete. All audited candidates are actively utilized through reflection-equivalent patterns (`.values.byName`, `.values[index]`, `.values.asNameMap()`, or `.values.firstWhereOrNull`).
