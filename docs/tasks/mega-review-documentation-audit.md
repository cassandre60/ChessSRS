# Documentation & Knowledge Management Audit

**Date:** 2026-11-17  
**Scope:** All 158 `.md` files across the ChessSRS repository  
**Method:** Source inspection of every markdown file, cross-referencing authority
claims, link targets, and freshness against live repository state.

---

## Executive Summary

ChessSRS has an unusually thorough documentation system for a project of its size.
The authority-map pattern (AGENTS.md §1) is well-designed and effectively
prevents the "competing truths" failure mode. However, the documentation has
grown organically to **91 files in `docs/` alone (1.15 MB)**, creating a
significant discovery burden. Roughly 40% of the docs/ content is historical
audit/incident records with diminishing active value. The root-level normative
documents (SPEC, ARCHITECTURE, PRODUCT, MVP, QUALITY, GATES) are high-quality.
Several shadow documents in `docs/` duplicate their root counterparts and risk
confusion.

**Key numbers:**  
- 158 total `.md` files; 91 under `docs/`; 15 root-level; 10 in `design/docs/`
- 20 TODO/FIXME/HACK comments in `lib/` (all inherited Lichess code)
- 1 confirmed broken file reference (D020 → `FEAT-REP-43`)
- 10 shadow/duplicate documents that compete with root normative homes
- 3 open SPEC conflicts (Q12, Q13, Q14) awaiting owner decisions
- Domain code has good doc-comment density (avg 20+ `///` per file)

---

## 1. Document Inventory & Categorization

### 1.1 Root-Level Normative Documents (15 files)

| File | Category | Lines | Health |
|---|---|---|---|
| `AGENTS.md` | Normative — agent ops | 209 | ✅ Well-maintained; authority map is the gold standard |
| `SPEC.md` | Normative — behavioral contract | 503 | ✅ Excellent; every INV falsifiable with oracle/gates |
| `ARCHITECTURE.md` | Normative — boundaries | 147 | ✅ Clean; hand-counted inventory removed in reconciliation |
| `PRODUCT.md` | Normative — product intent | 135 | ✅ Clear vision; board-only FEN truth principle elevated |
| `MVP.md` | Normative — scope | 56 | ✅ Concise; well-scoped |
| `QUALITY.md` | Normative — constraints | 57 | ✅ Correctly defers to SPEC for numbered rules |
| `GATES.md` | Normative — gate registry | 109 | ✅ Rich; escapes log is exemplary |
| `GATES_PLAN.md` | Normative — planned gates | 57 | ✅ Correctly separates planned from running |
| `TEST_STRATEGY.md` | Normative — verification | 128 | ✅ Enforcement matrix is test-parsed |
| `IMPLEMENTATION_PLAN.md` | Normative — delivery ledger | 1173 | ⚠️ Very long; phases 0-5 are purely historical |
| `CLAUDE.md` | Normative — conventions | 432 | ✅ Comprehensive setup and conventions guide |
| `CUT_PROPOSALS.md` | Normative — cut ledger | 413 | ✅ Clear supersession trail |
| `ChessSRS Scheduling Architecture.md` | Normative — math | 187 | ✅ Correctly separated from SPEC |
| `CODING_STANDARDS.md` | Guide — standards | 86 | ⚠️ Partially overlaps CLAUDE.md |
| `Chess_Repertoire_SRS_Product_Blueprint.md` | Historical — early blueprint | 1169 | ⚠️ Opens with "do not read by default"; 1169 lines of superseded content |

### 1.2 Shadow Documents in `docs/` (Compete with Root Homes)

These files cover the same subject as their root normative counterpart and risk
causing confusion, even when they carry a redirect notice:

