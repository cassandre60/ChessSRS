#!/usr/bin/env bash
# Self-test for scripts/gates/fail_to_pass_check.sh.
#
# The claim under test: the script verifies fail-to-pass WITHOUT touching the
# caller's checkout - it does not detach the caller's HEAD, it does not move
# the caller's branch, and the "must pass" leg really runs at the head ref
# rather than in the caller's working tree.
#
# It used to do all three wrong: the "must pass" leg ran
# `git checkout --detach "$HEAD_REF"` in the CALLER's directory. Verified
# 2026-10-22, on a live fleet: a mutation round lost two commits off its
# branch because this script detached its worktree.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fail_to_pass_check.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILED=0

fail() { echo "FAIL: $1"; FAILED=1; }
ok() { echo "ok: $1"; }

# --- a repo with a bug that a test demonstrates ----------------------------
REPO="$TMP/repo"
mkdir -p "$REPO/tests" "$REPO/src"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name Test
cat >"$REPO/src/thing.py" <<'EOF'
def value():
    return 1
EOF
cat >"$REPO/tests/test_thing.py" <<'EOF'
from src.thing import value


def test_value():
    assert value() == 1
EOF
git -C "$REPO" add -A
git -C "$REPO" commit -qm "base"
BASE="$(git -C "$REPO" rev-parse HEAD)"

# the fix + the test that demonstrates it
cat >"$REPO/src/thing.py" <<'EOF'
def value():
    return 2
EOF
cat >"$REPO/tests/test_thing.py" <<'EOF'
from src.thing import value


def test_value():
    assert value() == 2
EOF
git -C "$REPO" add -A
git -C "$REPO" commit -qm "fix"
HEAD_REF="$(git -C "$REPO" rev-parse HEAD)"

# the caller sits on a BRANCH with a commit of its own
git -C "$REPO" checkout -q -b feature/caller
echo "# caller work" >"$REPO/caller.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "caller commit"
CALLER_BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
CALLER_SHA="$(git -C "$REPO" rev-parse HEAD)"

# --- run the gate from the caller's directory ------------------------------
OUT="$(cd "$REPO" && EXPECT_PATTERN='assert' bash "$SCRIPT" "$BASE" "python3 -m pytest -q tests/test_thing.py" "$HEAD_REF" 2>&1)"
RC=$?

if [[ $RC -eq 0 ]]; then
  ok "the script reports fail-to-pass verified"
else
  fail "the script did not verify fail-to-pass (rc=$RC): $OUT"
fi

# --- the caller's checkout must be untouched -------------------------------
NOW_BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
NOW_SHA="$(git -C "$REPO" rev-parse HEAD)"
if [[ "$NOW_BRANCH" == "$CALLER_BRANCH" ]]; then
  ok "the caller's branch is intact ($NOW_BRANCH)"
else
  fail "the caller's branch changed: $CALLER_BRANCH -> $NOW_BRANCH"
fi
if [[ "$NOW_SHA" == "$CALLER_SHA" ]]; then
  ok "the caller's HEAD is still on its own commit"
else
  fail "the caller's HEAD moved: $CALLER_SHA -> $NOW_SHA"
fi
if git -C "$REPO" rev-parse --verify --quiet HEAD >/dev/null; then
  ok "the caller's HEAD is not detached"
else
  fail "the caller's HEAD is gone"
fi

# --- the "must pass" leg must run at the head ref --------------------------
# A caller whose working tree is DIRTY must not decide the outcome: the leg
# has to test the head commit, not the caller's uncommitted changes.
echo "# uncommitted scratch" >"$REPO/src/thing.py"   # breaks the test
OUT2="$(cd "$REPO" && EXPECT_PATTERN='assert' bash "$SCRIPT" "$BASE" "python3 -m pytest -q tests/test_thing.py" "$HEAD_REF" 2>&1)"
RC2=$?
git -C "$REPO" checkout -q -- src/thing.py
if [[ $RC2 -eq 0 ]]; then
  ok "the 'must pass' leg tests the head ref, not the caller's dirty tree"
else
  fail "the caller's uncommitted changes decided the 'must pass' leg (rc=$RC2): $OUT2"
fi

# --- no worktree left behind ----------------------------------------------
LEFT="$(git -C "$REPO" worktree list | awk '{print $1}' | grep -c "^$TMP/" || true)"
# the main worktree is under $TMP too, so exclude it explicitly
LEFT=$((LEFT - 1))
if [[ "$LEFT" == "0" ]]; then
  ok "no temporary worktree left behind"
else
  fail "$LEFT temporary worktree(s) left behind"
fi

[[ $FAILED -eq 0 ]] && echo "PASS: fail_to_pass_check self-test"
exit $FAILED
