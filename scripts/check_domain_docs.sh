#!/usr/bin/env bash
# check_domain_docs.sh - Check domain layer has basic documentation
# Exits with non-zero if domain layer has missing documentation

set -euo pipefail

echo "Checking domain layer documentation..."

# Check that key domain files have library directives and basic documentation
files=(
    "lib/src/domain/domain.dart"
    "lib/src/domain/scheduler.dart"
    "lib/src/domain/chess_fsrs_scheduler.dart"
    "lib/src/domain/review/review_session.dart"
    "lib/src/domain/review/review_engine.dart"
    "lib/src/domain/review/review_scope.dart"
    "lib/src/domain/review/review_mode.dart"
    "lib/src/domain/review/review_prompt.dart"
    "lib/src/domain/review/review_step_result.dart"
    "lib/src/domain/review/transpose_scope.dart"
    "lib/src/domain/chapter.dart"
    "lib/src/domain/study.dart"
    "lib/src/domain/repertoire_decision.dart"
    "lib/src/domain/repertoire_move.dart"
    "lib/src/domain/repertoire_node.dart"
    "lib/src/domain/repertoire_progress.dart"
    "lib/src/domain/position_knowledge_state.dart"
    "lib/src/domain/review_result.dart"
    "lib/src/domain/review_state.dart"
    "lib/src/domain/ids.dart"
    "lib/src/domain/clock.dart"
)

errors=0

for file in "${files[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo "WARNING: $file not found"
        continue
    fi
    
    # Check for library directive
    if ! grep -q '^library ' "$file"; then
        echo "WARNING: $file missing library directive"
        ((errors++))
    fi
    
    # Check for basic documentation on public classes (looking for /// before class)
    if grep -q '^class [A-Z]' "$file"; then
        # Check if class has documentation
        if ! grep -B2 '^class [A-Z]' "$file" | grep -q '///'; then
            echo "WARNING: $file has undocumented class"
            ((errors++))
        fi
    fi
done

if [[ $errors -gt 0 ]]; then
    echo "ERROR: Found $errors documentation issues in domain layer"
    exit 1
fi

echo "Domain layer basic documentation check passed!"
exit 0
