#!/usr/bin/env bash
# Tests for the release version stamping in .github/scripts/.
#
# Runs the real scripts CI runs, with fake build outputs, so the logic is
# checked without a Flutter build. Wired into test.yml because the failure it
# guards against is silent: with the version taken from pubspec, v1.5.0 through
# v1.6.2 all built, published and installed successfully while the app told the
# owner it was v1.4.0. Nothing about that was red.
#
# Run from the repository root: bash .github/scripts/release-version-test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  PASS %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s — %s\n' "$1" "$2"; }

# The dispatch fallback reads pubspec.yaml, so it needs the real one in scope.
cp "$ROOT/pubspec.yaml" "$WORK/"
cd "$WORK" || exit 1
DEV_VERSION="$(awk '/^version:/ { print $2; exit }' pubspec.yaml | cut -d+ -f1)"

# resolve <ref_type> <ref_name> <run_number>; succeeds only if the script does.
resolve() {
  : > "$WORK/out"
  GITHUB_REF_TYPE="$1" GITHUB_REF_NAME="$2" GITHUB_RUN_NUMBER="$3" \
    GITHUB_OUTPUT="$WORK/out" bash "$HERE/release-version.sh" >/dev/null 2>&1
}
stamped() { grep -qx "$1" "$WORK/out"; }

echo "release-version.sh:"
resolve tag v1.6.3 42
if stamped 'version=1.6.3' && stamped 'build_number=42'; then
  ok "tag v1.6.3 stamps 1.6.3 with build number 42"
else
  bad "tag v1.6.3" "got: $(tr '\n' ' ' <"$WORK/out")"
fi

if ! resolve tag vnot-a-version 42; then
  ok "a tag that is not v<major>.<minor>.<patch> is refused"
else
  bad "bad tag" "it was accepted"
fi

if ! resolve tag 1.6.3 42; then
  ok "a tag without the v prefix is refused"
else
  bad "unprefixed tag" "it was accepted"
fi

resolve tag v1.7.0-rc.1 43
if stamped 'version=1.7.0-rc.1'; then
  ok "a pre-release tag keeps its suffix"
else
  bad "prerelease tag" "got: $(tr '\n' ' ' <"$WORK/out")"
fi

resolve branch main 44
if stamped "version=$DEV_VERSION"; then
  ok "a manual dispatch falls back to pubspec's version ($DEV_VERSION)"
else
  bad "dispatch fallback" "got: $(tr '\n' ' ' <"$WORK/out")"
fi

resolve tag v1.6.3 45
if stamped 'build_number=45'; then
  ok "the build number follows the run number, so versionCode increases"
else
  bad "build number" "got: $(tr '\n' ' ' <"$WORK/out")"
fi

VERSION_JSON="build/linux/x64/release/bundle/data/flutter_assets/version.json"
mkdir -p "$(dirname "$VERSION_JSON")"

echo "verify-linux-version.sh:"
echo '{"app_name":"chess_srs","version":"1.6.3","build_number":"42"}' >"$VERSION_JSON"
if EXPECTED_VERSION=1.6.3 bash "$HERE/verify-linux-version.sh" >/dev/null 2>&1; then
  ok "a bundle stamped with the right version passes"
else
  bad "matching bundle" "it failed"
fi

# The regression this PR exists to stop.
echo '{"app_name":"chess_srs","version":"1.4.0","build_number":"7"}' >"$VERSION_JSON"
if ! EXPECTED_VERSION=1.6.3 bash "$HERE/verify-linux-version.sh" >/dev/null 2>&1; then
  ok "a bundle still claiming 1.4.0 is rejected for a 1.6.3 release"
else
  bad "stale bundle" "a bundle claiming 1.4.0 was accepted"
fi

rm -f "$VERSION_JSON"
if ! EXPECTED_VERSION=1.6.3 bash "$HERE/verify-linux-version.sh" >/dev/null 2>&1; then
  ok "a missing version.json fails instead of passing vacuously"
else
  bad "missing file" "it passed with no file to read"
fi

mkdir -p android
echo "verify-android-version.sh:"
printf 'flutter.versionName=1.6.3\nflutter.versionCode=42\n' >android/local.properties
if EXPECTED_VERSION=1.6.3 EXPECTED_BUILD_NUMBER=42 \
  bash "$HERE/verify-android-version.sh" >/dev/null 2>&1; then
  ok "matching versionName/versionCode passes"
else
  bad "matching android props" "it failed"
fi

printf 'flutter.versionName=1.6.3\nflutter.versionCode=7\n' >android/local.properties
if ! EXPECTED_VERSION=1.6.3 EXPECTED_BUILD_NUMBER=42 \
  bash "$HERE/verify-android-version.sh" >/dev/null 2>&1; then
  ok "a versionCode that never advances is rejected"
else
  bad "stuck versionCode" "versionCode 7 was accepted"
fi

printf 'flutter.versionName=1.4.0\nflutter.versionCode=7\n' >android/local.properties
if ! EXPECTED_VERSION=1.6.3 EXPECTED_BUILD_NUMBER=42 \
  bash "$HERE/verify-android-version.sh" >/dev/null 2>&1; then
  ok "a build still claiming 1.4.0 is rejected for a 1.6.3 release"
else
  bad "stale versionName" "a 1.4.0 build was accepted"
fi

rm -f android/local.properties
if ! EXPECTED_VERSION=1.6.3 EXPECTED_BUILD_NUMBER=42 \
  bash "$HERE/verify-android-version.sh" >/dev/null 2>&1; then
  ok "a missing local.properties fails instead of passing vacuously"
else
  bad "missing file" "it passed with no file to read"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
