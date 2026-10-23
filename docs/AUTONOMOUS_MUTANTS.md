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
| 2026-10-23 | `lib/src/app_links_service.dart:299:d3595af1c9ac` | `4d0c5a090` | EQUIVALENT | — | return true for non-http/unparseable in _isFirstPartyUrl converges with the else branch: onLinkifyOpen launches the same url via the browser fallback either way; full mapped file green under the mutant |
| 2026-10-23 | `lib/src/app_links_service.dart:239:2bbc79d99f0d` | `4d0c5a090` | EQUIVALENT | — | rootNavigator flag: currentNavigatorKeyProvider is the app's only navigator (tab_navigation.dart), so both flag values resolve the same navigator at this call site; full mapped file green under the mutant |
| 2026-10-23 | `lib/src/app_links_service.dart:233:fb71f2b4e15e` | `4d0c5a090` | KILLED-BY | #406 | handleAppLink allowBrowserFallback default true->false: first-party unresolvable url never reaches browser; test asserts launch |
| 2026-10-23 | `lib/src/app_links_service.dart:232:e3023053a534` | `4d0c5a090` | KILLED-BY | #406 | handleAppLink animated default true->false: linkify route asserted non-zero transition |
| 2026-10-23 | `lib/src/app_links_service.dart:192:9b270c652e77` | `4d0c5a090` | KILLED-BY | #406 | non-web refusal &&->\|\| : https url refused, never launched; test asserts launch of encoded https url |
| 2026-10-23 | `lib/src/app_links_service.dart:91:57dc6ddd6304` | `4d0c5a090` | KILLED-BY | #406 | allowBrowserFallback false->true on stream links: tv/blitz would launchUrl (browser loop); test asserts no launch |
| 2026-10-23 | `lib/src/app_links_service.dart:84:5adbf0aef825` | `4d0c5a090` | KILLED-BY | #406 | open-web guard &&->\|\| : custom://widget/editor diverted to open-web; test asserts it still navigates |
| 2026-10-23 | `lib/src/app_links_service.dart:84:16fd7d86573e` | `4d0c5a090` | KILLED-BY | #406 | open-web guard scheme ==->!= : launch never happens; test asserts launch of encoded url |
| 2026-10-23 | `lib/src/app_links_service.dart:81:dbb17c7ca86b` | `4d0c5a090` | KILLED-BY | #406 | shared-pgn guard &&->\|\| : custom://widget/editor would be skipped; test asserts it still navigates |
| 2026-10-23 | `lib/src/app_links_service.dart:81:79d5994c6508` | `4d0c5a090` | KILLED-BY | #406 | shared-pgn guard scheme ==->!= : custom shared-pgn/editor would navigate; test asserts skip before resolution |
| 2026-10-23 | `lib/src/app_links_service.dart:76:4a13ae9a28a3` | `4d0c5a090` | KILLED-BY | #406 | file/content guard && : file:///editor would navigate; test asserts skip |
| 2026-10-23 | `lib/src/app_links_service.dart:61:cecd4a687475` | `4d0c5a090` | KILLED-BY | #406 | running-link animated:true->false: replacement route asserted non-zero transition (same test) |
| 2026-10-23 | `lib/src/app_links_service.dart:52:a24ef2613b82` | `4d0c5a090` | KILLED-BY | #406 | second streamed link re-treated as cold start: no-transition replacement asserted animated (test: pushes without a transition, link while running is animated) |
| 2026-10-23 | `lib/src/app_links_service.dart:49:2efd69590e40` | `4d0c5a090` | KILLED-BY | #406 | cold-start link arriving before the first frame is deferred (test: deferred until the navigator exists) |
| 2026-10-23 | `lib/src/app_links_service.dart:49:2efd69590e40` | `4d0c5a090` | OPEN | — | Invert boolean literal true -> false |
| 2026-10-23 | `lib/src/app_links_service.dart:52:a24ef2613b82` | `4d0c5a090` | OPEN | — | Invert boolean literal false -> true |
| 2026-10-23 | `lib/src/app_links_service.dart:61:cecd4a687475` | `4d0c5a090` | OPEN | — | Invert boolean literal true -> false |
| 2026-10-23 | `lib/src/app_links_service.dart:76:4a13ae9a28a3` | `4d0c5a090` | OPEN | — | Swap logical OR (\|\|) to AND (&&) |
| 2026-10-23 | `lib/src/app_links_service.dart:81:79d5994c6508` | `4d0c5a090` | OPEN | — | Invert equality: '==' -> '!=' |
| 2026-10-23 | `lib/src/app_links_service.dart:81:dbb17c7ca86b` | `4d0c5a090` | OPEN | — | Swap logical AND (&&) to OR (\|\|) |
| 2026-10-23 | `lib/src/app_links_service.dart:84:16fd7d86573e` | `4d0c5a090` | OPEN | — | Invert equality: '==' -> '!=' |
| 2026-10-23 | `lib/src/app_links_service.dart:84:5adbf0aef825` | `4d0c5a090` | OPEN | — | Swap logical AND (&&) to OR (\|\|) |
| 2026-10-23 | `lib/src/app_links_service.dart:91:57dc6ddd6304` | `4d0c5a090` | OPEN | — | Invert boolean literal false -> true |
| 2026-10-23 | `lib/src/app_links_service.dart:192:9b270c652e77` | `4d0c5a090` | OPEN | — | Swap logical AND (&&) to OR (\|\|) |
| 2026-10-23 | `lib/src/app_links_service.dart:232:e3023053a534` | `4d0c5a090` | OPEN | — | Invert boolean literal true -> false |
| 2026-10-23 | `lib/src/app_links_service.dart:233:fb71f2b4e15e` | `4d0c5a090` | OPEN | — | Invert boolean literal true -> false |
| 2026-10-23 | `lib/src/app_links_service.dart:239:2bbc79d99f0d` | `4d0c5a090` | OPEN | — | Invert boolean literal true -> false |
| 2026-10-23 | `lib/src/app_links_service.dart:299:d3595af1c9ac` | `4d0c5a090` | OPEN | — | Invert boolean literal false -> true |
| 2026-01-01 | `src/example/service.py:12:abc123def456` | `000000000` | EXAMPLE | — | Delete this row; it is ignored by the parser |
