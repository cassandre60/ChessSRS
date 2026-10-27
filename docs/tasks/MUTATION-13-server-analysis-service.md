# MUTATION-13 — server_analysis_service first audit (Stream 1)

## Premise (re-runnable)

Selected via the queue tool, skipping `pgn_offload.dart` which already has an
open in-flight PR (#432):

```
python3 scripts/autonomous/ledger.py next --stream A
#   NEXT TARGET FOUND: lib/src/model/analysis/server_analysis_service.dart
#   Current source hash: bf4aff1b1 | Mapped test: test/model/analysis/server_analysis_service_test.dart
#   Composite hash:      bf4aff1b1:eb6015bc8
#   Last audited hash:   NEVER
```

First audit. `ServerAnalysisService` owns the lifecycle of a server-analysis
socket for a game or study chapter: it deduplicates repeated requests, keeps
late continuations of a replaced request from writing shared state, absorbs the
one-minute analysis deadline, and merges the server's evaluation tree into the
local one.

## Collision check (2026-10-26)

- Open PRs: none touching `lib/src/model/analysis/server_analysis_service.dart`
  or `test/model/analysis/server_analysis_service_test.dart` (#429–#434 cover
  other files).
- Ledger: the target is `NEVER` audited; no REJECTED/WONTFIX disposition.

## Oracle

```
fvm flutter test test/model/analysis/server_analysis_service_test.dart --concurrency=1
```

Baseline (fresh worktree at `97cc2eccc`, 2026-10-26): 5 tests green, ~9 s per
run including startup.

## Plan

1. Full-window engine run (`--max-mutants 500`, `--timeout 120`, JSON report to
   /tmp — never committed).
2. Triage every survivor by hand: re-apply, red under `--plain-name`, restore,
   `git diff --quiet -- lib/`.
3. Pin real gaps with new tests (each red under the mutant, green on clean
   tree).
4. Round summary table here; ledger row in a SEPARATE protected-path PR.

Class: test-only. `lib/` must end byte-identical to origin/main.

## Results (2026-10-26)

| State | Count |
|---|---|
| Killed (engine, original suite) | 6 |
| Survived → killed by the new tests | 11 |
| Survived → EQUIVALENT (no pin) | 2 |
| Uncompilable (excluded) | 4 |
| Timed out | 0 |

23 candidates; 19 compilable. 6/19 killed before the round, 17/19 after
(89.5%; the two remaining are equivalent). Every one of the 11 pinned mutants
was re-applied by hand and failed its named test before the source was
restored.

Survivor triage:

- **Line 82** (`_socketSubscription != null` → `== null` in the duplicate
  guard): real gap, pinned. A second `requestAnalysis` for the source already
  being watched must reuse the live socket instead of cancelling it and
  reconnecting. Killed by `a repeated request for the same source reuses the
  live socket` (asserts one HTTP request and one channel).
- **Line 83** (`_analysisCompleter != null` → `== null`): same guard, same
  gap, killed by the same test. Both fields are set and cleared together, so
  inverting either one turns the early return into a teardown-and-reconnect.
- **Line 120** (`isAnalysisComplete && !completer.isCompleted` → `||`): real
  gap, pinned. Any progress event would complete the wait, so the first
  partial tree would cancel the analysis. Killed by `an incomplete progress
  event keeps the analysis waiting`, which also asserts that the final event
  does release it.
- **Line 128** (`cancelOnError: true` → `false`): EQUIVALENT. The service
  subscribes to `SocketClient.stream`, and that controller is only ever
  closed (channel errors are consumed inside `SocketClient._onChannelGone`);
  no error event can reach this subscription, so both flag values behave the
  same.
- **Line 144** (`e.statusCode == 400` → `!=`): real gap, pinned. A 400 means
  the game already has an analysis and the socket should still be listened to;
  the inversion turns it into the failure path (cancel + rethrow). Killed by
  `a 400 response keeps listening because the analysis already exists`.
- **Line 198** (`_socketClient?.isDisposed != true` → `== true`): real gap,
  pinned. Normal cancellation leaves the client undisposed and leaked because
  the branch is skipped. Killed by `replacing the analysis disposes the
  previous socket` (asserts the replaced channel is closed).
- **Line 198** (`!= true` → `!= false`): same leak, same test. Both variants
  skip the dispose while `isDisposed` is false.
- **Line 211** (`mate != null` → `== null`): real gap, pinned twice. A mate
  evaluation from the server was dropped; worse, a comment with no evaluation
  at all invented `PgnEvaluation.mate(mate: null)`. Killed by `keeps a mate
  evaluation from the server` and `does not attach an eval comment when the
  server sent no evaluation`.
- **Line 215** (`glyphs?.first` → `last`): pinned. The socket event parser uses
  the first glyph for a node's judgment (`game_socket_events.dart`), so the
  merge takes the first glyph as the node annotation. Killed by `takes the
  first glyph as the node annotation`.
- **Line 217** (`comments?.first` → `last`): pinned for the same reason — the
  first server comment is the node's comment. Killed by `takes the first
  comment of a server node`.
- **Line 225** (`removeWhere((c) => c.eval != null)` → `== null`): real gap,
  pinned. Merging a newer evaluation must replace stale evaluated comments
  while keeping plain text notes; the inversion deletes the notes and keeps
  the stale eval. Killed by `a new evaluation replaces the stale one and keeps
  a plain note`.
- **Line 246** (`children.length > 1` → `>= 1`): pinned. A lone server
  variation must not be created collapsed; only a crowded branch is. Killed by
  `a single new server variation is not collapsed`.
- **Line 277** (`state != source` → `==` in `CurrentAnalysis._listener`):
  EQUIVALENT. `ServerAnalysisSource` is a freezed value type, and Riverpod's
  default `updateShouldNotify` compares with `==`; assigning the same value
  notifies nobody either way, so the guard is an optimisation, not a
  behavioural difference.

No production defect was fixed in this round: `lib/` is byte-identical to
origin/main. 15 tests in the oracle (was 5).

## Observation for a follow-up unit (not changed here)

The game route's fallback side is interpolated as the enum itself:
`'/watch/$gameId/${side?.name ?? Side.white}/v6'` yields
`/watch/<gameId>/Side.white/v6` when the caller omits `side`, because the
fallback stringifies the enum instead of using `.name`. The one production
call site (`analysis_controller.dart`) always passes an orientation, so this
is latent today, but the service's own default path is wrong. A one-line fix
(`?? Side.white.name`) plus a route-level test is a separate bugfix unit; it
is deliberately excluded from this test-only audit so `lib/` stays identical.