| `docs/` file | Root counterpart | Lines | Assessment |
|---|---|---|---|
| `docs/architecture.md` | `ARCHITECTURE.md` | 133 | ❌ No redirect banner. Stale: mentions "suggested fields" |
| `docs/product.md` | `PRODUCT.md` | 113 | ✅ Has redirect banner; still unnecessary clutter |
| `docs/design.md` | `design/README.md` | 100 | ⚠️ Redirect to design/docs, but adds its own rules |
| `docs/testing.md` | `TEST_STRATEGY.md` | 85 | ❌ No redirect banner. Stale parallel testing doc |
| `docs/performance.md` | `QUALITY.md` §4 | 77 | ❌ No redirect. Duplicate performance contract |
| `docs/coding_style.md` | `CLAUDE.md` / `CODING_STANDARDS.md` | 64 | ❌ No redirect. Inherited Lichess coding style |
| `docs/domain-model.md` | `ARCHITECTURE.md` §3 | 119 | ❌ No redirect. "Suggested fields" era document |
| `docs/review.md` | `SPEC.md` §C/PRODUCT §4 | 256 | ❌ No redirect. Large, stale review engine doc |
| `docs/roadmap.md` | `MVP.md` / `IMPLEMENTATION_PLAN.md` | 72 | ❌ No redirect. "Phase 1 — MVP" era roadmap |
| `docs/inspiration.md` | `docs/INTEGRATION_MAP.md` | 51 | ⚠️ Overlaps integration map's reference repos |

**Recommendation:** Add redirect banners to all shadow documents pointing to
their normative home, or archive them under `docs/archive/`.

### 1.3 Active Operational Documents (19 files)

| File | Category | Health |
|---|---|---|
| `docs/decisions.md` | ADR log (D001–D020) | ✅ Comprehensive; supersession explicit |
| `docs/open-questions.md` | Owner decision queue | ✅ Well-structured; Q7/Q8/Q12-14 open |
| `docs/documentation-map.md` | Navigation pointer | ✅ Correctly defers to AGENTS §1 |
| `docs/documentation-reconciliation.md` | Reconciliation report | ✅ Excellent record |
| `docs/INTEGRATION_MAP.md` | Reference provenance | ✅ Clear extraction boundaries |
| `docs/ESCAPE_TO_GATE.md` | Escape procedure | ✅ Protected path; procedure well-defined |
| `docs/releases.md` | Publishing mechanics | ✅ Clear; version stamping defined |
| `docs/manual-test-log.md` | Device evidence | ✅ Active; uncovered checks tracked |
| `docs/performance-handoff.md` | Perf findings | ✅ Active; measurements attributed |
| `docs/tech-debt-inventory.md` | Tech debt register | ⚠️ Dated; needs freshness check |
| `docs/AUTONOMOUS_IMPROVEMENT_CATALOG.md` | Autonomous ops | ✅ Active; subordinate to AGENTS |
| `docs/AUTONOMOUS_WORK_LEDGER.md` | Work ledger | ✅ 161KB — actively used but very large |
| `docs/AUTONOMOUS_MUTANTS.md` | Mutant ledger | ✅ Active |
| `docs/setting_dev_env.md` | Dev setup guide | ⚠️ Has redirect to CLAUDE.md; content partially stale |
| `docs/tasks/README.md` | Task index | ✅ Current; links to briefs |
| `docs/LITCHESS_TRIM_BASELINE.md` | Baseline record | ✅ Historical record with tag reference |
| `docs/internationalisation.md` | i18n guide | ⚠️ Inherited from Lichess; relevance unclear |
| `docs/h4-credential-redaction.md` | Security spec | ✅ Closed; kept as record |
| `docs/pgn-import.md` | Import design | ⚠️ Early design; partially superseded by SPEC |

### 1.4 Historical/Audit Records (32 files)

These are dated audit reports, review records, and incident histories. They have
value as evidence trails but are not actively consulted:

- `docs/agent-history.md` (658 lines) — incident archive
- `docs/audit.md` (692 lines) — full audit report
- `docs/audit-disposition.md` (334 lines) — audit findings
- `docs/audit-unverified-fixes.md` — unverified fix log
- `docs/chesssrs-audit-and-scene-log.md` — design pass log
- `docs/dependency-audit.md` (317 lines) — dependency audit
- `docs/spec-conformance-audit-2026-10-16.md` — conformance audit
- `docs/spec-enforcement-audit-2026-10-21.md` (542 lines) — enforcement audit
- `docs/spec-audit-fix-status.md` — fix tracking
- `docs/spec-audit-handoff.md` — handoff record
- `docs/release-audit-2026-09-30.md` — release audit
- `docs/review-program.md` (589 lines) — review program
- `docs/review-register.md` — findings register
- `docs/review-index.md` — review pass index
- `docs/review-1-chessfsrs-scheduler.md` through `review-4-*` — 4 review passes
- `docs/upstream-audit-2026-09-29.md`, `-2026-09-30.md` — upstream audits
- `docs/upstream-applied.md`, `upstream-realign.md`, `upstream-tracker.md` — upstream sync
- `docs/upstream-audit-prompt.md` — audit instructions
- `docs/test-suite-pass-1.md` — coverage assessment
- `docs/test-audit/` (5 files) — test audit campaign
- `docs/next-task-handoff.md` — session handoff
- `docs/open-email-login-handoff.md` — login fix record
- `docs/phone-feedback-batch2.md` — feedback triage
- `docs/polish-tasks.md` — completed polish items
- `docs/recovered-work.md` — recovered branch work
- `docs/game-import-and-quality-gate.md` — proposal, not implemented

