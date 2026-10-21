# Documentation reconciliation — 2026-10-21

Class: spec-change/documentation only. No product source, tests, gate scripts,
CI configuration, ratchets, dependencies or INV clauses changed.
Owner approved this documentation-only diff and publication on 2026-10-21.
Remote verification remains pending; Q7–Q10 are not settled by that approval.

## Scope and method

Read README, PRODUCT, MVP, ARCHITECTURE, QUALITY, SPEC, TEST_STRATEGY,
IMPLEMENTATION_PLAN, GATES, GATES_PLAN, scheduling architecture, AGENTS and
CLAUDE in full, plus their cut/integration/decision and open-question records.
Checked factual conflicts against source, test bodies, config, workflow paths
and live required-check settings at base `47364d99c`.
No Flutter builds, codegen, full suites or mutation campaigns were run locally
for this Markdown-only change. Source inspection is not runtime verification.

## Findings and dispositions

| Conflict / stale statement | Evidence | Reconciliation / authoritative home |
|---|---|---|
| README: foundation phase | IMPLEMENTATION_PLAN V6, beta delivery 2026-09-16, Phase 6 | README is a status summary linking the delivery ledger |
| MVP: PGN-only import, hubs later, orientation later, Lichess visual theme | Ledger B4/R7/R8/R12/R14; current importer/preferences; PRODUCT Diagram section | MVP is current beta scope, not an obsolete original phase plan |
| PRODUCT: independent state per occurrence | canonicalKeyForPosition and PositionKnowledgeState; INV-016/017/030 | Shared question memory; exact identity in ARCHITECTURE §5 |
| PRODUCT: only due work, while fresh/full-line review ships | INV-068 and P-CONTINUITY, preferences | Journey prose acknowledges both; exact behavioral contracts remain SPEC-owned |
| SPEC absent from AGENTS authority chain; QUALITY repeats it | Both full documents | Protected AGENTS §1 owns the subject-based authority map; documentation-map is only a pointer; SPEC owns numbered rules, QUALITY retains additional constraints |
| ARCHITECTURE: 23 files, schema v15, two migrations, three view→DB exceptions | database.dart is v20; multiple later upgrade paths; view import search returns none | Remove hand-counted inventory/line numbers; source owns versions; module map retains entry points |
| ARCHITECTURE/report: first-move or complete-set key without trained side | position_knowledge_state.dart canonicalKeyForPosition | ARCHITECTURE owns side + FEN4 + complete sorted UCI set; legacy key explicitly distinguished |
| Report: reject/deprecate selectable ladder schedulers | StudyPrefs default simple; schedulerProvider switch | No deprecation approved; three selectable kernels described |
| Report: four-button latency pseudocode versus binary D015 | FsrsRating enum and schedule accept only binary ReviewResult | Replace copied implementation with current math/source pointers |
| Report: single answer, incompatible same-FEN sets are import errors | INV-017 and complete-set key | Different questions are valid independent memories |
| Report: FSRS-5/drop-in optimizer, confusion registry, cold priors, tournament controls | Kernel says FSRS-4.5-style; coordinator/StudyPrefs omit proposed registry/controls | Math is current; unsupported features/empirical claims clearly proposals, not scope |
| Report prose has fixed depth exponent but copied code has old exponent | Coordinator exp(-(depth-1)/tau), params, throttle map | Remove stale copied code; retain formula and parameter source |
| Full local verify before commits/offline exception | AGENTS budget/global machine-safety instruction versus TEST_STRATEGY and README | TEST_STRATEGY alone owns narrow local loop; full suites/release builds remote |
| CI calls verify / local wrapper is identical trusted execution | test.yml calls individual steps; gates.yml uses trusted base; gates.sh uses checkout | Describe actual distinction without modifying workflows |
| AGENTS: docs skip CI, GATES uses workflow name as required context | Both workflows match Markdown; live protection contexts Tests/T1 fast gates | Correct current facts; CI configuration unchanged |
| GATES_PLAN: proposal, no CODEOWNERS/citations/corpus | CODEOWNERS, .gates, scripts/gates, redteam, SPEC present | Installed baseline separated from future work; no claims planned gates run |
| G06 covers six scheduler boundaries | .gates/mutants.json includes state/graph mutants; t2 only runs scheduler_test | Expanded catalogue does not imply full wrapper coverage; blind spot reported, not silently fixed |
| l10n formatting workaround / all generated files uncommitted | .gitignore, l10n.yaml format:false, git-tracked l10n, supersession lesson | CLAUDE owns raw committed l10n versus ignored Freezed/JSON |
| Fixed-80ms controller flake advice still current | Ledger task19/#52; controller now uses shared polling helper | Old incident archived; diagnose actual timing failures, not cached explanation |
| Firebase kept/grey, clock tool kept, WidgetKit/FCM current | CUT tables, absent dependencies/directories; D017 history | Explicit supersession and removal; no restore authorization |
| P-SYNC blocked because current Firebase points at Lichess | Firebase removed; backend remains undecided | Deferred sync remains; obsolete explanation superseded |
| Release versus Release proof conflated; major stays 0 despite v1 tags | Both release.yml and release-proof.yml exist; the latter always uses a throwaway key; tag series | docs/releases.md distinguishes publishing/dry-run from throwaway proof; no release for docs |
| AGENTS always-loads 600+ lines of incidents plus duplicated policies | Full AGENTS, external §3.1/§10 references | Short router preserves section anchors; archive retains every older incident with warning |

