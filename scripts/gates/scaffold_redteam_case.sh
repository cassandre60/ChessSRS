#!/usr/bin/env bash
# Scaffold a red-team case: directory, case.md from the template, and an empty
# patch.diff placeholder. The agent fills in the description and generates the
# real patch following docs/ESCAPE_TO_GATE.md step 6.
#
# Usage: bash scripts/gates/scaffold_redteam_case.sh rt-<nn>-<short-name>
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 rt-<nn>-<short-name>" >&2
  exit 2
fi
case_id="$1"
if [[ ! "$case_id" =~ ^rt-[0-9]{2}-[a-z0-9-]+$ ]]; then
  echo "error: id must look like rt-08-stale-write (got '$case_id')" >&2
  exit 2
fi

root="$(cd "$(dirname "$0")/../.." && pwd)"
dir="$root/redteam/cases/$case_id"
if [[ -e "$dir" ]]; then
  echo "error: $dir already exists" >&2
  exit 2
fi

sha="$(git -C "$root" rev-parse HEAD)"
mkdir -p "$dir"
cat > "$dir/case.md" <<EOF
# Red-team case: $case_id

Status: active
Category: <!-- hardcode | weaken-assertion | skip-test | swallow-error | mock-the-subject | suppression | widen-tolerance | delete-feature | spec-edit | env-special-case | nondeterminism-mask | real-bug-class -->
Expected catcher(s): <!-- e.g. G08 test-weakening tripwire -->

## What the patch does
<!-- plain-language description precise enough to regenerate the patch when it goes stale -->

## Why it is wrong
<!-- the behavior or invariant it violates, INV-xxx -->

## Why a naive gate would pass it
<!-- what makes it look green -->

## History
<!-- if this came from a real escape: date, PR, root cause -->

Patch file: \`patch.diff\` (git diff format, applies to the commit recorded below)
Recorded against: $sha
EOF
: > "$dir/patch.diff"

echo "created $dir/case.md + empty patch.diff (recorded against $sha)"
echo "next: generate the patch in a throwaway worktree per docs/ESCAPE_TO_GATE.md step 6,"
echo "fill in case.md, then prove the expected catcher rejects it."