### 1.5 Autonomous/Meta Documents (4 files)

| File | Lines | Assessment |
|---|---|---|
| `docs/UNIVERSAL_AUTONOMOUS_IMPROVEMENT_PROMPT.md` | ~167 | ⚠️ Generic template; ChessSRS-specific catalog exists |
| `docs/recursive-agent-improvement-strategy.md` | ~167 | ⚠️ Generic strategy doc; redundant with catalog |

### 1.6 Non-docs Markdown (32 files)

| Location | Count | Notes |
|---|---|---|
| `design/docs/` + `design/README.md` | 10 | ✅ Well-organized design system |
| `audit/2026-10-17/` | 13 | Historical weak-rows audit campaign |
| `conversations/` | 4 | Raw conversation exports (823KB!) |
| `redteam/cases/` | 10 | Red-team corpus — actively used by G12 |
| `scripts/autonomous/README.md` | 1 | Autonomous tooling readme |
| Other platform READMEs | 5 | `android/`, `ios/`, `translation/` |
| `.github/PULL_REQUEST_TEMPLATE.md` | 1 | ✅ Active |
| `repomix.md` | 1 | Repomix pack instructions |

---

## 2. Authority Map Verification

Each entry in AGENTS.md §1 was verified against its claimed home:

| Subject | Home | Verdict |
|---|---|---|
| Product intent, journeys, non-goals | `PRODUCT.md` | ✅ Contains §1-6 as claimed |
| Current included/deferred beta scope | `MVP.md` | ✅ Clear included/deferred tables |
| Module boundaries, storage, licensing | `ARCHITECTURE.md` | ✅ §2/5/6/7 all present |
| Exact behavioral invariants, stable IDs | `SPEC.md` | ✅ 32 INVs with oracles/gates/tiers |
| Engineering constraints | `QUALITY.md` | ✅ Correctly defers to SPEC for numbered rules |
| Scheduling math | `ChessSRS Scheduling Architecture.md` | ✅ Equations and graph mechanisms |
| Local/remote verification | `TEST_STRATEGY.md` | ✅ §1-4 as claimed |
| Gate registry, evidence, approval | `GATES.md` | ✅ Full gate table, escapes, operator checklist |
| Planned gates and promotion | `GATES_PLAN.md` | ✅ Risk prioritization and remaining work |
| Delivery status | `IMPLEMENTATION_PLAN.md` | ✅ Phase 6 refinement active |
| Agent task selection, isolation | `AGENTS.md` | ✅ Self-referential and correct |
| Dart/Riverpod conventions | `CLAUDE.md` | ✅ Setup, testing, conventions |
| Visual/copy specification | `design/docs` via `design/README.md` | ✅ 00-08 design docs present |
| Cut decisions | `CUT_PROPOSALS.md` | ✅ Execution tables current |
| Reference-source provenance | `docs/INTEGRATION_MAP.md` | ✅ Listudy/chessrs boundaries |
| Decision rationale | `docs/decisions.md` | ✅ D001-D020 with dates/supersession |
| Owner decisions | `docs/open-questions.md` | ✅ Q1-Q15, 5 open |
| Manual test log | `docs/manual-test-log.md` | ✅ Active; uncovered items tracked |
| Publishing, stamping | `docs/releases.md` | ✅ Tag-push workflow documented |

**No contradictions found between normative homes.** The reconciliation of
2026-10-21 resolved the previously documented conflicts. The remaining open
conflicts (Q7, Q12, Q13, Q14) are correctly tracked in `docs/open-questions.md`.

---

## 3. Documentation Health

### 3.1 Broken/Stale References

