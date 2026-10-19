#!/usr/bin/env bash
# Decide whether tonight's nightly build is worth spending runner minutes on,
# and write the answer to $GITHUB_OUTPUT as `needed` and `reason`.
#
# The point is not to build less often. It is to not build when the result
# would be byte-identical to the last one: a build costs a Linux compile and
# two Android release compiles, and this repository merges test, gate and
# documentation work far more often than it merges changes to the app.
#
# Three ways to skip, in order of cheapness:
#   1. main has not moved since the newest tag — there is nothing new at all.
#   2. nothing shipped changed since that tag (lib/, assets/, the platform
#      directories, the dependency manifest) — the app would be identical.
#   3. this exact commit has already been built, or is being built right now —
#      a scheduled run and a manual one can land on the same commit.
# A previous build that FAILED does not skip: retrying it is the point.
#
# Env: GITHUB_OUTPUT, GH_TOKEN (for `gh run list`), PATH (a fake `gh` is used in tests).
# Runs on a checkout with full history and tags.
set -euo pipefail

needed=false
reason=""

tag="$(git describe --tags --abbrev=0 HEAD 2>/dev/null || true)"

if [ -z "$tag" ]; then
  needed=true
  reason="no tag exists yet, so nothing has ever been built here"
elif git diff --quiet "$tag" HEAD; then
  reason="$tag is already the tip of main; there is nothing new to build"
else
  # What changes the shipped binary or what it displays, as opposed to what
  # only changes how the repository is tested, gated or documented.
  shipped="$(git diff --name-only "$tag" HEAD |
    grep -E '^(lib|assets|android|linux)/|^pubspec\.(yaml|lock)$' || true)"

  if [ -z "$shipped" ]; then
    count="$(git diff --name-only "$tag" HEAD | wc -l | tr -d ' ')"
    reason="$count files changed since $tag, none of them shipped code"
  else
    sha="$(git rev-parse HEAD)"
    # "running" covers a queued run too: GitHub reports conclusion=null.
    prior="$(gh run list --workflow release.yml --limit 30 \
      --json headSha,conclusion \
      --jq "map(select(.headSha == \"$sha\")) | .[0] |
             if . == null then \"none\"
             elif .conclusion == null then \"running\"
             else .conclusion end")"

    case "$prior" in
      success | running)
        reason="$sha was already built by a Release run ($prior)"
        ;;
      *)
        needed=true
        reason="$(printf '%s\n' "$shipped" | wc -l | tr -d ' ') shipped files changed since $tag"
        ;;
    esac
  fi
fi

echo "needed=${needed}" >>"$GITHUB_OUTPUT"
echo "reason=${reason}" >>"$GITHUB_OUTPUT"

if [ "$needed" = "true" ]; then
  echo "nightly build: YES — ${reason}"
else
  echo "nightly build: no — ${reason}"
fi
