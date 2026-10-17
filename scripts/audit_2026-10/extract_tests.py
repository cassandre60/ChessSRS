#!/usr/bin/env python3
"""Enumerate every test declaration in the suite.

Extracts test( / testWidgets( declarations from *_test.dart files with their
venues (group nesting via indentation is unreliable; we track groups), so the
audit can walk the suite one test at a time.

Usage: python3 scripts/audit_2026-10/extract_tests.py [output.json]
"""
from __future__ import annotations
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TESTS = os.path.join(ROOT, "test")

DECL = re.compile(r"^(\s*)((?:test|testWidgets)\(\s*)$", re.M)
DECL_INLINE = re.compile(r"^(\s*)(test|testWidgets)\(\s*(?:\n|')", re.M)
GROUP = re.compile(r"^(\s*)group\(\s*'([^']*)'", re.M)

def is_ascii_word(s: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z0-9 _.,:()/-]{0,120}", s))

def extract(path: str) -> list[dict]:
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return []
    lines = text.splitlines()
    out = []
    group_stack: list[tuple[int, str]] = []
    for i, line in enumerate(lines):
        stripped = line.strip()
        m = GROUP.match(line)
        if m:
            indent = len(m.group(1))
            while group_stack and group_stack[-1][0] >= indent:
                group_stack.pop()
            group_stack.append((indent, m.group(2)))
            continue
        if re.match(r"^\s*(?:test|testWidgets)\(", line):
            indent = len(line) - len(line.lstrip())
            while group_stack and group_stack[-1][0] >= indent:
                group_stack.pop()
            groups = [g[1] for g in group_stack]
            # location fingerprint nearest non-empty line for cross-referencing
            out.append({
                "file": os.path.relpath(path, ROOT),
                "line": i + 1,
                "groups": groups,
                "decl": stripped,
            })
    return out

def main() -> None:
    inventory = []
    for dirpath, _dirs, files in os.walk(TESTS):
        for f in sorted(files):
            if not f.endswith("_test.dart"):
                continue
            p = os.path.join(dirpath, f)
            inventory.extend(extract(p))
    summary = os.path.basename(sys.argv[1]) if len(sys.argv) > 1 else "inventory.json"
    out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), summary)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump({"total": len(inventory), "tests": inventory}, fh, indent=1)
    print(f"{len(inventory)} test declarations in "
          f"{len({t['file'] for t in inventory})} files -> {out_path}")

if __name__ == "__main__":
    main()