| Location | Issue | Severity |
|---|---|---|
| `docs/decisions.md` D020 | Links to `docs/tasks/FEAT-REP-43-dynamic-repertoire-branch-selection.md` which **does not exist** | 🔴 High |
| `docs/tasks/README.md` | References `FEAT-REP-43` in an entry but no such file exists in `docs/tasks/` | 🟡 Medium |
| `docs/architecture.md` | No redirect to root `ARCHITECTURE.md`; uses "suggested fields" language from early design | 🟡 Medium |
| `docs/testing.md` | No redirect to `TEST_STRATEGY.md`; parallel testing contract | 🟡 Medium |
| `docs/review.md` | 256 lines of review engine docs; no redirect to SPEC §C | 🟡 Medium |
| `docs/domain-model.md` | "Suggested fields" language; superseded by actual domain code | 🟡 Medium |
| `docs/roadmap.md` | "Phase 1 — MVP" language; superseded by MVP.md and IMPLEMENTATION_PLAN | 🟡 Medium |
| `GATES.md` line 17-18 | States "Merges to main go through a merge queue" but the operator checklist (line 83) correctly says "not available" — internal contradiction within the same file | 🔴 High |

### 3.2 Internal Link Health

All internal markdown links in root normative documents were verified:
- `README.md` → `docs/documentation-map.md`: ✅ exists
- `docs/documentation-map.md` → `../AGENTS.md#1-authority-and-conflicts`: ✅ exists
- `docs/documentation-map.md` → `documentation-reconciliation.md`: ✅ exists
- `docs/spec-audit-handoff.md` → `spec-audit-fix-status.md`: ✅ exists
- `docs/spec-audit-fix-status.md` → `spec-enforcement-audit-2026-10-21.md`: ✅ exists
- Root normative docs use backtick-quoted paths rather than links; no broken link targets found in those.

### 3.3 Outdated Information

| Item | Issue |
|---|---|
| `GATES.md` line 17-18 | "merge queue" claim contradicts §Operator checklist line 83-88 |
| `IMPLEMENTATION_PLAN.md` | Phases 0-5 (lines 1-~800) are purely historical with snapshot counts; still loaded by agents |
| `Chess_Repertoire_SRS_Product_Blueprint.md` | 1169 lines; says "do not read by default" but is always loaded if agents scan `.md` |
| `conversations/` | 823KB of raw conversation exports from Sep 2026; no current value |
| `docs/AUTONOMOUS_WORK_LEDGER.md` | 161KB — append-only ledger growing unboundedly |

---

## 4. Missing Documentation

### 4.1 API Documentation for `domain/` Types

The domain layer has 25 files (4237 lines). Doc-comment coverage is **good**
(avg ~20 `///` comments per file), with the heaviest files (`review_session.dart`:
169 doc comments, `graph_aware_review_coordinator.dart`: 65) being well-documented.

**Gaps:**
- `review_engine.dart` (84 lines, only 2 doc comments) — the core engine has
  almost no documentation despite being the central coordination point
- `ids.dart` (2 doc comments) — ID types lack explanation
- `transpose_scope.dart` (2 doc comments) — minimal documentation

### 4.2 Architecture Decision Records

`docs/decisions.md` contains **20 ADRs** (D001–D020), which is comprehensive.
Coverage of major decisions is good:
- ✅ Review-first design (D001)
- ✅ Local-first (D002)
- ✅ PGN is input, not model (D003)
- ✅ Binary FSRS grading (D015)
- ✅ Visual identity independence (D016)
- ✅ Firebase disposition (D017, superseded)
- ✅ CI docs-only fast lane (D018)
- ✅ Full-line review (D019)
- ✅ Line adoption overlay (D020)

**Missing ADRs:**
- No ADR for the choice of SQLite over other local databases
- No ADR for the sha1 canonical key format choice
- No ADR for the choice of FSRS-4.5 over other SRS algorithms

### 4.3 Onboarding & Contributing

| Document | Status |
|---|---|
| README.md | ✅ Present but minimal (72 lines) — see §5 below |
| CLAUDE.md | ✅ Comprehensive dev setup |
| CONTRIBUTING.md | ❌ **Missing** — no contributing guidelines |
| AGENTS.md | ✅ Agent onboarding is excellent |
| `docs/setting_dev_env.md` | ⚠️ Has redirect to CLAUDE; some unique content |
| Troubleshooting guide | ❌ **Missing** — no troubleshooting doc |
| FAQ for contributors | ❌ **Missing** |

