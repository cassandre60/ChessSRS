# RATCHET-FIX-22 — Prune 5–6 stale entries from reachability test baseline

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

`test/reachability/reachability_test.dart` pins 16 files as `_knownUnreachable`
(tech-debt #20). A tree-wide import trace shows **5–6 of these are now reachable**
— they became reachable after being listed (new imports from reskin/hub PRs)
but the baseline was never updated. The ratchet is therefore too loose: a new
unreachable file could hide among the stale entries without triggering a failure.

### Stale entries (reachable via import chains from `lib/main.dart`):

| File | Reached via |
|------|------------|
| `lib/src/view/analysis/analysis_hub_screen.dart` | `review_screen.dart:13` → `app.dart` |
| `lib/src/view/explorer/opening_explorer_screen.dart` | `analysis_hub_screen.dart:14` (transitive) |
| `lib/src/view/study/create_study_chapter_bottom_sheet.dart` | `study_bottom_bar.dart:13` → `study_screen.dart` → `review_scope_drawer.dart` |
| `lib/src/view/user/user_profile.dart` | `profile_screen.dart:17` → `account_menu.dart` → `srs_settings_screen.dart` |
| `lib/src/view/user/user_activity.dart` | `profile_screen.dart:16` (same chain) |
| `lib/src/view/game/game_common_widgets.dart` | `analysis_screen.dart:30` — its own entry says "NOT DELETABLE"; listing is known-stale |

### Genuinely still unreachable (~10–11 files):
`chess_clock.dart`, `game.dart`, `game_preferences.dart`, `social_icons.dart`,
`image.dart`, `chess_srs.dart`, `account_preferences_screen.dart`,
`board_settings_screen.dart`, `theme_settings_screen.dart`, `study_list_screen.dart`,
`library_sheet.dart`.

## 2. Files to read before touching anything

1. `test/reachability/reachability_test.dart` — the baseline map (`_knownUnreachable`)
2. `lib/src/app.dart` — root of the import tree
3. Each stale entry's importer (see §1 table) — verify the import chain is real
4. `GATES.md` / `.gates/ratchets.json` — `test_declarations` ratchet (if a test assertion changes)

## 3. The fix

Remove the 5–6 stale entries from `_knownUnreachable`. Leave the 10–11 genuinely
unreachable entries. Run the test to confirm it still passes — the traversal will
now find those files reachable and will not list them as missing-from-baseline.

```dart
// BEFORE (16 entries)
final _knownUnreachable = {
  'analysis_hub_screen.dart': ...,
  'opening_explorer_screen.dart': ...,
  'create_study_chapter_bottom_sheet.dart': ...,
  'user_profile.dart': ...,
  'user_activity.dart': ...,
  'game_common_widgets.dart': ..., // "NOT DELETABLE"
  // ... 10 genuinely unreachable ...
};

// AFTER (10–11 entries)
final _knownUnreachable = {
  // removed: analysis_hub_screen, opening_explorer_screen,
  //          create_study_chapter_bottom_sheet, user_profile,
  //          user_activity, game_common_widgets
  // ... 10 genuinely unreachable ...
};
```

For `game_common_widgets.dart`: its listing already acknowledges reachability
("NOT DELETABLE") — remove it from the unreachable set. If the test's traversal
algorithm does NOT follow exports/re-exports and misses it, keep it listed and
note the traversal limitation; otherwise remove.

### What NOT to change

* Do not delete the unreachable *files* — that is a product decision (tech-debt #20,
  owner approval required per `CUT_PROPOSALS.md`).
* Do not change the traversal algorithm — only the baseline data.
* Do not touch `SPEC.md`, `GATES.md`, `.gates/`, `pubspec.yaml`.
* This is a `test-only` change class.

## 4. Verification

```bash
git worktree add ../chesssrs-ratchet-fix-22 -b fix/ratchet-fix-22-reachability-prune origin/main
cd ../chesssrs-ratchet-fix-22
fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs

# Run the reachability test — it must pass with the tighter baseline
fvm flutter test test/reachability/reachability_test.dart
# If any of the "removed" entries still show as unreachable, add them back — the traversal
# may not follow a particular import pattern. Trust the test over the manual chain analysis.

fvm flutter analyze

git add test/reachability/reachability_test.dart
git commit -m "test(reachability): prune 5 stale entries now reachable from main"
./scripts/gates.sh t1
git push -u origin fix/ratchet-fix-22-reachability-prune
gh pr create -R cassandre60/ChessSRS --title "test(reachability): prune stale entries now reachable from main" --body "Closes RATCHET-FIX-22."
```

## 5. Done when

* [ ] Stale entries removed from `_knownUnreachable` (5–6 files)
* [ ] `fvm flutter test test/reachability/reachability_test.dart` passes
* [ ] Remaining entries are genuinely unreachable (test would fail if they were removed)
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green
* [ ] PR open against `cassandre60/ChessSRS`
