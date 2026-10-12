# L10N-FIX-18 — Hardcoded "PGN copied." string bypasses l10n (TODO l10n)

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

One user-visible string is hardcoded English with an explicit debt marker:

`lib/src/widgets/pgn.dart:1490`:
```dart
messenger.showSnackBar(const SnackBar(content: Text('PGN copied.'))); // TODO l10n
```

`rg TODO l10n lib/` has **exactly one hit** in non-docs code — this file. `docs/polish-tasks.md` notes the file as `board_settings_screen.dart` search, but the grep proves the surviving literal is in `pgn.dart` only. With `l10n` ARB generation, the correct flow is `l10n_en.arb` → `flutter gen-l10n` → `context.l10n.*` (see `docs/internationalisation.md`, `lib/l10n/app_en.arb`, `lib/l10n/l10n.dart:623` `mobileSomethingWentWrong`).

A second surface (`lib/src/view/review/export_pgn_dialog.dart:170`) already uses a non-TODO literal `PGN copied to clipboard`, and `test/view/analysis/analysis_screen_test.dart:808,841` asserts `find.text('PGN copied.')` — so any fix must keep those tests green (they are the oracle for the copy action).

## 2. Files to read before touching anything

1. `lib/src/widgets/pgn.dart:1486-1498` — the TODO line + surrounding `SnackBar` / `ScaffoldMessenger`
2. `lib/src/view/review/export_pgn_dialog.dart:170` — second copy literal ("PGN copied to clipboard") — decide whether to unify or leave
3. `lib/l10n/app_en.arb` + `lib/l10n/app_en_US.arb` — english ARBs (where `mobileSomethingWentWrong` lives)
4. `lib/l10n/l10n.dart:623` + `lib/l10n/l10n_en.dart:236` — generated l10n accessor pattern
5. `lib/src/utils/l10n_context.dart` — `context.l10n` helper
6. `docs/internationalisation.md` — l10n pipeline doc (ARB → gen-l10n → `context.l10n`)
7. `test/view/analysis/analysis_screen_test.dart:808,841` — asserts `Text('PGN copied.')`
8. `docs/polish-tasks.md` — notes board_settings_search is now clean (no TODO l10n there)
9. `analysis_options.yaml` / `scripts/gates/banned_apis_check.py` — l10n TODO gate if any

## 3. The fix

Add an ARB key and use `context.l10n` in `pgn.dart`. Keep the change minimal — one new string, one replacement, no refactor.

### 3.1 Add ARB entries

In `lib/l10n/app_en.arb` (and `app_en_US.arb` if it mirrors `app_en.arb`), add:

```json
"pgnCopied": "PGN copied.",
"@pgnCopied": { "description": "Toast after copying PGN to clipboard from the game tree view." }
```

(If the file already has a grouping comment like `@@locale` / `"@_comment"`, place near `mobileSomethingWentWrong`.)

Then regenerate (requires FVM pinned toolchain):

```bash
fvm flutter gen-l10n
# (Verify lib/l10n/l10n_en.dart gains String get pgnCopied)
```

### 3.2 Use it in pgn.dart

Replace the hardcoded literal + remove the TODO:

```dart
// BEFORE
messenger.showSnackBar(const SnackBar(content: Text('PGN copied.'))); // TODO l10n

// AFTER
messenger.showSnackBar(SnackBar(content: Text(context.l10n.pgnCopied)));
```

Add `import 'package:chess_srs/src/utils/l10n_context.dart';` (or `l10n/l10n.dart`) if not already imported in this file. Remove `const` from `SnackBar` — `l10n` is not const.

Do **not** change `export_pgn_dialog.dart:170`'s `PGN copied to clipboard` in this PR — different file, different string, and its wording intentionally includes "to clipboard". Unifying would require updating two ARBs + two call sites + two test files; if unification is desired, scope a separate `L10N` follow-up.

### 3.3 Update the test

