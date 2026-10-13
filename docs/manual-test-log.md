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

_Nothing outstanding. The first entry has been verified; add the next one here as
it ships._


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