# UI-FIX-17 — StudyChaptersScreen still Material (Diagram reskin gap)

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

`lib/src/view/review/study_chapters_screen.dart` is the last Study/library surface
still on legacy Material, while Review, Nothing due, scope list, Library sheet,
first launch/import and Settings were all reskinned to Diagram (`design/docs/04-screens-and-flows.md §1`):

| Legacy (current) | Diagram (spec) |
|---|---|
| `Scaffold` + `AppBar` + `AppBarTitleText` + `Theme.colorScheme` | `Scaffold(ground)` + `SrsPageHead(label: study.title, onBack: …)` |
| `ListTile` + `CircleAvatar(16, primaryContainer)` | `SrsSettingsRow` / `SrsRow` with `SrsMemoryBar(96×5)` + row due numeral |
| `Divider` | `hairlineSoft` `Container(height:1)` |
| `Styles.subtitle`, `textShade(context, …)` | `SrsText.*(c.ink / c.ink2 / c.ink3)` |
| `Icons.share_rounded` etc. without `Srs*` | `SrsPressable` / `SrsIconButton` with Diagram tokens |

A user moving Review → Chapters hits two design systems. Screenshots differ in
type scale, row height, memory bar shape, and app-bar treatment. This is
`tech-debt-inventory.md` U-7 / `design/docs/05-flutter-implementation.md` gap.

## 2. Files to read before touching anything

1. `lib/src/view/review/study_chapters_screen.dart:1-312` — the file to reskin
2. `lib/src/view/analysis/analysis_hub_screen.dart:67-150` — canonical Diagram list pattern (`Scaffold(ground)` + `SrsPageHead` + centered `ConstrainedBox(max 660)` + `ListView` + `SrsSettingsRow`)
3. `lib/src/view/review/review_scope_drawer.dart:588-771` — `_ScopeRow` pattern (name + memory bar + due cell, `accentSoft` selection, `hairlineSoft` hover)
4. `lib/src/design/tokens.dart:30-140, 293-415` — `SrsColors`, `SrsText`, `SrsLayout`
5. `lib/src/design/primitives.dart` or `lib/src/design/srs_sheet.dart` — `SrsSettingsRow`, `SrsSheetRow`, `SrsMemoryBar`, `SrsPressable`, `SrsPageHead`
6. `design/docs/03-components.md §6-8` — Scope row / Library row / Memory bar spec (96×5, gap 2, radius 1; due 17/600)
7. `design/docs/04-screens-and-flows.md §12` — Study chapters screen extrapolation ("same layout as Settings (back button, big title = study name) with rows like scope rows")
8. `test/view/review/study_chapters_screen_test.dart` (if exists) or `test/view/screenshot_capture_test.dart` — existing chapter tests / captures to keep green

## 3. The fix

Reskin `StudyChaptersScreen` to Diagram without changing navigation or data flow.
One screen, one PR. No new dependencies.

### 3.1 Scaffold + header

Replace `Scaffold(appBar: AppBar(...))` with:

```dart
Scaffold(
  backgroundColor: context.srs.ground,
  body: SafeArea(
    child: Column(
      children: [
        SrsPageHead(label: study.title, onBack: () => Navigator.of(context).maybePop()),
        // subtitle "N chapters" becomes a SrsText.meta(c.ink2) line under the head, or folded into the head's help
        Expanded(child: /* list */),
      ],
    ),
  ),
)
```

Center + width-cap like Settings/Hub: `Center > ConstrainedBox(maxWidth: 660) > ListView(padding: 24,6,24,40)`.

Remove `AppBarTitleText`, `textShade`, `Styles.*`, `Theme.of(context).colorScheme`.

### 3.2 Row

Replace `ListTile(leading: CircleAvatar, title: ..., subtitle: Column(opening, progress), trailing: Row(IconButton…))` with a Diagram row:

* Left column: name (`SrsText.rowName`), 6px gap, memory bar + sub line (`SrsMemoryBar(width:96,height:5,gap:2,radius:1, retained/learning/fresh)` + `SrsText.rowSub` with `"${progress.totalDecisions} positions"` or `Paused`, same math as `_ScopeRow`).
* Right: due cell (`SrsText.rowDue` numeral + `SrsText.rowSub("due")` baseline-aligned, 5px gap) like `_DueCell`.
* Actions: `SrsIconButton` / `SrsPressable` for Explore/Practice/Export/chevron, with `hairlineSoft` hover; keep `onTap` → `openChapterAnalysis` / `changeScope` and long-press affordances.

