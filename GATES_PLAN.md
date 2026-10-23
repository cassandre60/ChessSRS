# Gate Roadmap

Protected path. Authority: planned enforcement, promotion criteria and accepted
omissions. GATES owns the current registry, SPEC the exact invariants,
TEST_STRATEGY the verification workflow. See `docs/documentation-map.md`.

## 1. Baseline versus current state

The original 2026-10-01 proposal is preserved in git history. Its "missing
CODEOWNERS/traceability/ratchets/corpus" baseline is no longer current:
CODEOWNERS, protected paths, PR template, banned-API boundary enforcement,
SPEC traceability, tripwire, ratchets and nightly red-team recall are installed.
Definitions are in GATES and executable config, not repeated here.
Ratchet values live in `.gates/ratchet-baseline.json`, not this roadmap.

## 2. Risk prioritization

| Risk | Modules | Priority |
|---|---|---|
| R0 loss/corruption/security | persistence, migrations, import, auth secrets | durability, quarantine, migrations, redaction |
| R1 wrong behavior | schedulers, graph coordinator, review/session orchestration | deterministic and model/property/differential proofs |
| R2 degraded UX/performance | presentation, design, noncritical glue | widget/a11y evidence and measured performance |
| R3 generated | Freezed/JSON/l10n output | verify inputs/toolchain; raw output policy in CLAUDE |

Risk labels R0–R3 differ from SPEC's T0–T2 severity and GATES's T0–T3
execution-cost tiers. They are not interchangeable rankings.

## 3. Remaining work (not running acceptance gates)

| Work | Current limit | Promotion requirement |
|---|---|---|
| Blocking diff-scoped mutation CI | Hand-picked catalogue/audit campaigns; t2 wrapper only names scheduler tests | Prove matching test selection; two green runs without false positives before blocking |
| Crash-consistency at write boundaries | Rollback/reopen/upgrade tests exist; no process-kill-at-every-boundary campaign wired | Bounded fixtures; prove detection; nightly first |
| PGN fuzz campaigns | Example/property/round-trip tests, not a long-running fuzz lane | Deterministic seeds/minimized failures; nightly first |
| Pinned-runner performance budgets | Small-path latency oracle; no device/tail guarantee | Reliable instrument/dataset/spread before ratcheting; settle Q8 |
| Gate-health review | Table in GATES; no measured quarterly summary yet | Review rejection/false-positive/escape evidence; retain useful gates |

Autonomous mutation work/dispositions are indexed by
`docs/AUTONOMOUS_WORK_LEDGER.md`; do not infer campaign coverage from a mutant's
presence in `.gates/mutants.json`.

## 4. Deliberate omissions and constraints

- No unproved blocking mutation job: false positives can stall every PR.
- No blanket Random ban: session randomness is injectable/seeded in tests;
  production fallback is allowed, not a scheduler randomness license.
- No feature-punishing LOC diet: source-size tolerances live in ratchets.
- No duplicate analyzer job in gates.yml: Tests owns the product suite.
- No ownership-by-GitHub-identity claim: owner/agents share one account;
  consent is operational, not identity enforcement (open-questions Q5).
- Protected changes stay separate from product code. Schema/identity/format
  changes need accepted contracts and migration evidence, not speculative
  invariants without live oracles.

Shape spoilers are no longer a future SPEC candidate: INV-063 exists.
Advisory engine isolation remains a QUALITY constraint; stronger mechanical
enforcement is future work, not permission to block imports.
