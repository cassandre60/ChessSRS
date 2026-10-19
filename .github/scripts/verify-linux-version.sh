#!/usr/bin/env bash
# Assert the built Linux bundle reports the version this run stamped into it.
#
# The About screen (lib/src/view/review/about_page.dart) and the account menu
# read package_info_plus, which on Linux reads
# data/flutter_assets/version.json — a file the Flutter tool generates from
# --build-name. That indirection is why v1.5.0 through v1.6.2 shipped telling
# the owner they were v1.4.0: the build never carried its own tag.
#
# Env: EXPECTED_VERSION. Run from the repository root.
set -euo pipefail

VERSION_JSON="build/linux/x64/release/bundle/data/flutter_assets/version.json"

if [ ! -f "$VERSION_JSON" ]; then
  echo "no $VERSION_JSON — did the build produce a bundle?" >&2
  exit 1
fi

actual="$(jq -r '.version' "$VERSION_JSON")"
if [ "$actual" != "$EXPECTED_VERSION" ]; then
  echo "$VERSION_JSON reports '$actual', but this release is '$EXPECTED_VERSION'" >&2
  exit 1
fi
echo "version.json reports $actual, as intended"
