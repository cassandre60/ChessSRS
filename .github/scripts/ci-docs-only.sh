#!/usr/bin/env bash
# Decide whether a diff can only be documentation.
#
# Reads changed paths on stdin, one per line, exactly as
# `git diff --no-renames --name-only <base> HEAD` prints them, and writes
# exactly one line for $GITHUB_OUTPUT:
#
#     docs_only=true    every changed path is Markdown prose under docs/
#     docs_only=false   anything else, including an empty list
#
# test.yml runs the Flutter toolchain only when this says false. It always runs
# the job and always reports the "Tests" check, so branch protection is
# satisfied by the real job rather than by a stand-in wearing its name (the
# collision closed in #95/#107).
#
# Why the rule is this narrow
# ---------------------------
# "No step reads a Markdown file" holds for most of the repo and fails for the
# two that matter:
#   - test/reachability/enforcement_matrix_test.dart parses TEST_STRATEGY.md, so
#     a root-level .md edit can genuinely break the suite (G-BASEINV's matrix);
#   - test/view/screenshot_capture_test.dart compares docs/screenshots/*.png.
# So the fast lane is limited to `docs/**` Markdown, which no test reads, and
# everything else -- root .md, pngs, code, workflow files -- runs the full
# suite. Every uncertain case resolves to false: a wrongly slow run costs
# minutes, a wrongly fast one would hide a real failure.
set -uo pipefail

docs_only=true
seen=0

while IFS= read -r path; do
  [ -n "$path" ] || continue
  seen=$((seen + 1))
  case "$path" in
    # `*` crosses `/` in a shell case pattern, so this also covers docs/a/b.md.
    *'/../'*) docs_only=false ;;
    docs/*.md) : ;;
    *) docs_only=false ;;
  esac
done

if [ "$seen" -eq 0 ]; then
  # No diff to classify (or the caller could not produce one): run everything.
  docs_only=false
fi

if [ "$docs_only" = "true" ]; then
  echo "docs-only fast lane: all $seen changed path(s) are Markdown under docs/" >&2
else
  echo "full suite: the diff is not prose under docs/ ($seen path(s) seen)" >&2
fi

echo "docs_only=$docs_only"
