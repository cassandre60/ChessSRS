# Manual test log — things the suite cannot check

Every item here passed its automated tests and CI, and still needs a human with
the app. The usual reason: **a test can assert that a sound was requested, never
that a speaker produced it.** Unit tests fake the sound service, so audio and
haptics are structurally outside their reach.

This exists so those caveats are somewhere you can go with the app open, rather
than buried in commit messages nobody reads.

**How to use:** open the app, try the item, then mark it. An item you have not
tried is not verified, however green its CI was.

---

## Open

### 1. PGN comment shapes moved to one shared file (refactor, `pgn_shapes.dart`)

**What changed.** Nothing visible on purpose: the 15-line `PgnCommentShape → Shape`
conversion was copy-pasted in three files (analysis board, review screen, study
screen) and now lives once in `lib/src/widgets/pgn_shapes.dart`. Same mapping,
same chessground/dartchess entry points, same call sites.

**What the tests prove.** That the mapping is correct (new unit test: green arrow,
yellow circle, orig/dest), and that all three screens still build and behave
(14 study + 44 review widget tests green, unchanged). What they do not prove is
pixel identity — no test screenshots an arrow.

**What only you can check.** Open a study whose PGN has comment shapes (`[%cal]`
/ `[%csl]` tags — e.g. import any Lichess study with arrows), and confirm on
each of the three surfaces that arrows and circles render exactly as before:
analysis board, review screen mid-session, study screen. Pay attention to color
(the app maps through its own `ShapeColor`, not chessground's) and to circles
(`from == to`), which take a different constructor.

**How to test it.** Import a PGN containing `[%cal Ge2e4]` and `[%csl Ye4]`
comments, open it in analysis, start a review session on it, and open the study
screen. All three should show a green arrow e2→e4 and a yellow circle on e4.

### 2. Partial-import toast names what was skipped (#160)

**What changed.** A partial import now says what it skipped: the success toast
gains `N problem(s) in M chapter(s): <first error message>` when the import
result carries errors (PGN-text and Lichess paths both). Complete imports are
unchanged.

**What the tests prove.** A widget test drives the real dialog with a PGN whose
third move is illegal and asserts the toast contains the problem count and the
skipped move (`Bh6`). What a widget tree cannot see is whether the toast is
legible where it actually appears.

**What only you can check.** On a phone-width window, import a PGN with a bad
move (e.g. `1. e4 e5 2. Nf3 Nc6 3. Bh6 *`) and confirm the toast is readable
and stays on screen long enough to finish it — it is several lines longer than
the old one-liner.

---

### 2. Scope rows announce their selection to a screen reader (#167)

**What changed.** The review scope drawer's rows carry the `selected` semantics
flag now, so the row that is the live scope is announced as selected instead of
being indistinguishable from a row with the same due count.

**What the tests prove.** That the selected row's semantics node has
`isSelected: true` and a non-selected row's has `false` (a widget test over the
real drawer). What they do not prove is that a screen reader says it — a test
can assert a semantics flag, never an announcement.

**What only you can check.** With a screen reader running, open the review scope
drawer and move through the rows: the active scope's row should be announced as
selected, and the others should not. Nobody has heard it say that yet; the flag
is machine-verified, the spoken announcement is not.

**How to test it.** On Linux, start Orca (`orca --replace`), open the app, open
the review scope drawer, and arrow through the rows with the keyboard. The row
for the current scope should be read as "selected".

---

### 3. The engine button toggles the engine again (#315)

**What changed.** Pressing the engine button in the analysis board raised
`setState() callback argument returned a Future` and did nothing. The callback
that holds the in-flight future returned the future it assigned, and `setState`
requires a void callback; the callback now assigns in a block.

**What the tests prove.** That a press of the real `EngineButton` raises no
Flutter assertion, and that the button is disabled while a toggle is in flight
(a widget test with a slow preference write, so the toggle outlives the frame
that follows the press). What they do not prove is that the engine really
starts and stops: the widget test drives a fake engine and fake preferences.

**What only you can check.** Open an analysis board with the engine allowed and
press the engine button (the micro-chip at the foot of the board). The engine
should start and the chip should show a depth; press it again and it should
stop. Then press it twice quickly: the engine should toggle **once**, not twice
and back to where it started — the in-flight guard is what swallows the second
press, and it only exists now because the assignment happens outside the
assertion.

