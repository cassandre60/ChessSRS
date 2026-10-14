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