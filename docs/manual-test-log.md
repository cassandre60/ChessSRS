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

### 1. Review moves now make a sound (#93, `c00856c36`)

**What was broken.** Review training played a sound for the opponent's auto-reply
and for an animated pre-move, and nothing at all for the move you make. Every
position you actually played was silent, with no haptics either. Study and
analysis both sounded your move correctly; review was the outlier.

**What the tests prove.** That the sound service is *asked* for the right sound
on a user move, and for `Sound.capture` specifically on a capture. Both tests
were confirmed to fail on the pre-fix controller.

**What only you can check.** That something is actually audible, and that it
lands at the same moment as the piece moving rather than after the database
work. A fake sound service passes identically whether or not your speakers are
on, the volume is at zero, or the audio session is broken.

**How to test it.** Open Settings → sound, pick a theme, set volume above zero.
Then:

1. Start a review session from any imported repertoire.
2. Move a piece. You should hear the move sound *as* the piece lands.
3. Play a **capture** — it should sound different from a plain move.
4. Play a **check** — you should feel a slightly heavier buzz if haptics are on
   in Settings.
5. Move a piece the wrong way on purpose. It should still sound: the piece moved,
   and silence would be wrong.
6. Turn sound off in Settings and repeat. It should be silent.

**Not yet checked:** whether the capture sound feels distinct enough from the
plain move sound in practice, and whether the haptic on a check is noticeable
without looking at the phone.

---

## Closed

_Nothing yet — this section fills in as items are confirmed._

---

## Adding to this file

When you verify an item, move it to **Closed** and note how, in one line, and
when. When a change ships that the suite cannot prove, add it to **Open** in the
same PR that ships the change — not afterwards, when the context is gone.