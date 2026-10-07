#!/usr/bin/env bash
# ci_failure_summary.sh - Summarize CI failures from GitHub Actions
# Usage: ci_failure_summary.sh <run_id> [repo]

set -euo pipefail

RUN_ID="${1:-}"
REPO="${2:-cassandre60/chess-repertoire-srs}"

if [[ -z "$RUN_ID" ]]; then
    echo "Usage: $0 <run_id> [repo]"
    exit 1
fi

gh run view "$RUN_ID" -R "$REPO" --log-failed 2>/dev/null |
    awk '
    /^##\[error\]/ { in_error=1; print "" }
    in_error { print }
    /^##\[endgroup\]/ { in_error=0 }
    ' | head -100

# Also show failed job names
gh run view "$RUN_ID" -R "$REPO" --json jobs --jq '.jobs[] | select(.conclusion=="failure") | "\(.name) \(.conclusion)"'
