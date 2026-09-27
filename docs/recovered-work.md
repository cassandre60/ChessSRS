# Recovered work

Work that existed on a branch, was never reachable from the app, and is not on `main`.
Kept here so it is not re-derived, and so nobody re-litigates a decision already made.

Each entry says what it is, whether it should be wired, and why. A file that is not wired
is not "pending" — it is either superseded or waiting on a design decision, and those are
different things.

---

## `recovery/review-pages-unwired`

Three reskinned pages, all Diagram-native (no `PlatformAppBar`, no `ListTile`), all
written against the current design system. They compiled clean against `main` when
restored, so nothing about them had rotted.

| file | lines | status |
|---|---|---|
| `lib/src/view/review/about_page.dart` | 143 | **wired** — see below |
| `lib/src/view/review/study_actions_sheet.dart` | 431 | not wired, see below |
| `lib/src/view/review/import_pages.dart` | 424 | **superseded**, do not wire |
| `test/view/review/import_pages_test.dart` | 280 | superseded with it |

### `about_page.dart` — wired

Reachable from the Library sheet's *About and licences* row, replacing `showLicensePage`.
The stock page lists package licences and says nothing about the fork; `AGENTS.md` §7
requires attributing the GPL-3.0 code this is built on, and `AboutPage` names it — Lichess
Mobile, chessground and dartchess as GPL-3.0, plus both bundled fonts as SIL OFL 1.1.

Its `AppBar` was replaced with `SrsPageHead` on the way in, since the page became reachable
and every other screen in the fork uses the head.

### `import_pages.dart` — superseded, do not wire

Three full pages (`PastePgnPage`, `LichessImportPage`, `ImportErrorPage`) that duplicate
what `RepertoireImportDialog` already does. The dialog is a reskinned bottom sheet offering
all three routes the design names for *Import PGN* — "From a file, pasted text or a Lichess
study": a file picker, a `maxLines: 6` PGN field, and a Lichess URL/ID field. It is wired
into four call sites and works.

Wiring the pages would replace a working sheet with three pages, gain nothing, and touch
four call sites. `design/docs/03-components.md` §194 also asks for an *Import sheet*, not
pages. Left on the branch; its 280-line test came with it.

If the dialog is ever replaced, these are the reference for what the three routes need.

### `study_actions_sheet.dart` — not wired, and not by oversight

`SrsStudyActionsSheet` is complete: Chapters, Analyze, Practice, Export PGN, Pause/Resume,
Rename, Delete, in the Diagram sheet style.

It is not wired because attaching it is a **design change to the scope list**, not a wiring
task. `design/docs/03-components.md` §4 says row actions are *not* in the list row and are
revealed by long-press, secondary click, or a `…` affordance on hover. The scope rows in
`review_scope_drawer.dart` have none of those, and adding them is its own contract with its
own tests.

Deliberately not committed as dead code: the same reasoning that removed the 832-line tab
switcher applies. It stays on `recovery/review-pages-unwired` until the scope rows grow an
affordance to hang it on.
