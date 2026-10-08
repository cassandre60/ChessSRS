<!-- Fill every section. One concern per PR. See GATES.md for the class table. -->

**Class:** <!-- one of: bugfix | perf | refactor | feature | test-only | docs | dependency | gate-change | spec-change -->

## Problem
<!-- What is wrong or missing? Link the issue or invariant (INV-xxx). -->

## Root cause / rationale
<!-- Why does it happen / why this design? -->

## Evidence (required for the class)
- [ ] bugfix: regression test that FAILS on the base commit and passes here (`scripts/gates/fail_to_pass_check.sh` output pasted below; set EXPECT_PATTERN so it fails for the right reason)
- [ ] perf: before/after benchmark output on the pinned harness + equivalence test vs the old implementation
- [ ] refactor: no test files modified; behavior-equivalence evidence
- [ ] feature: SPEC.md invariants added or updated first (separate spec-change PR or same series); property tests for each
- [ ] test-only: names the mutant(s), invariant, or ratchet this kills
- [ ] dependency: written justification for the new dependency
- [ ] gate-change / spec-change: explains what it stops or starts catching and why; no product-code changes; needs the `gate-approved` label from the owner

```
<paste gate output here>
```

## Risk and rollback
<!-- What could break? How do we undo it? -->

## Honest status
- Ran locally: <!-- list commands -->
- Not run / unverified: <!-- be specific -->
- Protected paths touched: <!-- none, or list and justify -->
