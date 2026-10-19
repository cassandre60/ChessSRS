#!/usr/bin/env bash
# Tests for nightly-decide.sh, which decides whether the nightly build is
# worth the runner minutes.
#
# Both ways this can be wrong are silent: a nightly that never fires leaves
# the owner testing a stale app, and one that always fires spends a release
# build per night on commits that changed nothing it ships. Each case below is
# a small real git repository, so the comparisons run against actual history.
#
# `gh` is faked by putting a stub earlier on PATH, which leaves the script
# under test unmodified — no test-only branch inside it.
#
# Run from anywhere: bash .github/scripts/nightly-decide-test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/nightly-decide.sh"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  PASS %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s — %s\n' "$1" "$2"; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Stands in for `gh run list --json … --jq <filter>`: prints the JSON the case
# supplies, with @HEAD@ replaced by the commit under test (a fresh repo per
# case has a fresh SHA, so the test never has to know it), then applies the
# caller's own jq filter — gh applies it, so a stub that ignored it would test
# a different thing than CI runs.
json="${FAKE_GH_RUNS:-[]}"
json="${json//@HEAD@/$(git rev-parse HEAD 2>/dev/null || echo unknown)}"
filter=""
while [ $# -gt 0 ]; do
  if [ "$1" = "--jq" ]; then filter="$2"; fi
  shift
done
printf '%s\n' "$json" | jq -r "$filter"
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

NEEDED=""
REASON=""

# run <setup-commands> <prior-release-runs-json>
# Builds a throwaway repo, applies the setup, then runs the script against it.
run() {
  rm -rf "$WORK/repo"
  mkdir -p "$WORK/repo"
  (
    cd "$WORK/repo" || exit 1
    git init -q -b main
    git config user.email test@example.com
    git config user.name Test
    eval "$1" >/dev/null 2>&1
  )
  : >"$WORK/out"
  ( cd "$WORK/repo" && FAKE_GH_RUNS="$2" GITHUB_OUTPUT="$WORK/out" \
    bash "$SCRIPT" ) >"$WORK/log" 2>&1
  NEEDED="$(sed -n 's/^needed=//p' "$WORK/out")"
  REASON="$(sed -n 's/^reason=//p' "$WORK/out")"
}

# The repository state each case starts from: a tagged base commit.
BASE='git commit -q --allow-empty -m base; git tag v1.0.0'

# A commit that changes one shipped path.
shipped_commit() {
  printf '%s\n     mkdir -p "$(dirname %s)"; echo x >%s; git add -A; git commit -q -m change' \
    "$BASE" "$1" "$1"
}

echo "nightly-decide.sh:"

run 'git commit -q --allow-empty -m base' '[]'
if [ "$NEEDED" = "true" ]; then
  ok "builds when nothing has ever been tagged"
else
  bad "no tags" "needed='$NEEDED'"
fi

run "$BASE" '[]'
if [ "$NEEDED" = "false" ] && [[ "$REASON" == *"tip of main"* ]]; then
  ok "skips when main has not moved since the tag"
else
  bad "no movement" "needed='$NEEDED' reason='$REASON'"
fi

run "$BASE
     mkdir -p test redteam scripts/gates .gates docs
     echo x >test/a_test.dart; echo x >redteam/case.json
     echo x >scripts/gates/x.py; echo x >.gates/baseline.json
     echo x >docs/note.md
     git add -A; git commit -q -m 'tests, gates and docs only'" '[]'
if [ "$NEEDED" = "false" ] && [[ "$REASON" == *"none of them shipped code"* ]]; then
  ok "skips when only tests, gates and docs changed since the tag"
else
  bad "invisible delta" "needed='$NEEDED' reason='$REASON'"
fi

run "$(shipped_commit lib/feature.dart)" '[]'
if [ "$NEEDED" = "true" ] && [[ "$REASON" == *"shipped files changed"* ]]; then
  ok "builds when lib/ changed and this commit was never built"
else
  bad "shipped change" "needed='$NEEDED' reason='$REASON'"
fi

# Each entry: the literal JSON value for "conclusion", what it means, and the
# decision it implies. A successful run and a still-running one both mean
# "already built"; a failed or cancelled one means "build again".
while IFS='|' read -r conclusion expected label; do
  [ -z "$conclusion" ] && continue
  run "$(shipped_commit lib/feature.dart)" \
    "[{\"headSha\":\"@HEAD@\",\"conclusion\":$conclusion}]"
  if [ "$NEEDED" = "$expected" ]; then
    ok "$label → needed=$NEEDED"
  else
    bad "$label" "needed='$NEEDED' (expected $expected), reason='$REASON'"
  fi
done <<'CASES'
"success"|false|skips a commit a successful Release run already built
null|false|skips a commit whose build is still running
"failure"|true|retries a commit whose previous build failed
"cancelled"|true|retries a commit whose previous build was cancelled
CASES

run "$(shipped_commit lib/feature.dart)" \
  "[{\"headSha\":\"0000000000000000000000000000000000000000\",\"conclusion\":\"success\"}]"
if [ "$NEEDED" = "true" ]; then
  ok "ignores a run of an older commit"
else
  bad "stale run" "needed='$NEEDED' — an old run suppressed a needed build"
fi

# Every path that changes what the owner downloads must count as shipped.
for path in lib/a.dart assets/book.json android/app/build.gradle \
  linux/CMakeLists.txt pubspec.yaml pubspec.lock; do
  run "$(shipped_commit "$path")" '[]'
  if [ "$NEEDED" = "true" ]; then
    ok "$path counts as a shipped change"
  else
    bad "$path" "needed='$NEEDED' — a change to $path would never be built"
  fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
