# REFACTOR-FIX-20 — Dead production symbols cleanup (tech-debt #7)

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

`docs/tech-debt-inventory.md` item 7 lists 20+ identifiers that appear exactly
once across `lib/` + `test/` + `scripts/` (declaration only, no call). A subset
are framework overrides (not dead); the rest are genuinely never called in
production. Additionally, `getDueReviewStates` and `getDueCount` have zero
production callers — only test coverage. Keeping dead symbols costs nothing at
runtime but misleads maintainers and inflates the reachability ratchet.

### Top 5 confirmed dead (verified by tree-wide grep):

| Symbol | File | Evidence |
|--------|------|----------|
| `getDueReviewStates` | `sqlite_study_repository.dart:754` + `study_repository.dart:92` | Zero callers in `lib/`. Only `test/persistence/:274`. |
| `getDueCount` | `review_service.dart:391` | Zero callers in `lib/`. Wraps `getDueSummary` which every real caller uses. |
| `toggleAnimateOpponentPreMove` | `study_preferences.dart:105` | Read side `_shouldAnimateOpponentPreMove` is live; the write toggle has zero callers — user can never change it. |
| `kSliderTheme` | `theme.dart` | Already removed in tech-debt batch 1 — verify it stayed gone. |
| `SrsMovePair` | `design/notation_line.dart` | Zero callers across `lib/` + `test/`. |

Also confirmed: `setLocale`, `getCurrentGame`, `setPremove`, `setConfirmResign`,
`makeCurrentNodePgn`, `toApiForecast`, `harmonized`, `winningChancesPovDiff`, the
`as…OrNull` family in `id.dart`/`chess.dart` — all have zero callers outside
their own file's declaration.

## 2. Files to read before touching anything

1. `docs/tech-debt-inventory.md` §3 "Dead-code evidence" — full list with grep evidence
2. Each file listed in §3 — verify the symbol is still present and still has zero callers
3. `test/reachability/reachability_test.dart` — if any of these symbols are in files pinned as
   unreachable, removing the symbol from a reachable file is fine but removing the file itself
   is a separate product decision (tech-debt #20)
4. `GATES.md` + `.gates/ratchets.json` — the `test_declarations` ratchet may change if a test
   file that only tests a dead symbol is also removed (G10)

## 3. The fix

Delete each dead symbol. One commit per logical group (e.g. "dead model symbols",
"dead preference toggles", "dead service methods"). Do NOT remove `getDueReviewStates`
if a test file exercises it as a regression lock — leave it and note "test-only" in a
comment. For `toggleAnimateOpponentPreMove`, the preference setting exists but
cannot be written; either delete the toggle (leave the reader live) or wire it to
Settings.

**Concrete instructions per symbol:**

* `getDueCount` (`review_service.dart:391-395`): delete the method declaration + body.
  Remove the `@override` if it implements an interface (it does not — it is on `ReviewService`
  directly). No test references to update (test callers can use `getDueSummary` directly).
* `getDueReviewStates` (`sqlite_study_repository.dart:754-762`, `study_repository.dart:92`):
  keep the declaration + implementation because
  `test/persistence/sqlite_study_repository_test.dart:274` tests it. Add a one-line comment
  `/// Test-only; no production caller.` on both.
* `toggleAnimateOpponentPreMove` (`study_preferences.dart:105`): delete. The setting's
  *read* side (`_shouldAnimateOpponentPreMove` in `review_controller.dart`) stays.
* `SrsMovePair` (`design/notation_line.dart`): delete the class.
* `setLocale`, `getCurrentGame`, `setPremove`, `setConfirmResign`, etc.: delete each. Verify
  no test references with `rg <symbol> lib/ test/` before deleting.

### What NOT to change

* Do not delete framework overrides (`didPush`, `updateShouldNotify`, etc.).
* Do not delete files — only symbols within files. File removal is tech-debt #20.
* Do not touch `SPEC.md`, `GATES.md`, `.gates/`, `pubspec.yaml`.
* One PR, multiple commits grouped by file area.

## 4. Verification

```bash
git worktree add ../chesssrs-refactor-fix-20 -b fix/refactor-fix-20-dead-symbols origin/main
cd ../chesssrs-refactor-fix-20
fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs

# For each symbol:
rg -n "<symbol>" lib/ test/
# Must show 0 callers in lib/ (declaration-only hit is the one you delete)

fvm flutter analyze   # 0 issues after each deletion
fvm flutter test test/persistence/sqlite_study_repository_test.dart  # if getDueReviewStates kept
fvm flutter test test/review/review_service_test.dart  # getDueCount was never called from tests either

git add <touched files>
git commit -m "refactor: remove dead production symbols (getDueCount, toggleAnimateOpponentPreMove, SrsMovePair, …)"
./scripts/gates.sh t1
git push -u origin fix/refactor-fix-20-dead-symbols
gh pr create -R cassandre60/ChessSRS --title "refactor: remove dead production symbols" --body "Closes REFACTOR-FIX-20."
```

## 5. Done when

* [ ] Each symbol from the list is deleted (or marked test-only with a comment)
* [ ] `rg <symbol> lib/` returns 0 hits per deleted symbol
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green (G10 ratchets may improve)
* [ ] PR open against `cassandre60/ChessSRS`