## Unresolved contracts (no automatic decision)

- Q7 / INV-060: study versus repertoire in screen-reader announcement; design
  docs also disagree. Existing owner question retained.
- Q8 / INV-050 versus QUALITY §4.1: budget scope and percentile/device evidence.
- Q9 / INV-025: FSRS repetition preservation versus universal streak-reset prose.
- Q10 / INV-068: stored null-date states intentionally due versus scheduled-date prose.

These remain in docs/open-questions.md; invariant clauses and tests are untouched.
They need separate explicitly approved contract/behavior work, not a reconciliation
that rubber-stamps whatever code happens to do.

## Review checklist

- Each normative subject has one home in protected AGENTS §1; documentation-map
  is a navigation pointer, not a new unprotected authority.
- SPEC IDs/oracle clauses preserved; no assertions/gates/budgets relaxed.
- Historical ledger and incident evidence retained and visibly superseded.
- Local validation: git diff --check, invariant-definition/citation checks and
  local path checks; results reported with the draft, not invented CI evidence.
- G07 rejected the unapproved committed diff; after owner consent the local
  approved fast check passed. The protected-path guard was not changed.
- Owner consent covers publishing/labeling this documentation-only change;
  unresolved behavioral contracts need separate decisions.
- No release: the outcome is documentation/agent navigation, not app behavior.

## Observed local validation

- `git diff --check`: clean.
- Exact comparison of SPEC from `## A.` to EOF against the base: identical,
  including all invariant clauses, IDs, oracles and change-log rows.
- Markdown fence pairing, relative Markdown links and authority-map home paths:
  checked; no missing targets in the checked set. This is not a rendered-doc pass.
- `python3 scripts/gates/spec_trace_check.py --spec SPEC.md --tests test`:
  **45 invariants / 45 referenced**. This is traceability, not behavioral proof.
- `python3 scripts/gates/banned_apis_check.py --config .gates/banned-apis.json --root .`:
  **clean**. Product code is unchanged.
- Full remote suite and independent red-team recall: pending; no local wide run.
- After merging current origin/main without conflicts, `APPROVED=1
  ./scripts/gates.sh t1` passed: G03 clean, G07 approved under explicit owner
  consent, G08 clean, G05 45/45, G10 ratchet OK. No local Flutter run.
