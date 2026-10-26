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
| 2026-10-25 | `lib/src/domain/graph_aware_review_coordinator.dart:220:12fb3662d6e0` | `7f64f687a` | EQUIVALENT | — | line 220 'remainingMs > 0' -> '>=': the branches are value-identical at the only boundary they can diverge (remainingMs == 0): currentDue.add(Duration(milliseconds: (0*0.08).round()=0)) == currentDue; no call site can construct a sub-millisecond remaining (both operands are whole-ms DateTimes via .difference().inMilliseconds), so no observable input distinguishes mutant and original. Overdue/negative remainingMs unchanged; granted path verified by the 16 mapped tests. |
| 2026-10-25 | `lib/src/domain/graph_aware_review_coordinator.dart:220:12fb3662d6e0` | `7f64f687a` | OPEN | — | Loosen strict inequality: '>' -> '>=' |
| 2026-10-26 | `lib/src/design/srs_toast.dart:43:06049ceac9fe` | `dfbdd83a8` | KILLED-BY | #427 | rootNavigator literal on the Navigator fallback: killed by testWidgets 'a navigator-key context past a LookupBoundary still resolves to the root' (red under the mutant, green on clean source). An earlier EQUIVALENT call (context with no overlay ancestor must be the rootmost navigator) was refuted by the round's refutation pass: an app-placed LookupBoundary clips Overlay.maybeOf's marker walk (lookup_boundary.dart boundary.depth > candidate.depth), so a nested navigator's own key context can reach the fallback with overlays above it -- and Navigator.maybeOf's ?? asymmetry then makes rootNavigator:false take the context-owned navigator where true takes the rootmost ancestor. Both flag values are observable; the mutant files the toast inside the clipped subtree. |
| 2026-10-26 | `lib/src/design/srs_toast.dart:43:06049ceac9fe` | `dfbdd83a8` | EQUIVALENT | — | rootNavigator literal on the Navigator fallback: no constructible input distinguishes the flags. The fallback runs only when Overlay.maybeOf finds no OverlayState above the context; every nested navigator's context sits below the root overlay, so the only navigator context with no overlay ancestor is the rootmost navigator itself, where nearest and rootmost resolve to the same NavigatorState and both flags return the identical overlay. |
| 2026-10-26 | `lib/src/design/srs_toast.dart:42:4b762721ee5b` | `dfbdd83a8` | KILLED-BY | #427 | rootOverlay literal on the Overlay lookup: killed by testWidgets 'renders in the root overlay even from inside a nested navigator' (red under the mutant, green on clean source). A context below a nested navigator's overlay resolves to the rootmost overlay on clean source; the mutant files the toast into the nested subtree, under the shell chrome. |
| 2026-10-26 | `lib/src/design/srs_toast.dart:42:4b762721ee5b` | `dfbdd83a8` | OPEN | — | Invert boolean literal true -> false |
| 2026-10-26 | `lib/src/design/srs_toast.dart:43:06049ceac9fe` | `dfbdd83a8` | OPEN | — | Invert boolean literal true -> false |
| 2026-10-24 | `lib/src/domain/scheduler.dart:228:409de8b11d1d` | `e91aa7578` | EQUIVALENT | 417 | dueItems has no production caller (test-only convenience helper); no INV or call site observes the returned list growability; flipping it cannot change behavior any contract names |
| 2026-10-24 | `lib/src/domain/scheduler.dart:163:e75d7151670d` | `e91aa7578` | EQUIVALENT | 417 | Same clamp expression as line 63 in EaseScalingScheduler; identical reasoning - all call sites are ms-precision, boundary equality returns the identical Duration value |
| 2026-10-24 | `lib/src/domain/scheduler.dart:63:e75d7151670d` | `e91aa7578` | EQUIVALENT | 417 | Clamp compares at ms granularity; every caller constructs d via Duration(milliseconds:) or whole-day constants and stability round-trips through .inMilliseconds, so a sub-ms duration never reaches the clamp; when inMilliseconds are equal the two branches return value-identical Durations |
| 2026-10-24 | `lib/src/domain/scheduler.dart:63:e75d7151670d` | `e91aa7578` | OPEN | — | Loosen strict inequality: '>' -> '>=' |
| 2026-10-24 | `lib/src/domain/scheduler.dart:163:e75d7151670d` | `e91aa7578` | OPEN | — | Loosen strict inequality: '>' -> '>=' |
| 2026-10-24 | `lib/src/domain/scheduler.dart:228:409de8b11d1d` | `e91aa7578` | OPEN | — | Invert boolean literal false -> true |
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
