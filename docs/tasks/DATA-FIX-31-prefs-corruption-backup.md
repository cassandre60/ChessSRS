# DATA-FIX-31 — Corrupted preferences silently reset to defaults with no backup or diagnosis path

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

`lib/src/model/settings/preferences_storage.dart` — both `fetch` paths
(`PreferencesStorage.fetch` ~line 64-69, `SessionPreferencesStorage.fetch`
~line 100-105) do this on deserialization failure:

```dart
catch (e) {
  _logger.warning('Failed to load prefs', e);
  return defaults;  // every user customization silently gone
}
```

Two compounding problems:

1. **No backup.** The unparseable blob is overwritten on the next `save`,
   destroying the evidence. If the corruption was a partial write (crash
   mid-save), the user's actual preferences are unrecoverable *and* invisible.
2. **Warning-level log.** Losing all user settings is not a warning; it is a
   SEVERE event that should be greppable in the in-app log viewer.

Trigger class: Freezed `fromJson` throws when an enum value is renamed between
app versions, a required field is added, or SharedPreferences' underlying file
is truncated by a crash. App updates hit this repeatedly over time.

## 2. Files to read before touching anything

1. `lib/src/model/settings/preferences_storage.dart` — both `fetch` paths and `save`
2. `lib/src/model/log/` — Logger usage in the model layer
3. `lib/src/model/settings/board_preferences.dart` — one concrete consumer (how
   `fetch` is called, what `defaults` are)
4. `test/model/settings/` — existing preferences tests (if any)

## 3. The fix

### 3.1 Preserve the corrupted blob

On deserialization failure, write the raw string to a **separate** backup key
before returning defaults:

```dart
catch (e, st) {
  final raw = sharedPreferences.getString(key);
  if (raw != null) {
    await sharedPreferences.setString('$key.corrupt-backup', raw);
  }
  _logger.severe(
    'Preferences "$key" failed to parse (${e.runtimeType}); '
    'backed up to "$key.corrupt-backup" and reset to defaults',
    e, st,
  );
  return defaults;
}
```

The backup key is never read by the app — it exists so a support session can
recover it via the log viewer's export or `adb`/file access. It is overwritten
only if corruption recurs, which is correct (the newest corruption is the
relevant one).

### 3.2 Do not change anything else

* `save` behavior unchanged.
* Defaults fallback unchanged — the app must still boot on corrupted prefs.
* No user-facing dialog: the app cannot know whether the user cares; the log
  entry + backup is the support path. (A "settings were reset" snackbar needs
  product sign-off — out of scope.)
* Apply the identical change to both storage classes in the file.
* Do not touch `SPEC.md`, `GATES.md`, `.gates/`, `pubspec.yaml`.

## 4. Verification

```bash
git worktree add ../chesssrs-data-fix-31 -b fix/data-fix-31-prefs-corruption-backup origin/main
cd ../chesssrs-data-fix-31
fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs
```

**RED test** — add to the preferences storage test file (create
`test/model/settings/preferences_storage_test.dart` if none exists; mirror
existing test setup):

```dart
test('corrupted prefs blob is backed up before defaults are returned', () async {
  SharedPreferences.setMockInitialValues({'boardPrefs': '{not valid json'});
  final prefs = await SharedPreferences.getInstance();
  final storage = /* construct the storage under test with prefs */;
  final result = await storage.fetch();
  expect(result, equals(defaults));              // fallback still works
  expect(prefs.getString('boardPrefs.corrupt-backup'), '{not valid json}');
});
```

Run — must fail on current code (no backup key written). Implement — must pass.

```bash
fvm flutter test test/model/settings/preferences_storage_test.dart --plain-name 'corrupted prefs'
fvm flutter test test/model/settings/
fvm flutter analyze

git add lib/src/model/settings/preferences_storage.dart test/model/settings/
git commit -m "fix(settings): back up corrupted prefs blob and log SEVERE before resetting to defaults"
./scripts/gates.sh t1
git push -u origin fix/data-fix-31-prefs-corruption-backup
gh pr create -R cassandre60/ChessSRS --title "fix(settings): back up corrupted prefs before reset" --body "Closes DATA-FIX-31."
```

## 5. Done when

* [ ] Both storage classes write `$key.corrupt-backup` on parse failure
* [ ] Log level is `severe` with error + stack trace
* [ ] New test proves backup-then-defaults behavior; verified RED on old code
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green
* [ ] PR open against `cassandre60/ChessSRS`
