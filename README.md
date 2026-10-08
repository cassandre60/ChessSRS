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

## Status

Foundation phase — the app is the Lichess Mobile foundation with product
specifics under active development. See `IMPLEMENTATION_PLAN.md`.

## Development

```bash
fvm flutter pub get
dart run build_runner build     # after model/codegen changes
fvm flutter analyze
fvm flutter test
fvm flutter run -d linux
```

`./verify` runs the quality gate (analyze + tests).

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

- `PRODUCT.md` — product definition
- `MVP.md` — current scope
- `ARCHITECTURE.md` — foundation + domain boundary
- `QUALITY.md` — invariants
- `CUT_PROPOSALS.md` — Lichess foundation trim map
- `docs/INTEGRATION_MAP.md` — Listudy/chessrs extraction plan
