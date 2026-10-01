# Polish Task List — Chess Repertoire SRS

Generated from comprehensive codebase review (2026-09-29).

> **Status (2026-10-01):** All 6 tasks have been completed and merged to `main`:
> - Task 1 (`_NoStudiesView` l10n) in PR #106
> - Task 2 (Board Settings Screen l10n) in PR #106
> - Task 3 (Toggle Sound Button tooltip l10n) in PR #106 / #109
> - Task 4 (dartchess FEN side parsing) in PR #116
> - Task 5 (narrow exception catch in `_hasAnnotationsOrShapes`) in PR #107
> - Task 6 (replace fixed delays with condition-based polling) in PR #117

---

## Required — Hardcoded English → l10n

### 1. `_NoStudiesView` welcome screen (`lib/src/view/review/review_screen.dart`)
| Line | Text | Suggested l10n Key |
|------|------|-------------------|
| 133 | "Bring your repertoire." | `review.noStudies.headline` |
| 145 | "Import a PGN or a Lichess study. Everything stays on this device, and reviews work offline." | `review.noStudies.subtext` |
| 158 | "Drop a PGN file here" | `review.noStudies.dropZone` |
| 163 | "Choose file" | `review.noStudies.chooseFile` |
| 180 | "Paste PGN text" | `review.noStudies.pastePgn` |
| 188 | "Import a Lichess study" | `review.noStudies.importLichess` |
| 201 | "Train as" | `review.noStudies.trainAs` |
| 207 | "Auto", "White", "Black" | `review.noStudies.auto`, `review.noStudies.white`, `review.noStudies.black` |
| 510 | "Practice" (button label) | `review.nothingDue.practice` |

**Files to update:**
- `lib/src/view/review/review_screen.dart` (lines 132–212, 509)
- `lib/l10n/l10n_en.arb` + all locale ARBs

---

### 2. Board Settings Screen (`lib/src/view/settings/board_settings_screen.dart`)
| Line | Current | Suggested l10n Key |
|------|---------|-------------------|
| ~TODO | "Board theme" section label | `settings.board.theme` |
| ~TODO | "Piece set" section label | `settings.board.pieceSet` |
| ~TODO | "Coordinates" toggle label | `settings.board.coordinates` |

**Files to update:**
- `lib/src/view/settings/board_settings_screen.dart` (search `// TODO l10n`)
- `lib/l10n/l10n_en.arb` + all locale ARBs

---

### 3. Toggle Sound Button (`lib/src/view/settings/toggle_sound_button.dart`)
| Line | Current | Suggested l10n Key |
|------|---------|-------------------|
| ~TODO | Tooltip / semantic label | `settings.sound.toggleTooltip` |

**Files to update:**
- `lib/src/view/settings/toggle_sound_button.dart`
- `lib/l10n/l10n_en.arb` + all locale ARBs

---

## Optional — Code Quality

### 4. Use `dartchess` for FEN side parsing (`lib/src/domain/review/review_session.dart:660`) *(done in PR #116)*
```dart
// Current: manual FEN string split
Side _sideFromFen(String fen) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  if (parts.length > 1 && parts[1].toLowerCase() == 'b') {
    return Side.black;
  }
  return Side.white;
}

// Suggested: use dartchess Position
Side _sideFromFen(String fen) {
  try {
    final pos = Setup.parseFen(fen);
    return pos.turn;
  } catch (_) {
    return Side.white;
  }
}
```
**Files:** `lib/src/domain/review/review_session.dart`
**Tests:** Add unit test for `_sideFromFen` with various FENs

---

### 5. Narrow exception catch in `_hasAnnotationsOrShapes` (`lib/src/view/review/review_controller.dart:234`) *(done in PR #107)*
```dart
// Current: catches all exceptions
try {
  final prefs = ref.read(studyPreferencesProvider);
  final pgn = PgnComment.fromPgn(comment);
  ...
} catch (_) {
  return comment.trim().isNotEmpty;
}

// Suggested: catch specific parse errors
try {
  final prefs = ref.read(studyPreferencesProvider);
  final pgn = PgnComment.fromPgn(comment);
  ...
} on FormatException catch (_) {
  return comment.trim().isNotEmpty;
}
```
**Files:** `lib/src/view/review/review_controller.dart`

---

### 6. Fix test flakiness in `pumpAsync` helpers (shared test infrastructure)
**Problem:** Fixed `Future.delayed(80ms)` causes flakiness under CPU contention (AGENTS.md Lessons Learned 2026-09-28)
**Fix:** Replace with condition polling
```dart
// Instead of:
await Future.delayed(const Duration(milliseconds: 80));
await tester.pump();

// Use:
await tester.pumpUntilFound(
  find.byType(SomeWidget),
  timeout: const Duration(seconds: 5),
);
```
**Files:** `test/test_helpers.dart` (or wherever `pumpAsync` is defined)
**Scope:** Only affects 4 load-sensitive review controller tests

---

## Verification Checklist per Task

For each l10n task:
- [ ] Add English strings to `lib/l10n/l10n_en.arb`
- [ ] Run `fvm flutter gen-l10n` to regenerate `lib/l10n/*.dart`
- [ ] Replace hardcoded strings with `context.l10n.key`
- [ ] Run `fvm flutter analyze` — zero warnings
- [ ] Run affected widget tests
- [ ] Manual runtime check: switch device language, verify translation appears

For code quality tasks:
- [ ] Make minimal change
- [ ] Run `fvm flutter analyze` on touched files
- [ ] Run related unit/widget tests
- [ ] Verify no regression in vertical slice test

---

## Suggested Order

1. **Task 1** — `_NoStudiesView` (highest visibility, first-launch experience)
2. **Task 2** — Board Settings (settings are user-facing)
3. **Task 3** — Toggle Sound Button (small, isolated)
4. **Task 4** — dartchess FEN parsing (consistency, no user-visible change)
5. **Task 5** — Narrow exception catch (defensive coding)
6. **Task 6** — Test flakiness fix (infrastructure, run after others to verify)

---

## Notes

- All locale ARBs (`l10n_*.dart`) are generated — edit `l10n_en.arb` and run `flutter gen-l10n`
- The app uses `SrsText.ui` (Instrument Sans) which supports Latin/Cyrillic/Greek; verify glyph coverage for target locales
- No RTL-specific layout changes needed — `ReviewScreen` uses `SrsReviewLayout` which handles `whiteAtBottom` for board orientation, not text direction