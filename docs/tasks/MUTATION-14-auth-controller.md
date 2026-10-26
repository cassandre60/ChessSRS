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
