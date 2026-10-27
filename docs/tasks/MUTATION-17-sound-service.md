# MUTATION-17 — mutation audit of `sound_service.dart`

**Date:** 2026-10-27
**Stream:** 1 (Mutation Testing & Test-Gap Elimination)
**Class:** test-only + one behavior-preserving seam extraction
**Target:** `lib/src/model/common/service/sound_service.dart`
**Mapped test:** `test/model/common/service/sound_service_test.dart`
**Hashes:** source before the audit `79be951af` (never audited before; selected
via `ledger.py next --stream A`), source after the seam `a32be34e2`, mapped test
`dbb9d88a1`.

## Engine settings used

```bash
python3 scripts/autonomous/mutation_engine.py \
  --source lib/src/model/common/service/sound_service.dart \
  --test-cmd "fvm flutter test test/model/common/service/sound_service_test.dart --concurrency=1" \
  --max-mutants 500 \
  --timeout 150 \
  --output-json .autonomous/mut_sound_service.final.json \
  --output-issue .autonomous/mutant_issue_sound_service.md
```

## Totals

| Outcome | Count (round 1) | Count (final) |
|---|---|---|
| Killed by the old suite | 4 | 12 |
| Survived | 16 | 8 |
| Closed by new tests | — | 8 |
| Uncompilable (excluded) | 3 | 3 |
| Timed out | 0 | 0 |
| Kill rate (killable = 20) | 20.0% | 60.0% |

The mapped file grew from 3 to 8 tests.

## Seam change (behavior-preserving)

Round 1 showed that `changeTheme` loads sounds through the process-wide
`_linuxSoundPlayer` singleton, so the documented test seam
(`SoundService.linuxPlayer`) only covered playback, never the load path. The
change passes the same instance down: `_loadSound`/`_loadAllSounds` take an
optional `LinuxSoundPlayer` that defaults to the singleton, and `changeTheme`
passes `_linuxPlayer` (which itself defaults to the singleton). Production
behavior is identical; only the test-visible route changes. Precedent: the
`offloadsAt` extraction in PR #441.

Fail-to-pass for the seam: the new `changeTheme` test is **red** against
`origin/main`'s `sound_service.dart` (it observes zero loads) and green with the
seam in place.

## Killed (8 new mutants)

| Mutant (line) | Gap closed | Killing test |
|---|---|---|
| L43 `== → !=` (iOS extension) | Linux must request the `mp3` asset, not `aifc` | `changeTheme reloads every sound of the theme ...` |
| L150 `== → !=` (`_loadSound` platform branch) | Linux loads must reach the Linux backend, not the plugin | same test |
| L201 `>= → >` (volume lower bound) | a per-request volume of `0.0` is legal and resolves to silence | `play accepts the inclusive volume bounds ...` |
| L201 `&& → ||` (weakened bounds assert) | out-of-range volumes must be rejected, never amplified | same test |
| L204 `|| → &&` (sound gate) | enabled-and-nonzero must not be required together | pre-existing test (killed before) |
| L204 `== → !=` (sound gate) | zero master volume drops the request | pre-existing test |
| L207 `== → !=` (play platform branch) | Linux playback goes through the injected backend | pre-existing test |
| L223 `== → !=` (atomic capture) | only the atomic variant explodes | `playCaptureSound maps the atomic variant ...` |
| L231 `false → true` (`playSound` default) | `changeTheme` must not preview by default | `changeTheme ... plays nothing by default` |
| L232 `== → !=` (`changeTheme` platform branch) | the previous theme is released on the Linux backend | same test |
| L249 `== → !=` (`release` platform branch) | `release` reaches the Linux backend | `release releases the Linux backend` |

Each killed verdict is the engine's own red run on the mutated source; the tree
was restored byte-identical after each mutant (verified by the source hash).

## Open survivors (8, documented)

- **L71 `|| → &&`, L72 `true → false`, L76 `== → !=`, L78 `false → true`**
  (`_hasCmd`): command discovery hardcodes `/usr/bin` and `/usr/local/bin` and
  depends on which of `pw-play`/`paplay`/`aplay` the host has. `_hasCmd` is
  private and there is no injectable probe or path root, so a hermetic test
  would need a new filesystem/exec seam in `lib/`. Not pinned in a test-only
  audit; flagged as a follow-up seam if command selection ever regresses.
- **L86 `recursive: true → false`** (`createSync`): equivalent — the parent is
  `Directory.systemTemp`, which always exists, so a single-level create
  succeeds either way.
- **L91 `flush: true → false`** (`writeAsBytes`): equivalent for observable
  behavior — the following `Process.run` reads through the page cache; `flush`
  only changes crash durability, not the bytes a completed read sees.
- **L101 `_playerCmd == null → != null`** (`play` early return): both forms
  return early when no sound path is loaded, and populating `_soundPaths`
  requires the real player's `load` (writes under `/tmp`). No hermetic seam
  without exposing private state.
- **L185 `== → !=`** (`initialize` platform branch): operates on the
  process-wide singleton and only decides whether `_playerCmd` is set; it is
  observable only by spawning a real audio process. Needs a singleton seam.

## Mechanics worth recording

- `_loadSound`/`_loadAllSounds` are top-level private functions; until this
  change they always used the process-wide player, so injecting
  `SoundService.linuxPlayer` did not cover loads.
- `Sound` has 10 values and every `assets/sounds/standard/<id>.mp3` exists, so a
  `changeTheme` test can assert a full 10-sound load without fixtures.
- `play` asserts the inclusive `[0.0, 1.0]` volume bounds; `0.0` is a supported
  per-request mute (dropped by the resolved-volume guard, not the assert).
- Both `.aifc` and `.mp3` exist for every sound; the platform decides which is
  requested.
