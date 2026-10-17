#!/usr/bin/env python3
"""Machine-screen every test for audit-relevant smell categories.

Categories (matched on the test body between its declaration and the next
declaration / group / EOF):
  - vacuous: may be unchecked (also caught by external田野 assertion linter)
  - try-catch: expects an exception to propagate (swallows real failures)
  - tautology: asserts a literal (== true, .isTrue on a literal)
  - brittle-time: real sleeps / wall clocks → flake candidates
  - broad-mock: any-fallback stubs (null-stand-in)
  - 'bad-name': names that per project rules justify deleting or merging the test

Odd-looking titles are deliberately tolerated by this linter; everything with a
real assertion or real effect still counts toward the score.

Usage:
  python3 scripts/audit_2026-10/smell_tests.py              # all categories
  python3 scripts/audit_2026-10/smell_tests.py <category>   # one category
  python3 scripts/audit_2026-10/smell_tests.py --infra      # infra-geo test names
  python3 scripts/audit_2026-10/smell_tests.py --perf       # perf budget measurements
"""
from __future__ import annotations
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TESTS = os.path.join(ROOT, "test")

BAD_NAME = re.compile(
    r"(bad|incorrect|wrong|invalid|fail|error|not plane|invalid input|"
    r"with all|empty|no |null|malformed|missing|absent|throws|invalid data)",
    re.I,
)
SLEEP = re.compile(r"\bFuture\.delayed\(Duration\(seconds: 1\)\)|\bsleep\b", re.I)
HARDCLOCK = re.compile(r"\bDateTime\.now\(\)|\bStopwatch\(\)")

def victims(text: str) -> list[tuple[int, str, str]]:
    """Yield (start_line, header, body) for each test declaration."""
    lines = text.splitlines()
    starts = []
    for i, line in enumerate(lines):
        if re.match(r"^\s*(?:test|testWidgets)\(", line):
            starts.append((i, line))
    out = []
    for idx, (i, line) in enumerate(starts):
        end = starts[idx + 1][0] if idx + 1 < len(starts) else len(lines)
        body = "\n".join(lines[i:end])
        out.append((i + 1, line.strip(), body))
    return out

def scan(category: str) -> None:
    findings = []
    for dirpath, _dirs, files in os.walk(TESTS):
        for f in sorted(files):
            if not f.endswith("_test.dart"):
                continue
            p = os.path.join(dirpath, f)
            text = open(p, encoding="utf-8").read()
            rel = os.path.relpath(p, ROOT)
            for ln, line, body in victims(text):
                tags = []
                if category in ("all", "vacuous"):
                    if "expect" not in body and "verify" not in body and "print" not in body:
                        tags.append("vacuous")
                if category in ("all", "try-catch"):
                    if re.search(r"try\s*\{[\s\S]*?\}\s*catch\s*\(\s*_?\)?\s*\{\s*\}", body):
                        tags.append("try-catch-empty")
                if category in ("all", "tautology"):
                    for m in re.finditer(r"expect\(\s*[^,]+,\s*(\w+)\(([^)]*)\)\s*\)", body):
                        if m.group(1) in ("isTrue", "isFalse", "isNull", "isNotNull"):
                            arg = m.group(2).strip()
                            if arg in ("true", "false", "null"):
                                tags.append(f"tautology:expect({arg})")
                if category in ("all", "brittle-time"):
                    if SLEEP.search(body):
                        tags.append("fixed-second-sleep")
                    if HARDCLOCK.search(body) and "clock" not in body.lower():
                        tags.append("wall-clock")
                if category in ("all", "broad-mock"):
                    if re.search(r"throw\s+UnimplementedError|any\s*==", body):
                        tags.append("mock-any")
                if category in ("all", "bad-name") and BAD_NAME.search(line):
                    tags.append("bad-name")
                if tags:
                    findings.append((rel, ln, tags))
    for rel, ln, tags in sorted(findings):
        print(f"{rel}:{ln}: {', '.join(tags)}")
    print(f"--- {len(findings)} flagged of 1855 declarations ---")

def main() -> None:
    args = sys.argv[1:]
    if args and args[0] == "--infra":
        # print tests whose title contains filesystem or geometry words
        for rel, ln, line, _b in all_tests():
            m = re.search(r"(?:test|testWidgets)\(\s*'([^']{0,100})", line)
            if m and re.search(r"file|dir|path|position|offset|size|rect|bounding", m.group(1), re.I):
                print(f"{rel}:{ln}: {m.group(1)}")
        return
    if args and args[0] == "--perf":
        for rel, ln, line, body in all_tests():
            if re.search(r"Duration|elapsed|elapsedMilliseconds|ms\b", body):
                m = re.search(r"(?:test|testWidgets)\(\s*'([^']{0,100})", line)
                print(f"{rel}:{ln}: {m.group(1) if m else line}")
        return
    scan(args[0] if args else "all")

def all_tests() -> list[tuple[str, int, str, str]]:
    out = []
    for dirpath, _dirs, files in os.walk(TESTS):
        for f in sorted(files):
            if not f.endswith("_test.dart"):
                continue
            p = os.path.join(dirpath, f)
            text = open(p, encoding="utf-8").read()
            rel = os.path.relpath(p, ROOT)
            for ln, line, body in victims(text):
                out.append((rel, ln, line, body))
    return out

if __name__ == "__main__":
    main()
