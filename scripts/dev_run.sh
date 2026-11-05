#!/usr/bin/env bash
# Regenerate code, then run the app.
#
# `flutter run` does not run build_runner, and the generated *.freezed.dart /
# *.g.dart files are gitignored. After a `git pull` that changes a Freezed or
# json_serializable source, a bare `flutter run` compiles the OLD generated code
# and fails with errors inside the *.freezed.dart files — the error points at the
# generated file, not at the source that changed. CI regenerates before
# compiling, so it never sees this.
#
# Usage:
#   scripts/dev_run.sh                  # regenerate, then run
#   scripts/dev_run.sh -d linux         # extra args go to `flutter run`
#   scripts/dev_run.sh -d linux --debug
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
fvm flutter pub get
fvm dart run build_runner build
exec fvm flutter run "$@"