**For the record.** A release build skips the assertion, so the press worked
there; but the guard was dead there too, because the assignment lived inside
the assertion — which only runs when assertions are enabled. The button has
been dead in debug builds (anything started with `flutter run`, and every test)
since #106 on 2026-09-30, and the guard has been dead in every build.

---

### 4. The board editor drew its status panel twice in a band of window sizes

**What changed.** The editor decided its layout from the shape of the *area left to
the editor* and decided whether to show the status panel (the live FEN and the
side-to-move control) in the bottom bar from the shape of the *screen*. The chrome
around the board takes height off that area and no width off it, so the area's shape
is always wider than the screen's. In the band where the screen is taller than it is
wide but the area left to the editor is wider than it is tall, the two disagreed and
the panel was drawn **twice**: once in a column beside the board, once in the bottom
bar. Both decisions now read the screen's shape.

**What the tests prove.** That at an 800×900 window the panel is drawn exactly once
(a new widget test that fails on the base code with two copies of the live FEN), and
that the rest of the editor's tests are unchanged. What they do not prove is how the
editor *looks* in that band: the test counts widgets and measures rectangles, it does
not look at the screen.

**What only you can check.** Resize the window to something taller than it is wide
but not by much — 810×1080 (a tablet in portrait) or 800×900 — and open the board
editor. The live FEN and the "White to play / Black to play" control should each
appear **once**, under the board. On the base build each appeared twice. The board
should also come out bigger than it did in that band, because the side column no
longer squeezes it.

**How to test it.** On Linux desktop, `fvm flutter run -d linux`, open the board
editor, and resize the window to 810×1080 and then to 844×390 (a landscape phone):
in the first the panel sits under the board, in the second beside it, and in both it
appears exactly once.

### 5. A shape drawn in a study chapter no longer survives a chapter switch

**What changed.** The study board's shape-clearing guard watched the loading
flag, which never flips on a chapter switch — `goToChapter` assigns the new
state directly — so a shape the user drew in one chapter stayed on the board in
the next one, pointing at a position that had nothing to do with it. The guard
now watches the chapter identity, which is what a chapter switch changes.

**What the tests prove.** That the drawn shape is gone after the chapter
switch, and that it is still there after an unrelated rebuild of the same
chapter (a widget test that drives the real two-pointer draw gesture on the
real board). What they do not prove is how the board looks on a device.

**What only you can check.** The draw gesture is a two-finger *touch* gesture:
chessground locks the draw mode with the first pointer and drags the shape out
with a second one, so a mouse cannot draw a shape at all — the Linux desktop
build has no touch input, and this change was therefore never exercised in the
running app here.

**How to test it.** On a phone or a tablet, open a study with at least two
chapters, draw an arrow on the board (hold one finger on an empty square, drag
a second finger away from it), then switch to the next chapter with the chapter
dialog. The arrow must not follow you to the new chapter.

---

## Closed

### #93 — review moves now make a sound (#93, `c00856c36`)

**Verified 2026-10-13 by the owner, in the running app.** Launched
`fvm flutter run -d linux` on `main` at `14f4bb3d0`, started a review session and
confirmed the move sound is audible on a user move. This is the check no test
could do: the suite asserts the sound service is *asked* for `Sound.move`, and
`FakeSoundService` returns `Future.value()`, so it passes identically with the
volume at zero.

**Confirmed:** a user's own move is audible in review training.

**Not individually confirmed, and not claimed:** that the capture sound is
distinguishable from the plain move sound in practice, and that a check produces
the heavier haptic. Both are asserted by the automated tests at the service
boundary; neither has been checked by ear or by hand. If you try them, record it
here.

**What was broken, for the record.** Review played a sound for the opponent's
auto-reply and for an animated pre-move, and nothing at all for the move the user
makes — every position the user actually played was silent, with no haptics
either. Study and analysis both sounded the player's move correctly; review was
the outlier.


---

## Adding to this file

When you verify an item, move it to **Closed** and note how, in one line, and
when. When a change ships that the suite cannot prove, add it to **Open** in the
same PR that ships the change — not afterwards, when the context is gone.