Reuse `SrsMemoryBar` math from drawer: `retained=(learned-due).clamp`, `fresh=(total-learned).clamp`.

### 3.3 Separators + icons

* `Divider(height:1)` → `Container(height:1,color:c.hairlineSoft)` or rely on `SrsSettingsRow`'s own hairline.
* `CircleAvatar` numeral badge → drop it or replace with Diagram's row accent bar (`accentSoft` fill + 3px `accent` left bar when selected, if selection applies).
* Keep `Symbols.*` icons but wrap in `SrsIconButton`.

### 3.4 What NOT to change

* Do not change `openStudyExplorer` / `openChapterAnalysis` helpers (top of file) — they are navigation; only the widget's `build` is reskinned.
* Do not change `ReviewScope.chapter` scoping logic (`onTap` → `changeScope`).
* Do not add new `l10n` keys unless the spec names them — reuse existing `review.*` / `study.*` keys.
* Do not touch `SPEC.md`, `GATES.md`, `.gates/`, `pubspec.yaml`. This is view polish.

## 4. How to make the work verifiable (no guessing)

### 4.1 Worktree setup — required

```bash
git worktree add ../chesssrs-ui-fix-17 -b fix/ui-fix-17-chapters-diagram origin/main
cd ../chesssrs-ui-fix-17
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze
```

Branch name is `fix/ui-fix-17-chapters-diagram`.

### 4.2 Failing-or-proving test

Visual reskin — two proofs:

**(a) Static grep (required):** After the fix, legacy Material tokens must be gone from this file:

```bash
rg -n "AppBar\(|AppBarTitleText|ListTile|CircleAvatar|Styles\.|textShade|Divider\(|primaryContainer" lib/src/view/review/study_chapters_screen.dart
# must print nothing
```

Before the fix this prints ~8 hits.

**(b) Existing tests / captures (required):** `test/view/review/study_chapters_screen_test.dart` (if exists) must stay green — reskin does not change `find.text(chapterTitle)` or `tap Explore`. If `test/view/screenshot_capture_test.dart` exists, its 30 captures over 5 widths must still render; eyeball one phone + one desktop capture against `design/reference/index.html` at the same widths/themes — rows now match the drawer, not Material.

### 4.3 Implement the fix — GREEN

Edit only `lib/src/view/review/study_chapters_screen.dart` (and import `design/design.dart` if not already).

### 4.4 Verify

```bash
rg -n "AppBar\(|ListTile|CircleAvatar" lib/src/view/review/study_chapters_screen.dart
# 0 hits

fvm flutter analyze

fvm flutter test test/view/review/study_chapters_screen_test.dart  # if exists
# or: fvm flutter test test/view/screenshot_capture_test.dart --plain-name 'chapters'

git add lib/src/view/review/study_chapters_screen.dart
git commit -m "fix(design): reskin StudyChaptersScreen to Diagram (SrsPageHead, SrsRow, SrsMemoryBar)"
./scripts/gates.sh t1
```

Gates read committed diff — run after committing (pre-commit is not evidence, see `AGENTS.md` Lesson 2026-10-07).

### 4.5 Push & PR

```bash
git push -u origin fix/ui-fix-17-chapters-diagram
gh pr create -R cassandre60/ChessSRS --title "fix(design): reskin StudyChaptersScreen to Diagram (SrsPageHead, SrsRow, SrsMemoryBar)" --body "Closes UI-FIX-17. See docs/tasks/UI-FIX-17-chapters-screen-diagram-reskin.md."
```

## 5. Done when

* [ ] No `AppBar`/`ListTile`/`CircleAvatar`/`Styles`/`Divider`/`primaryContainer` remains in `study_chapters_screen.dart`
* [ ] Header is `SrsPageHead` on `c.ground`, rows use `SrsMemoryBar(96×5)` + Diagram type/colors
* [ ] `fvm flutter analyze` 0 issues on touched files
* [ ] `./scripts/gates.sh t1` green on committed branch
* [ ] PR open against `cassandre60/ChessSRS`

## 6. Sequencing note

`ARCH-FIX-05` also touches this file (removes `persistence` import) — rebase this branch on `main` after 05 lands, or note the import already gone.
