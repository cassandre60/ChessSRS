#!/usr/bin/env bash
# Assert the built Android artifacts report the version this run stamped into
# them.
#
# The Flutter tool writes flutter.versionName/flutter.versionCode into
# android/local.properties from --build-name/--build-number; those are what
# Android displays and what the Play Store reads. With the version coming from
# pubspec alone, every release carried versionCode 7, so no new build could be
# uploaded as an update to the previous one.
#
# Env: EXPECTED_VERSION, EXPECTED_BUILD_NUMBER. Run from the repository root.
set -euo pipefail

PROPS="android/local.properties"

if [ ! -f "$PROPS" ]; then
  echo "no $PROPS — did the Android build run?" >&2
  exit 1
fi

actual_name="$(sed -n 's/^flutter.versionName=//p' "$PROPS")"
actual_code="$(sed -n 's/^flutter.versionCode=//p' "$PROPS")"

if [ "$actual_name" != "$EXPECTED_VERSION" ] ||
  [ "$actual_code" != "$EXPECTED_BUILD_NUMBER" ]; then
  echo "$PROPS reports versionName='$actual_name' versionCode='$actual_code'," >&2
  echo "but this release should be '$EXPECTED_VERSION' / '$EXPECTED_BUILD_NUMBER'" >&2
  exit 1
fi
echo "Android reports $actual_name (versionCode $actual_code), as intended"
