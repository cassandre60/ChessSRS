#!/usr/bin/env bash
# check_dartdoc_domain.sh - Check dartdoc coverage for domain layer
# Exits with non-zero if domain layer has undocumented public APIs

set -euo pipefail

echo "Checking dartdoc coverage for domain layer..."

# Run dartdoc on domain layer only
output=$(fvm dart doc lib/src/domain --dry-run 2>&1)

# Check for warnings about undocumented public APIs
if echo "$output" | grep -q "warning.*has no documentation"; then
    echo "ERROR: Domain layer has undocumented public APIs:"
    echo "$output" | grep "warning.*has no documentation"
    exit 1
fi

if echo "$output" | grep -q "warning.*has no documentation"; then
    exit 1
fi

# Check for the "no documentable libraries" warning which indicates no public APIs found
if echo "$output" | grep -q "has no documentable libraries"; then
    echo "WARNING: No documentable libraries found in domain layer"
    exit 1
fi

echo "Domain layer dartdoc check passed!"
exit 0
