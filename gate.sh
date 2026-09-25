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
#   ./gate.sh                  # analyze the paths this branch touched
#   ./gate.sh lib/src/design test/design
#   ./gate.sh --all            # analyze the whole tree
set -uo pipefail

cd "$(dirname "$0")"

if [[ "${1:-}" == "--all" ]]; then
  ANALYZE_PATHS=(lib test)
elif [[ $# -gt 0 ]]; then
  ANALYZE_PATHS=("$@")
else
  ANALYZE_PATHS=(lib/src/navigation.dart
                 lib/src/widgets/platform.dart
                 lib/src/app.dart
                 lib/src/design
                 lib/src/view/review
                 lib/src/view/settings
                 lib/src/view/analysis
                 lib/src/view/explorer
                 test/design
                 test/view
                 test/app_links_service_test.dart
                 test/test_provider_scope.dart)
fi

echo "==> analyze"
fvm flutter analyze "${ANALYZE_PATHS[@]}" || exit 1

echo "==> format check"
fvm dart format --output=none --set-exit-if-changed "${ANALYZE_PATHS[@]}" || {
  echo "run: fvm dart format ${ANALYZE_PATHS[*]}"
  exit 1
}

cat <<'EOF'

Local gate green: analyze and format clean.

NOT verified locally, by design: `flutter test`. It overloads this machine. Run it in CI:

    git push -u origin design/v2-remainder
    gh run watch

Per AGENTS.md §4, a runtime launch on a real device or the Linux desktop build is still
owed before the branch counts as done — `./verify` and screenshots are not evidence of a
visual pass.
EOF

