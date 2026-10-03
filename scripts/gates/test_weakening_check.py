#!/usr/bin/env python3
"""Heuristic detector for changes that weaken the test suite or silence analyzers.

Adapted from the agent-proof-codebase skill template for this repo's Dart/Flutter
conventions. Scans `git diff -U0 BASE...HEAD` and reports:
  - removed assertion-like lines in test files (`expect`, `expectLater`, `assert`)
  - removed test-case declarations in test files
  - added `skip:` markers in test files (Dart's skip mechanism)
  - added lint/type suppressions in ANY file
It is a tripwire, not proof: findings require a human (or a justified note in the PR).

Pairing rule (G08 retune): a removed assertion is NOT a finding when an added
assertion in the same file has the same shape — the line with string
literals and `//` comments stripped. That is exactly "same check, new
words" (e.g. a copy rename changing only the expected text). Deleting a
check, or changing its matcher, still fails: the stripped shapes differ.
Fail-closed by construction: an unpaired removal, an empty shape, and any
removed test declaration always report.

Dart tuning (deliberate deviations from the generic template):
  - SKIP matches the `skip:` *named argument* only. It does NOT match `.skip(`,
    which is the Iterable API (`moves.skip(1)`) and the ReviewSession.skip()
    product call; both appear in honest tests and the generic pattern would
    false-positive on them.
  - ASSERT covers `expect`/`expectLater` (flutter_test) plus `assert`.
  - CASE covers `test(`, `testWidgets(` and `group(` declarations.

Exit codes: 0 clean, 4 findings, 2 usage error.
"""
import argparse
import re
import subprocess
import sys

TEST_PATH = re.compile(r"(^|/)(tests?|__tests__|spec|specs|e2e|integration_test)(/|$)|(_test|_spec|\.test|\.spec)\.|(^|/)test_[^/]*$", re.I)
# Inert or self-describing trees are never scanned: the red-team corpus
# deliberately STORES weakening patterns as data, and this script necessarily
# NAMES the patterns it hunts. Both trees are guarded by G07 protected-paths
# instead, so excluding them here loses no coverage of live code.
SKIP_PATH_PREFIXES = ("redteam/", "scripts/gates/")
ASSERT = re.compile(r"\bexpect(Later)?\s*\(|\bassert\s*\(|\bassert\b")
CASE = re.compile(r"^\s*(testWidgets|test|group)\s*\(")
SKIP = re.compile(r"[(,]\s*skip\s*:")
SUPPRESS = re.compile(r"(//\s*ignore_for_file|//\s*ignore:|nolint|# pylint: disable|type:\s*ignore)")
STRING = re.compile(r"'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"")


def shape_of_assertion(text):
    """The check's shape ignoring its words: no string literals, no comments."""
    return STRING.sub("", text).split("//", 1)[0].strip()


def diff_lines(base, head):
    out = subprocess.run(["git", "diff", "-U0", "--no-color", "--no-renames", f"{base}...{head}"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        print(out.stderr, file=sys.stderr)
        sys.exit(2)
    path, lineno = None, 0
    for raw in out.stdout.splitlines():
        if raw.startswith("+++ "):
            path = raw[6:] if raw.startswith("+++ b/") else None
        elif raw.startswith("@@"):
            m = re.search(r"\+(\d+)", raw)
            lineno = int(m.group(1)) if m else 0
        elif raw.startswith("+") and not raw.startswith("+++"):
            yield path, lineno, "+", raw[1:]
            lineno += 1
        elif raw.startswith("-") and not raw.startswith("---"):
            yield path, lineno, "-", raw[1:]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--head", default="HEAD")
    args = ap.parse_args()

    findings = []
    removed_asserts = {}
    added_shapes = {}
    for path, lineno, sign, text in diff_lines(args.base, args.head):
        if not path:
            continue
        if path.startswith(SKIP_PATH_PREFIXES):
            continue
        is_test = bool(TEST_PATH.search(path))
        if sign == "-" and is_test and ASSERT.search(text):
            removed_asserts.setdefault(path, []).append((lineno, shape_of_assertion(text), text.strip()))
        elif sign == "+" and is_test and ASSERT.search(text):
            added_shapes.setdefault(path, []).append(shape_of_assertion(text))
        elif sign == "-" and is_test and CASE.search(text):
            findings.append((path, lineno, "removed test declaration", text.strip()))
        elif sign == "+" and is_test and SKIP.search(text):
            findings.append((path, lineno, "added skip marker in test", text.strip()))
        elif sign == "+" and SUPPRESS.search(text):
            findings.append((path, lineno, "added suppression", text.strip()))
    for path, removed in removed_asserts.items():
        pool = list(added_shapes.get(path, []))
        for lineno, shape, text in removed:
            if shape and shape in pool:
                pool.remove(shape)
            else:
                findings.append((path, lineno, "removed assertion-like line", text))

    if not findings:
        print("no test-weakening patterns found")
        return 0
    print("Possible weakening (needs human judgement):")
    for path, lineno, kind, text in findings:
        print(f"  {path}:{lineno}: {kind}: {text[:110]}")
    print("\nIf intentional, explain in the PR why the removed check is obsolete or where its "
          "coverage moved. Never weaken a check to make a gate pass.")
    return 4


if __name__ == "__main__":
    sys.exit(main())