### 4.4 Troubleshooting Guides

No troubleshooting guide exists. Common issues that should be documented:
- Build failures after `git pull` (codegen; mentioned in README but not as troubleshooting)
- SQLite schema migration failures
- FVM version mismatches
- Generated code conflicts

---

## 5. README Quality Assessment

**Current state:** 72 lines. Functional but not compelling.

| Aspect | Assessment |
|---|---|
| Value proposition | ✅ Clear: "local-first chess repertoire + spaced-repetition trainer" |
| Core concept | ✅ Quoted one-liner is excellent |
| Feature list | ✅ Four bullet points cover essentials |
| Screenshots | ❌ **None** — 120 screenshots exist in `docs/screenshots/` but none in README |
| Build instructions | ✅ Present but minimal (3 commands) |
| Website link | ✅ Present |
| Support/donation | ✅ Buy Me a Coffee |
| License section | ✅ Clear GPL-3.0 attribution |
| Documentation pointer | ✅ Links to authority map |

**Missing from README:**
- Screenshots or GIF demo (120 screenshots already exist in `docs/screenshots/`)
- Comparison with alternatives (listudy, chessrs, Anki chess decks)
- Feature highlight section with more detail
- Platform support table (Linux, Android mentioned on website)
- Badges (CI status, license, version)

---

## 6. Code-Level Documentation

### 6.1 TODO/FIXME Inventory

20 occurrences across 17 files in `lib/`. **All are in inherited Lichess code**,
none in ChessSRS domain/review/import code:

| Pattern | Count | Notable |
|---|---|---|
| `TODO: l10n` | 4 | Untranslated strings in analysis/explorer views |
| `TODO` (general) | 15 | Lichess inherited: retry buttons, color choices, translations |
| `FIXME` | 0 | None |
| `HACK` | 0 | None |
| `XXX` | 0 | None |

**Assessment:** Clean. No technical debt markers in ChessSRS-original code.

### 6.2 Undocumented Public APIs in `domain/`

The domain barrel (`domain.dart`) exports 4 items. Most domain types have good
doc comments. The weakest files:

- `review_engine.dart` — 84 lines, 2 doc comments. The `ReviewEngine` class is
  the core abstraction but has near-zero documentation.
- `ids.dart` — Type aliases for IDs with no doc comments explaining their purpose.
- `transpose_scope.dart` — Enum with 2 doc comments but no explanation of
  grading implications.

### 6.3 Complex Algorithms Without Comments

- `review_session.dart` (1847 lines) — **Well-documented** with 169 doc comments
  covering the state machine, traversal logic, and line-walking.
- `graph_aware_review_coordinator.dart` (300 lines) — **Well-documented** with
  65 doc comments on contagion, coupling, and credit mechanics.
- `chess_fsrs_scheduler.dart` (343 lines) — **Well-documented** with 42 doc
  comments covering FSRS math.

---

## 7. docs/ Cleanup & Reorganization

### 7.1 Size Analysis

Total docs/ content: **1.15 MB** across 91 files.

Top consumers:
| File | Size | Active use |
|---|---|---|
| `AUTONOMOUS_WORK_LEDGER.md` | 161 KB | Active but growing unboundedly |
| `review-program.md` | 68 KB | Historical review campaign |
| `AUTONOMOUS_MUTANTS.md` | 63 KB | Active mutant ledger |
| `spec-enforcement-audit-2026-10-21.md` | 51 KB | Historical audit |
| `audit.md` | 43 KB | Historical audit |
| `agent-history.md` | 39 KB | Historical incidents |
| `tech-debt-inventory.md` | 29 KB | Dated inventory |
| `open-questions.md` | 27 KB | Active |
| `review-1-chessfsrs-scheduler.md` | 26 KB | Historical review |

### 7.2 Proposed Reorganization

