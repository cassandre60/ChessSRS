# ChessSRS

**A local-first chess repertoire + spaced-repetition trainer**, built as a
fork of [Lichess Mobile](https://github.com/lichess-org/mobile) (GPL-3.0).

> Give the player a position from their own repertoire and ask them to play
> what they have learned.

- Import your PGN studies (variations, comments, NAGs, custom FENs).
- Review due positions on a Lichess-quality board.
- Spaced repetition schedules what you see next — learned moves return when
  they're due again.
- Everything runs locally; no account, no network on the training path.

**Website:** <https://cassandre60.github.io/chesssrs-site/> — downloads for
Linux and Android, a live interactive demo, and FAQ.

## Status

The local-first review loop has shipped to the owner for beta use; work is in
Phase 6 refinement. Lichess study import, opening hubs, practice and three
selectable schedulers are implemented. `IMPLEMENTATION_PLAN.md` is the delivery
and evidence ledger; this summary is not a fresh runtime-verification claim.

## Development

```bash
fvm flutter pub get
fvm dart run build_runner build # required in a fresh worktree before compiling
fvm flutter analyze <touched paths>
fvm flutter test <affected test file> --concurrency=1
fvm flutter run -d linux
```

Full suites and release builds run in CI, not locally. See `TEST_STRATEGY.md`
for the bounded local loop and `AGENTS.md` for worktree isolation.

## Support

Building small, useful software — if this project saves you time, consider [buying me a coffee](https://buymeacoffee.com/cassandre60) to help keep it maintained.

<a href="https://buymeacoffee.com/cassandre60"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" width="150" alt="Buy Me A Coffee"></a>

## Licensing

ChessSRS is a fork of Lichess Mobile and is licensed under the **GNU GPL
v3** — see `LICENSE` and `COPYING.md`. Lichess Mobile copyright and license
notices are preserved.

Domain behavior is informed by studying (not copying)
[listudy](https://github.com/ArneVogel/listudy) (AGPL-3.0, behavioral
reference only) and [chessrs](https://github.com/ZackMurry/chessrs)
(GPL-3.0). See `docs/INTEGRATION_MAP.md`.

## Documentation

Start with [the authority map](docs/documentation-map.md): one home per rule,
with links to product scope, architecture, SPEC invariants, verification,
delivery status and agent instructions.
