#!/usr/bin/env bash
# Unit tests for ci-docs-only.sh, run on every PR by test.yml.
#
# The classifier decides whether the Flutter suite runs at all, so it is a
# judge of its own job: if it silently begins answering "true" for code, every
# PR skips its tests and nothing else in CI would notice. Hence a case per
# boundary, including the two paths that actually are read by tests.
#
# Cases feed the classifier through a here-string, not a pipe: `printf | check`
# would run check in a subshell and the tallies would never come back, leaving
# this file green whatever the cases did (caught while writing it, 2026-10-23).
#
# Usage: ci-docs-only-test.sh [path-to-classifier]
set -uo pipefail

classifier="${1:-$(dirname "$0")/ci-docs-only.sh}"
if [ ! -f "$classifier" ]; then
  echo "classifier not found: $classifier" >&2
  exit 2
fi

pass=0
fail=0

check() { # <expected docs_only value> <case name>; paths on stdin
  local expected=$1 name=$2 got
  got=$(bash "$classifier" 2>/dev/null)
  if [ "$got" = "docs_only=$expected" ]; then
    pass=$((pass + 1))
    printf 'ok   %-52s -> %s\n' "$name" "$got"
  else
    fail=$((fail + 1))
    printf 'FAIL %-52s -> got %s, want docs_only=%s\n' "$name" "'$got'" "$expected"
  fi
}

check true 'docs Markdown only' <<< $'docs/documentation-map.md\ndocs/tasks/README.md'
check true 'nested docs Markdown' <<< 'docs/a/b.md'
check false 'docs plus code' <<< $'docs/documentation-map.md\nlib/src/app.dart'
check false 'root Markdown (read by enforcement_matrix_test.dart)' <<< 'TEST_STRATEGY.md'
check false 'root referee Markdown' <<< 'AGENTS.md'
check false 'docs golden png (read by screenshot_capture_test.dart)' <<< 'docs/screenshots/review.png'
check false 'non-Markdown under docs' <<< 'docs/notes.txt'
check false 'design docs (outside the lane)' <<< 'design/docs/03-components.md'
check false 'the classifier itself' <<< '.github/scripts/ci-docs-only.sh'
check false 'code only' <<< 'lib/src/app.dart'
check false 'empty diff'
check false 'traversal out of docs' <<< 'docs/../lib/src/app.md'

echo
if [ "$fail" -eq 0 ]; then
  echo "ci-docs-only: $pass/$((pass + fail)) cases passed"
else
  echo "ci-docs-only: $fail of $((pass + fail)) case(s) failed"
  exit 1
fi
