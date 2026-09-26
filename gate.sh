#!/usr/bin/env bash
# Lightweight local gate for design/v2-remainder.
#
# This gate is ANALYZE AND FORMAT ONLY. It deliberately does not run `flutter test`, at
# any concurrency, even for a single file: compiling the test tree saturates the CPU and
# the fans on this machine, and the project rules already say resource-heavy verification
# belongs in CI, not locally.
#
# Tests run in GitHub Actions. Push the branch and read the result:
#
#     git push -u origin design/v2-remainder
#     gh run list -L 3
#     gh run watch
#
# Usage:
#   ./gate.sh                  # analyze/format the CI-equivalent tree
#   ./gate.sh lib/src/design test/design
#   ./gate.sh --all            # same as the default; retained for compatibility
set -uo pipefail

cd "$(dirname "$0")"

# Resolve the FVM-pinned SDK once, instead of paying FVM's wrapper dispatch once
# per check. `dart analyze` reads the same analysis_options.yaml as
# `flutter analyze`, without the Flutter tool wrapper. Fall back to the
# previous `fvm` commands when the pinned SDK cannot be resolved directly.
ANALYZE_CMD=(fvm flutter analyze)
FORMAT_CMD=(fvm dart format)
PUB_CMD=(fvm flutter pub get)
if [[ -r .fvmrc ]] && command -v fvm >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  _fvm_version="$(jq -r '.flutter // empty' .fvmrc 2>/dev/null)"
  _fvm_cache="$(fvm api context 2>/dev/null | jq -r '.context.versionsCachePath // empty' 2>/dev/null)"
  if [[ -n "${_fvm_version:-}" && -n "${_fvm_cache:-}" \
    && -x "${_fvm_cache}/${_fvm_version}/bin/flutter" \
    && -x "${_fvm_cache}/${_fvm_version}/bin/dart" ]]; then
    ANALYZE_CMD=("${_fvm_cache}/${_fvm_version}/bin/dart" analyze)
    FORMAT_CMD=("${_fvm_cache}/${_fvm_version}/bin/dart" format)
    PUB_CMD=("${_fvm_cache}/${_fvm_version}/bin/flutter" pub get)
  fi
fi

if [[ $# -gt 0 && "${1:-}" != "--all" ]]; then
  ANALYZE_PATHS=("$@")
  FORMAT_PATHS=("$@")
else
  # Default to the same scope CI checks. The previous default enumerated a fixed
  # list of branch paths; that list had gone stale and no longer covered every
  # Dart file changed on this branch. Directory roots also avoid passing a large
  # number of individual paths to the analyzer. `lib` is still scoped to
  # `lib/src` because `lib/l10n` is generated and has never been formatted.
  ANALYZE_PATHS=(lib/src test)
  # Mirror CI's format exclusions: generated files are the code generator's
  # output, not hand-written code, and CI never checks them.
  mapfile -t FORMAT_PATHS < <(find lib/src test -name '*.dart' -not \( -name '*.*freezed.dart' -o -name '*.*g.dart' -o -name '*lichess_icons.dart' \))
fi

# `flutter analyze` used to resolve dependencies implicitly on every run. Do it
# only when the package config is missing or older than the pubspec files, so
# the inner loop skips it when dependencies are already resolved. This guard is
# also required for correctness: without a package config, `dart analyze` and
# `dart format` cannot resolve analysis_options.yaml's includes (notably the
# formatter's page_width), producing false failures across the tree.
if [[ ! -f .dart_tool/package_config.json || pubspec.yaml -nt .dart_tool/package_config.json || pubspec.lock -nt .dart_tool/package_config.json ]]; then
  echo "==> pub get (package config missing or stale)"
  "${PUB_CMD[@]}" || exit 1
fi

echo "==> analyze + format (parallel)"
ANALYZE_STATUS=0
FORMAT_STATUS=0
"${ANALYZE_CMD[@]}" "${ANALYZE_PATHS[@]}" &
ANALYZE_PID=$!
"${FORMAT_CMD[@]}" --output=none --set-exit-if-changed "${FORMAT_PATHS[@]}" &
FORMAT_PID=$!
wait "$ANALYZE_PID" || ANALYZE_STATUS=$?
wait "$FORMAT_PID" || FORMAT_STATUS=$?

if (( ANALYZE_STATUS != 0 )); then
  echo "FAIL: ${ANALYZE_CMD[*]} ${ANALYZE_PATHS[*]}"
fi
if (( FORMAT_STATUS != 0 )); then
  echo "FAIL: formatting issues found."
  echo "run: ${FORMAT_CMD[*]} --output=none --set-exit-if-changed ${FORMAT_PATHS[*]}"
fi
if (( ANALYZE_STATUS != 0 || FORMAT_STATUS != 0 )); then
  exit 1
fi

cat <<'EOF'

Local gate green: analyze and format clean.

NOT verified locally, by design: `flutter test`. It overloads this machine. Run it in CI:

    git push -u origin design/v2-remainder
    gh run watch

Per AGENTS.md §4, a runtime launch on a real device or the Linux desktop build is still
owed before the branch counts as done — `./verify` and screenshots are not evidence of a
visual pass.
EOF

