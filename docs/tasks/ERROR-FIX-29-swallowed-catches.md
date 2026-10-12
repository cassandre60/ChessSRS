# ERROR-FIX-29 — Silent swallowed catches lose user settings and hide import root causes

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

Three swallowed-error sites either lose user data silently or make debugging
impossible:

### 1a. `account_preferences.dart:66,141` — corrupted prefs silently reset to defaults

```dart
// line ~141 (local deserialization failure)
catch (e) {
  debugPrint('Failed to parse account preferences: $e');
  return AccountPrefs.defaults;  // user loses ALL customizations, no warning
}
```

If the preferences JSON is corrupted (partial write from crash), the user's
settings revert to defaults with only a `debugPrint`. Brief 24 routes
`debugPrint` → `Logger` for view files; this is a model file and needs the same
upgrade plus a user-facing signal is out of scope — but at minimum the error
must include the raw JSON snippet and reach the Logger pipeline so it appears
in the in-app log viewer.

### 1b. `pgn_importer.dart:562` — parse errors logged without stack trace

```dart
// In _buildChildren, per-move parse failure:
catch (e) {
  errors.add(ImportError(...));  // no stack trace captured
}
```

When a user's PGN has a malformed move, the error list says "couldn't parse
move X" but the stack trace (`st`) is dropped. Root-cause diagnosis ("which
dartchess code path rejected this SAN?") is impossible from logs.

### 1c. `share.dart:40` — share failure silently becomes clipboard copy

```dart
catch (e) {
  debugPrint('Share failed: $e');
  await Clipboard.setData(...);  // user thinks "Share" worked; it silently
                                 // did something different
}
```

If the share service is broken (permissions, no share target), the user taps
"Share" and gets "Copied to clipboard" with no indication that sharing failed.
This is a silent behavior change, not an error.

## 2. Files to read before touching anything

1. `lib/src/model/account/account_preferences.dart:50-80, 130-150` — both catches
2. `lib/src/import/pgn_importer.dart:550-580` — `_buildChildren` catch site
3. `lib/src/utils/share.dart:25-55` — the share fallback
4. `lib/src/model/log/` — `Logger` pattern used in model layer
5. `lib/src/widgets/feedback.dart` — `showSnackBar` helper

## 3. The fix

### 3a. account_preferences.dart

Replace `debugPrint` with `Logger` and include the error + stack:

```dart
// Top of file:
final _logger = Logger('AccountPreferences');

// At line ~66 (remote fetch failure):
catch (e, st) {
  _logger.warning('Failed to fetch remote account preferences', e, st);
  // fall back to local/defaults — behavior unchanged
}

// At line ~141 (local deserialization failure):
catch (e, st) {
  _logger.severe(
    'Account preferences corrupted, resetting to defaults', e, st);
  return AccountPrefs.defaults;
}
```

### 3b. pgn_importer.dart

Capture the stack trace:

```dart
catch (e, st) {
  errors.add(ImportError(
    move: san,
    message: e.toString(),
    stackTrace: st.toString(),  // if ImportError has a stackTrace field;
                                // otherwise append to message
  ));
}
```

Read `ImportError`'s definition first — if it has no `stackTrace` field, append
`st` to the message string. Do not add fields to `ImportError` if it's a
public API type used elsewhere.

### 3c. share.dart

Tell the user the share failed:

```dart
catch (e, st) {
  _logger.warning('Share failed, falling back to clipboard', e, st);
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    showSnackBar(
      context,
      'Share unavailable — copied to clipboard instead',
      type: SnackBarType.warning,
    );
  }
}
```

The snackbar text changes from silently claiming success to stating the
fallback. Check whether a snackbar already fires on this path; if it does,
change only its text, don't add a second one.

### What NOT to change

* Do not change the fallback behaviors themselves (defaults, clipboard copy) —
  only the logging/visibility.
* Do not add user-facing dialogs or blockers.
* Do not touch `SPEC.md`, `GATES.md`, `.gates/`, `pubspec.yaml`.

## 4. Verification

```bash
git worktree add ../chesssrs-error-fix-29 -b fix/error-fix-29-swallowed-catches origin/main
cd ../chesssrs-error-fix-29
fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs

# After: these greps must show Logger usage, no bare debugPrint at the 3 sites
rg -n "debugPrint" lib/src/model/account/account_preferences.dart lib/src/import/pgn_importer.dart lib/src/utils/share.dart
# 0 hits

fvm flutter analyze
fvm flutter test test/import/ --plain-name 'malformed'  # if such a test exists
fvm flutter test test/model/account/ 2>/dev/null || true  # account prefs tests if any

git add lib/src/model/account/account_preferences.dart lib/src/import/pgn_importer.dart lib/src/utils/share.dart
git commit -m "fix(errors): route swallowed catches to Logger, include stack traces, surface share fallback"
./scripts/gates.sh t1
git push -u origin fix/error-fix-29-swallowed-catches
gh pr create -R cassandre60/ChessSRS --title "fix(errors): route swallowed catches to Logger, surface share fallback" --body "Closes ERROR-FIX-29."
```

## 5. Done when

* [ ] `account_preferences.dart` catches use `_logger.warning/severe` with error + stack
* [ ] `pgn_importer.dart:562` catch includes stack trace in the ImportError
* [ ] `share.dart:40` fallback tells the user sharing failed
* [ ] `rg debugPrint` on the three files returns 0 hits
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green
* [ ] PR open against `cassandre60/ChessSRS`

## 6. Sequencing note

* `pgn_importer.dart` is also touched by brief 10 (isolate threshold) and
  brief 25 (size guard) — three agents editing one file. Serialize:
  `10 → 25 → 29`, rebasing on `main` after each merge.
* Brief 24 (debugPrint→Logger) covers `lib/src/view/` only; this brief covers
  `model/` and `utils/`. No overlap.
