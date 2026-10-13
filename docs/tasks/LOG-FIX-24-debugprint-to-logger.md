# LOG-FIX-24 — 16 SEVERE debugPrint calls bypass Logger pipeline (tech-debt #16)

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

The app owns a structured log pipeline (`model/log/*`, `Logger`, `AppLogSettingsScreen`),
yet 16 view-layer error sites bypass it entirely with `debugPrint('SEVERE: [ClassName] …')`.
These errors never appear in the in-app log viewer, can't be filtered by level or
category, and can't be exported for diagnostics. `tech-debt-inventory.md` item 16
(Impact 2, Effort 2, Risk L) tracks this as "Logging is split between Logger and
debugPrint".

### Sites (all `debugPrint('SEVERE: …')` in `lib/src/view/`):

| File | Line | Current |
|------|------|---------|
| `game_bookmarks_screen.dart` | 175 | `debugPrint('SEVERE: [GameBookmarks] …')` |
| `import_pgn_screen.dart` | 145 | `debugPrint('SEVERE: [ImportPgn] …')` |
| `create_study_chapter_bottom_sheet.dart` | 288, 334 | `debugPrint('SEVERE: [CreateChapter] …')` |
| `opening_explorer_view.dart` | 153 | `debugPrint('SEVERE: [Explorer] …')` |
| `tablebase_view.dart` | 146 | `debugPrint('SEVERE: [Tablebase] …')` |
| `gif_export_dialog.dart` | 79 | `debugPrint('SEVERE: [GifExport] …')` |
| `game_history_screen.dart` | 334 | `debugPrint('SEVERE: [GameHistory] …')` |
| `perf_stats_screen.dart` | 399 | `debugPrint('SEVERE: [PerfStats] …')` |
| `recent_games.dart` | 65 | `debugPrint('SEVERE: [RecentGames] …')` |
| `user_activity.dart` | 41 | `debugPrint('SEVERE: [UserActivity] …')` |
| `review_scope_drawer.dart` | 501 | `debugPrint('SEVERE: [ReviewScopeDrawer] …')` |
| `repertoire_import_dialog.dart` | 191, 244 | `debugPrint('SEVERE: [RepertoireImportDialog] …')` |
| `export_pgn_dialog.dart` | 60, 82 | `debugPrint('SEVERE: [ExportPgn] …')` |

Plus 3 non-SEVERE `debugPrint` sites in `search_screen.dart:189`, `perf_stats_screen.dart:159`, `analysis_settings_screen.dart:164`.

## 2. Files to read before touching anything

1. Each file listed above — read the `try/catch` block surrounding the `debugPrint`
2. `lib/src/model/log/` — the `Logger` infrastructure (how other services use `Logger('Name')`)
3. `lib/src/view/settings/app_log_settings_screen.dart` — the in-app log viewer (shows `Logger` output)
4. `docs/tech-debt-inventory.md` item 16 — prior analysis

## 3. The fix

For each site, replace `debugPrint('SEVERE: [Name] …: $e')` with:

```dart
// At the top of the file, add once:
final _logger = Logger('ClassName');

// At each catch site:
_logger.severe('Description of what failed', e, st);
// or _logger.warning(...) if the severity is lower
```

Keep the `showSnackBar(context, 'User-facing message', type: SnackBarType.error)`
line unchanged — the user-visible message stays the same. Only the debug output
switches from `debugPrint` to `Logger`.

For the 3 non-SEVERE sites, use `_logger.warning(...)` instead.

Do NOT import `dart:developer` — `package:logging/logging.dart` is already used
everywhere in the codebase. The `Logger` constructor is `Logger('Name')` — no
registration needed; the log pipeline picks it up automatically.

### What NOT to change

* Do not change user-visible error messages (snackbar text).
* Do not change the `try/catch` structure — only the debug output inside `catch`.
* Do not touch `app_log_settings_screen.dart:206` (`Text('Failed to load logs: $error')`)
  — that one intentionally shows the error to the user (it IS the log viewer).
* Do not touch `SPEC.md`, `GATES.md`, `.gates/`, `pubspec.yaml`.

## 4. Verification

```bash
git worktree add ../chesssrs-log-fix-24 -b fix/log-fix-24-debugprint-to-logger origin/main
cd ../chesssrs-log-fix-24
fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs

# Before: 19 debugPrint hits in view/
rg -c "debugPrint" lib/src/view/
# After: 0 (or 1 if app_log_settings_screen stays)

fvm flutter analyze

# No test file touches needed — debugPrint → Logger is behavior-preserving
# for the user (same snackbar) and invisible to widget tests (they don't
# assert on debug output).

git add <all touched view files>
git commit -m "refactor(view): route SEVERE debugPrint to Logger pipeline"
./scripts/gates.sh t1
git push -u origin fix/log-fix-24-debugprint-to-logger
gh pr create -R cassandre60/ChessSRS --title "refactor(view): route SEVERE debugPrint to Logger pipeline" --body "Closes LOG-FIX-24."
```

## 5. Done when

* [ ] `rg debugPrint lib/src/view/` returns 0 hits (or 1 for `app_log_settings_screen`)
* [ ] Each former `debugPrint('SEVERE: …')` is now `_logger.severe(…)` with the same error/stack
* [ ] User-visible snackbar text unchanged
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green
* [ ] PR open against `cassandre60/ChessSRS`