`test/view/analysis/analysis_screen_test.dart:808,841` asserts `find.text('PGN copied.')`. With l10n, the text becomes the ARB's English value (still `PGN copied.`), so these tests remain green *if* the test harness sets locale to English (`l10n_en`). If the test pumps with a default `WidgetTester` without `l10n`, it will read the generated English and still pass. If the test does fail because the widget now needs a `BuildContext.l10n`, wrap the tested subtree in the app's `MaterialApp(localizationsDelegates: ...)` as `analysis_screen_test.dart` already does for other l10n consumers — copy that pattern.

### 3.4 What NOT to change

* Do not change `analysis_options.yaml`, `pubspec.yaml` generation config.
* Do not touch `SPEC.md`, `GATES.md`, `.gates/`, `pubspec.yaml` deps.
* Do not change `export_pgn_dialog.dart`'s separate string in this PR.
* Remove the `// TODO l10n` line when the literal is gone — no TODO should survive for this string.

## 4. How to make the work verifiable (no guessing)

### 4.1 Worktree setup — required

```bash
git worktree add ../chesssrs-l10n-fix-18 -b fix/l10n-fix-18-pgn-copied origin/main
cd ../chesssrs-l10n-fix-18
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze
```

Branch name is `fix/l10n-fix-18-pgn-copied`.

### 4.2 Failing-or-proving test

**Before edit (baseline):**

```bash
rg -n "TODO l10n" lib/src/widgets/pgn.dart  # prints: ...:1490: ... // TODO l10n
```

**After edit:**

```bash
rg -n "TODO l10n" lib/src/widgets/pgn.dart  # prints nothing
rg -n "pgnCopied|l10n.*pgn" lib/src/widgets/pgn.dart lib/l10n/app_en.arb  # hits in both
```
And the analysis screen test that asserts the toast must still pass:

```bash
fvm flutter test test/view/analysis/analysis_screen_test.dart --plain-name 'PGN copied'
# or: fvm flutter test test/view/analysis/analysis_screen_test.dart
```

### 4.3 Implement the fix — GREEN

Edit only `lib/src/widgets/pgn.dart`, `lib/l10n/app_en.arb` (and `app_en_US.arb` if mirrored), then run gen-l10n.

### 4.4 Verify

```bash
rg -n "TODO l10n" lib/  # 0 hits

fvm flutter gen-l10n            # regenerates lib/l10n/*.dart
fvm flutter analyze

fvm flutter test test/view/analysis/analysis_screen_test.dart --plain-name 'PGN copied'
fvm flutter test test/view/analysis/analysis_screen_test.dart  # whole file, once

git add lib/src/widgets/pgn.dart lib/l10n/app_en.arb lib/l10n/app_en_US.arb lib/l10n/l10n_en.dart lib/l10n/l10n.dart
git commit -m "fix(l10n): use ARB string for PGN copied toast"
./scripts/gates.sh t1
```

Gates read committed diff — run after committing (pre-commit is not evidence). Note: `lib/l10n/*.dart` is generated but tracked; if the gate's protected-path includes `lib/l10n/*.dart`, run `gen-l10n` first so the gate sees a formatter-clean file; the alternative is to `.gitignore` `lib/l10n/*.dart` but the repo currently generates into `lib/l10n/`.

### 4.5 Push & PR

```bash
git push -u origin fix/l10n-fix-18-pgn-copied
gh pr create -R cassandre60/ChessSRS --title "fix(l10n): use ARB string for PGN copied toast" --body "Closes L10N-FIX-18. See docs/tasks/L10N-FIX-18-pgn-copied-l10n.md."
```

## 5. Done when

* [ ] `rg TODO l10n lib/` prints nothing
* [ ] `lib/l10n/app_en.arb` has `pgnCopied` entry with `@pgnCopied` description
* [ ] `lib/src/widgets/pgn.dart:1490` uses `context.l10n.pgnCopied` (no TODO, no hardcode)
* [ ] `fvm flutter gen-l10n` + `fvm flutter analyze` 0 issues
* [ ] `analysis_screen_test.dart` toast asserts still green
* [ ] `./scripts/gates.sh t1` green on committed branch
* [ ] PR open against `cassandre60/ChessSRS`
