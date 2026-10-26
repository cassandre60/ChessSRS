# MUTATION-14 — Stream 1 mutation audit: `lib/src/model/auth/auth_controller.dart`

Claimed 2026-10-26 (branch `test/mutation-auth-controller`, draft PR at claim
time). First unclaimed target from `ledger.py next --stream A` after the
in-flight MUTATION-09..13 rounds.

## Scope

- Target: `lib/src/model/auth/auth_controller.dart` (174 lines at claim hash
  `97cc2eccc`).
- Oracle: mapped test `test/model/auth/auth_controller_test.dart` (260 lines).
- Engine round: `mutation_engine.py --source <target> --test-cmd "fvm flutter
  test <oracle> --concurrency=1" --max-mutants 22` (seed + shard recorded in
  the run JSON).

## Protocol (per `docs/AUTONOMOUS_IMPROVEMENT_CATALOG.md` Stream 1)

1. Baseline green before mutating; a red baseline aborts the round.
2. Every survivor triaged: real gap → fail-to-pass test (red under the
   mutant via `--plain-name`, green on the restored tree), equivalent →
   documented in `docs/AUTONOMOUS_MUTANTS.md`, noise → recorded as such.
3. `lib/` ends byte-identical unless a survivor demands a behavior-preserving
   extraction to make a boundary pinnable (documented in the PR if so).
4. This PR carries the audit changes; the ledger row lands in its own docs PR.

## Collision log

- Claim time: no open PR or worktree touched the target (#431–#435 cover
  pgn_importer, pgn_offload, account_repository, forecast, server_analysis).
- 2026-10-26: `chesssrs-mutation-next-target` was found occupied by another
  round (account_repository, MUTATION-11) — this round moved to its own
  worktree; the collision and recovery are disclosed on #433.

## Round results (engine run 2026-10-26 ~10:05Z, owning session)

19 candidates: 10 killed, 8 survived, 1 uncompilable — a 55.6% kill rate
against the mapped suite. The owning session stalled on repeated
`provider.transport` timeouts after triaging the survivors but before any
killer test landed (only the fake-storage seam was written); the round was
completed by the resume wake in this same worktree/branch. The engine's
verdict cache was not persisted, so every survivor below was re-verified
empirically with an applied-mutant red proof instead of the cache.

## Survivor disposition (8 survivors, four families + one out-of-mapping)

- L26 `isLoggedInProvider` select inversion (`!= null` → `== null`) — real
  gap: no test read the boolean's value. Killed by `isLoggedInProvider tracks
  the signed-in state`.
- L81 `_onSignedIn` second fence (`||` → `&&`) — real gap: the existing
  in-flight tests never park a sign-in inside its own storage write, the only
  window where the second fence runs after the first one passed. Killed by
  `a stale sign-in parked mid-write does not clobber the newer session`
  (FIFO write gates stage the generation bump during the write; under the
  mutant the superseded session clobbers the state mid-test).
- L107 signOut final fence (`||` → `&&`) — real gap: the existing
  "sign-in during sign-out delay" test returns at the delay fence and never
  reaches the final one. Killed by `a stale sign-out parked mid-delete does
  not clear the newer session` (a delete gate stages the bump past both
  earlier fences).
- L138/L142 checkToken fences (`||` → `&&`; both operators, both lines — four
  mutants) — real gap: the existing invalid-token test only exercises the
  token-mismatch clause. Killed by `a stale token check for the unchanged
  session does not clear it` (L138 variants: generation stale, token still
  matching) and `checkToken does not clear state when the generation bumps
  during its delete` (L142 variants: bump staged inside the storage delete);
  the `deleteCalls` assertion additionally catches L138 variants that clear
  storage without reaching `state`.
- L167 `startupTokenCheckProvider` null-path inversion (`==` → `!=`) — not a
  mapped-suite gap: `test/model/auth/startup_token_check_test.dart` already
  kills it, but that file sits outside the engine's mapped-test kill
  criterion. Disposition: covered by an existing oracle file; no new test.

## Fail-to-pass proof

Baseline: 11/11 green on clean source (`fvm flutter test
test/model/auth/auth_controller_test.dart --concurrency=1`). Each mutant was
applied to the source and reverted: every killer test ran red under its
mutant and green on the restored tree, L138/L142 proven per single-operator
variant (four runs). Spot check: under the L81 mutant the mid-test state
reads the superseded session (userC over userA) — the predicted clobber.
`lib/` ends byte-identical; format and analyze clean on both touched files.