```
docs/
├── active/                          # Actively consulted
│   ├── decisions.md
│   ├── open-questions.md
│   ├── documentation-map.md
│   ├── documentation-reconciliation.md
│   ├── INTEGRATION_MAP.md
│   ├── ESCAPE_TO_GATE.md
│   ├── releases.md
│   ├── manual-test-log.md
│   ├── performance-handoff.md
│   ├── tech-debt-inventory.md
│   ├── AUTONOMOUS_IMPROVEMENT_CATALOG.md
│   ├── AUTONOMOUS_WORK_LEDGER.md
│   ├── AUTONOMOUS_MUTANTS.md
│   └── internationalisation.md
├── guides/                          # Setup & process guides
│   ├── setting_dev_env.md           # (merge into CLAUDE.md?)
│   ├── pgn-import.md
│   └── UNIVERSAL_AUTONOMOUS_IMPROVEMENT_PROMPT.md
├── archive/                         # Historical records (read-only)
│   ├── shadow/                      # Former duplicate docs
│   │   ├── architecture.md
│   │   ├── product.md
│   │   ├── design.md
│   │   ├── testing.md
│   │   ├── performance.md
│   │   ├── coding_style.md
│   │   ├── domain-model.md
│   │   ├── review.md
│   │   ├── roadmap.md
│   │   └── inspiration.md
│   ├── audits/                      # Dated audit reports
│   │   ├── audit.md
│   │   ├── audit-disposition.md
│   │   ├── audit-unverified-fixes.md
│   │   ├── dependency-audit.md
│   │   ├── release-audit-2026-09-30.md
│   │   ├── spec-conformance-audit-2026-10-16.md
│   │   ├── spec-enforcement-audit-2026-10-21.md
│   │   ├── spec-audit-fix-status.md
│   │   ├── spec-audit-handoff.md
│   │   ├── upstream-audit-*.md
│   │   └── test-suite-pass-1.md
│   ├── reviews/                     # Code review passes
│   │   ├── review-program.md
│   │   ├── review-register.md
│   │   ├── review-index.md
│   │   └── review-1-* through review-4-*
│   ├── incidents/
│   │   └── agent-history.md
│   ├── handoffs/
│   │   ├── next-task-handoff.md
│   │   ├── open-email-login-handoff.md
│   │   ├── h4-credential-redaction.md
│   │   └── recovered-work.md
│   └── proposals/
│       ├── game-import-and-quality-gate.md
│       ├── phone-feedback-batch2.md
│       ├── polish-tasks.md
│       ├── recursive-agent-improvement-strategy.md
│       └── chesssrs-audit-and-scene-log.md
├── tasks/                           # (keep as-is)
├── test-audit/                      # (move to archive/audits/)
└── screenshots/                     # (keep; use in README)
```

**Impact:** Reduces the flat `docs/` listing from 60+ files to ~15 actively
consulted files, while preserving all historical records in clearly labeled
subdirectories.

### 7.3 Files to Delete or Merge

| File | Action | Reason |
|---|---|---|
| `conversations/` (4 files, 823 KB) | **Delete** | Raw conversation exports; no reference value; not referenced anywhere |
| `CODING_STANDARDS.md` | **Merge into CLAUDE.md** | 86 lines; duplicates domain doc requirements already in CLAUDE |
| `docs/upstream-tracker.md` | **Archive** | Describes automated tracking that isn't running |
| `docs/upstream-realign.md` | **Archive** | Superseded by upstream audit reports |
| `repomix.md` | **Keep** | Utility instructions; small |
| `Chess_Repertoire_SRS_Product_Blueprint.md` | **Archive or delete** | 1169 lines; says "do not read"; fully superseded by PRODUCT.md |

---

## 8. SPEC.md Quality Assessment

### 8.1 Strengths

- **Falsifiability:** Every INV has an oracle (how violations are detected) ✅
- **Stable IDs:** `INV-001` through `INV-069` with explicit "never renumbered" rule ✅
- **Tier classification:** T0/T1/T2 severity ratings on every invariant ✅
- **Covering tests:** Every INV lists its covering test file(s) ✅
- **Change log:** Dated amendments with reviewer attribution ✅
- **Retirement policy:** Retired IDs explained (though none retired yet) ✅
- **Clear sections:** A-F grouping by concern is logical ✅

### 8.2 Gaps and Concerns

