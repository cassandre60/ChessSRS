#!/usr/bin/env bash
# Single entry point for every gate. CI and contributors both call this, so
# each gate has exactly one definition.
#   ./scripts/gates.sh t0   # seconds: banned APIs in the pure core
#   ./scripts/gates.sh t1   # + referee checks, spec traceability, ratchets
#   ./scripts/gates.sh t2   # + hand-picked mutation run (needs the Flutter toolchain; local opt-in)
set -euo pipefail
TIER="${1:-t1}"
BASE="${BASE_REF:-origin/main}"
here="$(cd "$(dirname "$0")" && pwd)"
gates="$here/gates"
root="$(cd "$here/.." && pwd)"
cd "$root"

step() { printf '\n== %s ==\n' "$*"; }
fail() { printf '\nFAIL %s\n' "$*" >&2; exit 1; }

# ---- t0 ---------------------------------------------------------------------------------
step "G03 banned APIs in core"
python3 "$gates/banned_apis_check.py" --config .gates/banned-apis.json --root . || fail "G03 banned APIs"

[[ "$TIER" == "t0" ]] && { echo "t0 ok"; exit 0; }

# ---- t1 ---------------------------------------------------------------------------------
step "G07 protected paths (base $BASE)"
python3 "$gates/protected_paths_check.py" --base "$BASE" ${APPROVED:+--approved} || fail "G07 protected paths (referee edited)"

step "G08 test-weakening tripwire (base $BASE)"
python3 "$gates/test_weakening_check.py" --base "$BASE" || fail "G08 test weakening"

step "G05 spec traceability"
python3 "$gates/spec_trace_check.py" --spec SPEC.md --tests test || fail "G05 spec traceability"

step "G10 ratchets"
metrics_dir="$(mktemp -d)"
python3 "$gates/collect_metrics.py" --out "$metrics_dir/metrics.json"
python3 "$gates/ratchet_check.py" --baseline .gates/ratchet-baseline.json --current "$metrics_dir/metrics.json" || fail "G10 ratchet"
rm -rf "$metrics_dir"

[[ "$TIER" == "t1" ]] && { echo "t1 ok"; exit 0; }

# ---- t2 ---------------------------------------------------------------------------------
step "G06 hand-picked mutants (R0/R1 scheduler boundaries)"
python3 "$gates/manual_mutation_runner.py" --mutants .gates/mutants.json \
  --test-cmd "fvm flutter test test/domain/scheduler_test.dart" || fail "G06 mutation"

if [[ "${CLASS:-}" == "bugfix" ]]; then
  step "G09 fail-to-pass"
  bash "$gates/fail_to_pass_check.sh" "$BASE" "fvm flutter test ${TEST_FILES:-test/domain/scheduler_test.dart}" || fail "G09 fail-to-pass"
fi

echo "t2 ok"
