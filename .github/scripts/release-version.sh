#!/usr/bin/env bash
# Decide what version a release build should report, and write it to
# $GITHUB_OUTPUT as `version`, `build_number` and `tag`.
#
# The tag is the only version ledger: on a tag push the version comes from the
# tag, so the artifact can never disagree with what it was published as. A
# manual dispatch has no tag and falls back to pubspec's development version.
#
# `tag` is the name the artifacts are FILES under, which is not the same thing
# as the version: on a tag push it is the tag, and otherwise it is a run number.
# It must never contain a slash, because a branch name does — naming a tarball
# after the branch it was dispatched from wrote it to a path that does not
# exist, and failed the whole dry run.
#
# The build number is the workflow run number, which rises on every run. That
# matters for Android: Play Store refuses an upload whose versionCode does not
# increase, and a pubspec-derived build number never changed.
#
# Used by the linux and android jobs of .github/workflows/release.yml.
set -euo pipefail

if [ "${GITHUB_REF_TYPE:-}" = "tag" ]; then
  # The workflow only triggers on 'v*' tags, and the publish job only runs for
  # them, so the tag itself is checked rather than the stripped value: a tag
  # that is not v<major>.<minor>.<patch> would stamp garbage into the About
  # screen, and refusing it beats publishing a lie.
  if ! printf '%s' "$GITHUB_REF_NAME" |
    grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$'; then
    echo "tag '${GITHUB_REF_NAME}' is not v<major>.<minor>.<patch>; refusing to stamp it" >&2
    exit 1
  fi
  VERSION="${GITHUB_REF_NAME#v}"
  FILE_TAG="$GITHUB_REF_NAME"
else
  VERSION="$(awk '/^version:/ { print $2; exit }' pubspec.yaml | cut -d+ -f1)"
  if [ -z "$VERSION" ]; then
    echo "could not read a version from pubspec.yaml" >&2
    exit 1
  fi
  FILE_TAG="build-${GITHUB_RUN_NUMBER}"
fi

echo "version=${VERSION}" >> "$GITHUB_OUTPUT"
echo "build_number=${GITHUB_RUN_NUMBER}" >> "$GITHUB_OUTPUT"
echo "tag=${FILE_TAG}" >> "$GITHUB_OUTPUT"
echo "stamping this build as ${VERSION} (build number ${GITHUB_RUN_NUMBER}, files as ${FILE_TAG})"
