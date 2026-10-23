# MUTATION-02 — full-window mutation audit of `app_links_service.dart`

**Date:** 2026-10-23
**Stream:** 1 (Mutation Testing & Test-Gap Elimination)
**Class:** test-only (no production code)
**Target:** `lib/src/app_links_service.dart`
**Mapped test:** `test/app_links_service_test.dart`
**Content hash under test:** `git hash-object` = `4d0c5a090` (never audited before;
selected via `ledger.py next --stream 1`, because the catalog's six named targets
are all COMPLETED at their current hashes)

## Engine settings used

```bash
python3 scripts/autonomous/mutation_engine.py \
  --source lib/src/app_links_service.dart \
  --test-cmd "fvm flutter test test/app_links_service_test.dart" \
  --max-mutants 500 \
  --timeout 480 \
  --output-issue docs/tasks/mutant_issue.md \
  --output-json /tmp/mut_app_links.json
```

- `--max-mutants 500` = full candidate window (no 20-mutant first-N cut, per the
  MUTATION-01 lesson: windows hide coverage).
- `--timeout 480` ≈ 10x the measured clean baseline (45.8 s wall), per the
  MUTATION-01 timeout-converts-to-kill false-positive lesson.

## Totals

| Outcome | Count | Share |
|---|---|---|
| Killed by the old suite | 15 | — |
| Survived | 14 | — |
| Uncompilable (excluded) | 14 | — |
| Timed out | 0 | — |
| Kill rate before | 51.7% | 15/29 killable |
| Kill rate after this round | **93.1%** | 27/29 killable |

All 14 uncompilable mutants are the documented null-promotion/noise class
(`== null`/`!= null` inversions and `&&`/`||` swaps that break type promotion on
`context`, `id`, `chapter`, `userName`, `target`, `targetUri`, `routes`,
`topRoute`/`pushed`, `uri`) — no signal, consistent with prior rounds.

## Triage

**12 real gaps — closed by 9 new tests** (22 → 31 tests in the mapped file).
Every closed mutant has a per-mutant red run (`--plain-name` on its killing
test) and the tree was restored and verified byte-identical after each. The
concentration is exactly where coverage was absent: the deep-link **stream**
path (`start()` → `_handleUri`) had only one test (cold-start single-handling),
and `open-web`/`launchUrl` behavior had none.

| Mutant | Gap the survivor exposed | Killing test |
|---|---|---|
| L49 `isColdStart = true → false` | nothing pinned the cold-start **deferral**: a pre-frame link must be held until the navigator exists, not silently dropped on a null context | `a cold-start link arriving before the first frame is deferred until the navigator exists` |
| L52 `isColdStart = false → true` | nothing pinned that a second link is treated as running-app, not cold start | `a cold-start link pushes without a transition, a link while running is animated` |
| L61 running-link `animated: true → false` | nothing pinned the running-link animated transition | same test |
| L76 file/content guard `|| → &&` | a `file:` link with a resolvable path must be skipped (sharing-intent ownership) | `a file link is skipped rather than resolved as a route` |
| L81 shared-pgn `== → !=` | a `org.chesssrs.app://shared-pgn/…` link must be skipped **before** any resolution (SharePlugin owns it) | `a shared-pgn custom-scheme link is skipped before any resolution` |
| L81 shared-pgn `&& → ||` | the skip must be scoped to custom scheme **and** host, not the scheme alone | `a custom-scheme link whose host is not open-web or shared-pgn still navigates` |
| L84 open-web `== → !=` | an `open-web?url=` link must launch the decoded **web** url in the in-app browser | `an open-web link opens the encoded web url and refuses a non-web url` |
| L84 open-web `&& → ||` | the diversion must not capture every custom-scheme link | same as L81-`||` test |
| L91 `allowBrowserFallback: false → true` | app links must never fall back to the browser (the documented browser↔app loop) | `an app link that resolves to nothing never falls back to the browser` |
| L192 non-web refusal `&& → ||` | a valid `https:` url must not be refused | the open-web test |
| L232 `animated = true → false` (default) | linkify navigation must use the normal transition | `navigation from linkified text uses the normal animated transition` |
| L233 `allowBrowserFallback = true → false` (default) | a first-party url with no in-app route must reach the browser from linkified text (INV-008 family) | `a first-party url with no in-app route falls back to the browser from linkified text` |

Additional hardening included with the open-web kill test: the `tel:` refusal
(only web urls are launched — the doc comment's security contract) is asserted
in the same test.

**2 equivalents — full mapped file green under each, recorded EQUIVALENT in
`docs/AUTONOMOUS_MUTANTS.md`:**

- L239 `rootNavigator: true → false`: `currentNavigatorKeyProvider` is the app's
  only navigator (`tab_navigation.dart`), so both flag values resolve the same
  navigator at this call site.
- L299 `return false → true` in `_isFirstPartyUrl`: for a non-http url the
  mutant routes through `handleAppLink`, whose browser fallback launches the
  same url the else-branch launches directly — convergent at the only call site.

## Mechanics worth recording

- A `StreamController(sync: true)` cannot deliver the cold-start link
  pre-frame: an `add()` from `onListen` lands on a microtask after `listen()`
  returns (verified in isolation). The deferral test therefore uses a
  hand-rolled `Stream` subclass whose `listen()` invokes `onData` directly,
  which reproduces the documented "link can arrive before the first frame"
  race the deferral exists for.
- The service's `animated` flag is observable as the pushed route's
  `transitionDuration` (`MaterialScreenRoute.overrideTransitionDuration`); the
  tests assert `Duration.zero` for cold-start pushes and non-zero for
  running-app pushes.
- `url_launcher` is mocked at the platform channel
  (`plugins.flutter.io/url_launcher`), which needs no new dependency and no
  pubspec change.

## Honest status

- Ran: one full-window engine pass (43 mutants + baseline, one targeted test
  file per mutant; source restored and `git diff --exit-code -- lib/` verified
  after every mutant and every hand re-application); 14 per-mutant hand
  re-applications for triage; full mapped file green on clean code (31/31).
- Not run: full suite and CI (belongs to CI per TEST_STRATEGY §2); no runtime
  validation applies (no user-visible change; `lib/` untouched).
- Tests added: 9 (22 → 31 in `test/app_links_service_test.dart`); no product
  code changed.
- Sibling check: `test/app_test.dart` also starts the service (boot-time
  coverage from #393); no other test exercises link resolution.
