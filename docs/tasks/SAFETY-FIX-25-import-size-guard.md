# SAFETY-FIX-25 — No PGN file-size guard → OOM on large imports

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

The import pipeline reads the entire PGN file into a `String` with no size
check:

* `lib/src/view/review/repertoire_import_dialog.dart:133` — `_pickPgnFile`
  reads the picked file with `File.readAsString()`, producing one `String`.
* `lib/src/import/pgn_importer.dart:362` — `importPgnAsync` copies that
  `String` into a new isolate via `Isolate.run` (doubling memory).
* `dartchess` PGN parser builds an AST in memory (tripling memory).
* The domain tree builder materialises `Node` objects (quadrupling memory).

A 50 MB PGN on a 4 GB phone means ~200 MB peak usage inside the parse
isolate, plus the UI isolate's copy. No progress reporting and no way to
cancel. A user importing a Lichess Master Games dump (>100 MB) will get an
OOM kill with no error message.

## 2. Files to read before touching anything

1. `lib/src/view/review/repertoire_import_dialog.dart:100-180` — `_pickPgnFile`
   and `_handlePgnImport` (where the file is read)
2. `lib/src/import/pgn_importer.dart:210-370` — `importPgn` / `importPgnAsync`
   (where the string enters parsing)
3. `lib/src/import/pgn_importer.dart:480-600` — `_buildChildren` (where the
   tree is built, catches malformed moves)
4. `QUALITY.md` — any import-related invariants
5. `design/docs/04-screens-and-flows.md` §10 (import flow) — UX for import
   states

## 3. The fix

### 3.1 Add a file-size guard in the dialog (UI layer)

In `repertoire_import_dialog.dart`, after the file is picked and before
reading its contents, check the file size:

```dart
// After _pickPgnFile selects the file, before readAsString:
const maxPgnBytes = 10 * 1024 * 1024; // 10 MB — covers the largest sane
                                       // repertoire PGN; larger files are
                                       // game databases, not repertoires.
final file = File(result.files.single.path!);
final fileSize = await file.length();
if (fileSize > maxPgnBytes) {
  if (!mounted) return;
  showSnackBar(
    context,
    'PGN file is too large (${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB). '
    'Maximum is ${maxPgnBytes ~/ 1024 ~/ 1024} MB.',
    type: SnackBarType.error,
  );
  return;
}
final pgnText = await file.readAsString();
```

### 3.2 Add the same guard for paste/drop input

`repertoire_import_dialog.dart` also accepts pasted PGN text (line ~260). Add
a string-length guard there:

```dart
if (pgnText.length > maxPgnBytes) {
  // same snackbar as above
  return;
}
```

### 3.3 Optional — add a constant in pgn_importer.dart

If multiple entry points call `importPgn*`, expose the limit as a constant:

```dart
/// Maximum PGN input length (bytes). Larger inputs are rejected at the
/// UI layer; this is a defense-in-depth assert.
const kMaxPgnInputBytes = 10 * 1024 * 1024;
```

And add an early return / assert in `importPgn`:

```dart
if (pgnText.length > kMaxPgnInputBytes) {
  return ImportResult.error('PGN too large (${pgnText.length} bytes)');
}
```

### 3.4 What NOT to change

* Do not add streaming/chunked parsing — that is a separate, large feature.
* Do not change the isolate threshold (brief 10 covers that).
* Do not change `_buildChildren` or the PGN parse logic — only the pre-check.
* Do not touch `SPEC.md`, `GATES.md`, `.gates/`, `pubspec.yaml`.

## 4. Verification

```bash
git worktree add ../chesssrs-safety-fix-25 -b fix/safety-fix-25-import-size-guard origin/main
cd ../chesssrs-safety-fix-25
fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs

# Unit test: add a test in test/import/pgn_importer_test.dart
# that calls importPgn with a string > kMaxPgnInputBytes and asserts
# it returns an ImportResult.error (not an OOM).
fvm flutter test test/import/pgn_importer_test.dart --plain-name 'rejects oversized PGN'

fvm flutter analyze

git add lib/src/import/pgn_importer.dart lib/src/view/review/repertoire_import_dialog.dart test/import/pgn_importer_test.dart
git commit -m "fix(import): reject PGN files larger than 10 MB before reading into memory"
./scripts/gates.sh t1
git push -u origin fix/safety-fix-25-import-size-guard
gh pr create -R cassandre60/ChessSRS --title "fix(import): reject PGN files larger than 10 MB" --body "Closes SAFETY-FIX-25."
```

## 5. Done when

* [ ] `kMaxPgnInputBytes` constant exists (10 MB)
* [ ] `_pickPgnFile` checks `file.length()` before `readAsString()`
* [ ] Paste/drop path checks `pgnText.length` before calling `importPgn*`
* [ ] `importPgn` has a defense-in-depth early return for oversized input
* [ ] New test proves oversized input returns error, not OOM
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green
* [ ] PR open against `cassandre60/ChessSRS`