| Issue | Severity | Detail |
|---|---|---|
| No INV for PGN export correctness | 🟡 Medium | INV-014 covers round-trip identity but not export format fidelity (e.g., valid PGN syntax, correct RAV nesting in output) |
| No INV for study/chapter CRUD | 🟡 Medium | Deletion cascade (INV-004) exists but creation/rename/reorder have no invariants |
| No INV for settings persistence | 🟢 Low | Scheduler settings, review preferences — no invariant that settings survive restart |
| No INV for concurrent access | 🟡 Medium | No invariant about what happens if two sessions grade the same position |
| ID gap: INV-034 through INV-039 | 🟢 Info | Large gap in numbering between §C and §D; not a problem but notable |
| ID gap: INV-043 through INV-049 | 🟢 Info | Gap between §D and §E |
| ID gap: INV-052 through INV-059 | 🟢 Info | Gap between §E and §F |
| Unresolved conflicts | 🟡 Medium | Q12 (16ms budget scope), Q13 (FSRS lapse count), Q14 (null-date due status) all awaiting owner decisions |

### 8.3 Invariant Quality Spot-Checks

- **INV-020** (board-only truth): Excellent. Clear, falsifiable, well-scoped. ✅
- **INV-050** (move latency): The oracle measures batch median, but the INV says
  "single frame" — this mismatch is correctly tracked as Q12. ⚠️
- **INV-068** (fresh vs due): Good but the null-date edge case (Q14) means the
  invariant text doesn't fully specify behavior in a known corner case. ⚠️
- **INV-025** (success grows interval): The FSRS preservation of repetition count
  (Q13) means the "resets the streak" language may not match one scheduler's
  behavior. ⚠️

---

## 9. Specific Fixes Needed

### Priority 1 — Immediate

1. **Fix broken reference in D020:** `docs/tasks/FEAT-REP-43-dynamic-repertoire-branch-selection.md`
   does not exist. Either create the referenced brief or update D020's link.

2. **Fix GATES.md internal contradiction:** Line 17-18 says "merge queue" but the
   operator checklist (line 83-88) correctly documents that no merge queue is
   available. Update the first reference.

3. **Add redirect banners to shadow docs:** At minimum, `docs/architecture.md`,
   `docs/testing.md`, `docs/performance.md`, `docs/review.md`, and
   `docs/domain-model.md` need a prominent redirect to their normative home.

### Priority 2 — Short Term

4. **Add screenshots to README.md:** 120 screenshots already exist in
   `docs/screenshots/`. Pick 2-3 representative ones for the README.

5. **Create CONTRIBUTING.md:** Even a short one pointing to AGENTS.md, CLAUDE.md,
   and the authority map would help.

6. **Document `review_engine.dart`:** The core engine abstraction has 2 doc
   comments for 84 lines of code.

7. **Archive `conversations/` directory:** 823 KB of raw conversation exports
   with no current value.

### Priority 3 — Medium Term

8. **Reorganize docs/:** Implement the proposed directory structure to reduce
   discovery burden from 60+ flat files to ~15 actively consulted ones.

9. **Archive `Chess_Repertoire_SRS_Product_Blueprint.md`:** 1169 lines of
   superseded content that opens with "do not read by default."

10. **Merge `CODING_STANDARDS.md` into `CLAUDE.md`:** Avoid having two files
    that both define coding standards.

11. **Resolve open SPEC conflicts:** Q12 (16ms scope), Q13 (FSRS lapse), Q14
    (null-date) need owner decisions before the SPEC text can be tightened.

### Priority 4 — Nice to Have

12. **Add CI status badge to README.**
13. **Create a troubleshooting guide** for common build issues.
14. **Add missing ADRs** for SQLite choice, sha1 key format, FSRS-4.5 selection.
15. **Cap or rotate `AUTONOMOUS_WORK_LEDGER.md`** (161 KB and growing).

---

## 10. Summary Metrics

| Metric | Value |
|---|---|
| Total markdown files | 158 |
| Root normative docs | 15 (healthy) |
| Active operational docs | ~19 |
| Historical/archive candidates | ~40 |
| Shadow/duplicate docs | 10 (need redirects or archival) |
| Broken file references | 1 (D020 → FEAT-REP-43) |
| Internal contradictions | 1 (GATES.md merge queue) |
| Open SPEC conflicts | 3 (Q12, Q13, Q14) |
| Missing docs | CONTRIBUTING.md, troubleshooting guide |
| README missing screenshots | Yes (120 available) |
| TODO/FIXME in lib/ | 20 (all inherited Lichess) |
| Domain doc-comment coverage | Good (avg ~20/file) |
| docs/ size | 1.15 MB across 91 files |
| Recommended for archival | ~40 files (~500 KB) |
