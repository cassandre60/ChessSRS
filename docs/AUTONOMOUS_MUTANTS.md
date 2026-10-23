# Autonomous Mutant Ledger

> One row per surviving mutant. New rows go directly below the header. The
> authoritative row for a mutant id is the newest by **Date** (topmost wins on a
> tie). Rows are append-only: never edit an old row, supersede it with a new one.
>
> A mutant id is `file:line:hash(mutated text, sha256, first 12 hex chars)`.
> `OPEN` is active state and only counts while **Source Hash** still matches the
> file's blob hash at HEAD. `KILLED-BY`, `EQUIVALENT`, `NOISE`, and `WONTFIX` are
> terminal: that exact mutant is never re-reported, even after the file changes.
>
> `EXAMPLE` rows are ignored. Write `—` when there is no PR.

| Date | Mutant ID | Source Hash | Disposition | PR / Issue | Reason |
|---|---|---|---|---|---|
| 2026-10-23 | `lib/src/db/openings_database.dart:43:370fe8648634` | `9f745f2c3` | EQUIVALENT | — | flush only affects durability under crash/power-loss; any subsequent read sees identical bytes, so no test can distinguish - full mapped file green under the mutant |
| 2026-10-23 | `lib/src/db/openings_database.dart:46:fe4942b21d79` | `9f745f2c3` | KILLED-BY | #409 | readOnly:false lets a CREATE TABLE through on the static dataset; the first-run test asserts writes are refused |
| 2026-10-23 | `lib/src/db/openings_database.dart:28:8bcc2db417ad` | `9f745f2c3` | KILLED-BY | #409 | recursive:false on a fresh install leaves ancestors missing; the swallowed create makes directory.list() throw and the provider fails - killed by the first-run test's fresh .dart_tool wipe |
| 2026-10-23 | `lib/src/db/openings_database.dart:28:8bcc2db417ad` | `9f745f2c3` | OPEN | — | Invert boolean literal true -> false |
| 2026-10-23 | `lib/src/db/openings_database.dart:43:370fe8648634` | `9f745f2c3` | OPEN | — | Invert boolean literal true -> false |
| 2026-10-23 | `lib/src/db/openings_database.dart:46:fe4942b21d79` | `9f745f2c3` | OPEN | — | Invert boolean literal true -> false |
| 2026-01-01 | `src/example/service.py:12:abc123def456` | `000000000` | EXAMPLE | — | Delete this row; it is ignored by the parser |
