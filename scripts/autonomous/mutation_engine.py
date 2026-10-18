#!/usr/bin/env python3
"""Autonomous Mutation Engine for Dart / Flutter Codebases.

Generates targeted, high-signal semantic mutations in Dart source files to
mechanically expose blindspots in the test suite without running full workspace suites.

IMPORTANT — Limitations (read before trusting output):
  - This engine is REGEX-BASED, not AST-based. It can mutate string literals,
    comments, and the wrong occurrence of &&/||. Every surviving mutant must be
    triaged by a human — many are equivalent mutants or noise.
  - Uncompilable mutants are reported separately from killed mutants; the summary
    distinguishes the two so kill-rate is not inflated by compile failures.
  - TIMEOUT is a third non-kill bucket: a timed-out test run is not evidence of
    a kill, so timed-out mutants are excluded from BOTH the kill-rate numerator
    and denominator (reported like UNCOMPILABLE). The timeout used is printed in
    the summary.
  - Generic type-argument lists: the strict < / > relational rules used to fire
    inside `Foo<Bar>` / `Map<K, V>` because `<` and `>` are also angle brackets.
    A heuristic now skips a < or > match when the `<` is immediately preceded
    by an identifier char (no whitespace) and the content up to the matching `>`
    is type-like (letters/digits/underscore/dot/comma/space/?/< >). This covers
    formatted Dart style (`List<String>`, `Map<String, DateTime>`) and is
    imperfect: spaced generics, function-type arguments and tight comparisons
    may still slip through or be skipped; triage survivors accordingly.
  - Null-promotion blindspot (NOT fixed here): `!= null` -> `== null` and
    `&&` -> `||` can remove null-flow promotion and produce uncompilable
    mutants rather than real gaps.
  - String literals / comments can still be mutated despite the quote heuristic.
  - Candidate windowing is mechanical, not signal-ranked: --start skips the
    first N candidates in file order; --max-mutants caps the shard size. Total
    coverage requires repeating shards until exhaustion; order is unchanged.
  - Promotion to blocking CI is gated on GATES_PLAN.md row 9 (two green runs
    without false positives).

Usage:
  python3 scripts/autonomous/mutation_engine.py \
    --source lib/src/domain/review_coordinator.dart \
    --test-cmd "fvm flutter test test/domain/review_coordinator_test.dart" \
    --max-mutants 20 --start 0 --timeout 240 \
    --output-issue docs/tasks/surviving_mutants.md

  # Shard the full candidate list (example: 55 candidates -> 3 shards):
  python3 scripts/autonomous/mutation_engine.py --source X --test-cmd "..." --max-mutants 20 --skip-m 0
  python3 scripts/autonomous/mutation_engine.py --source X --test-cmd "..." --max-mutants 20 --skip-m 20
  python3 scripts/autonomous/mutation_engine.py --source X --test-cmd "..." --max-mutants 20 --skip-m 40
"""

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
import time
from typing import Dict, List, Optional, Tuple

# Mutation patterns: (Regex pattern, replacement, description).
# Applied per-line, skipping comment/import/part lines. Still regex-based —
# see module docstring for why survivors need human triage.
MUTATION_RULES: List[Tuple[str, str, str]] = [
    # Relational & Equality (ordered: specific before general)
    (r'\b([a-zA-Z0-9_\.]+)\s*==\s*([a-zA-Z0-9_\.]+)', r'\1 != \2', 'Invert equality == to !='),
    (r'\b([a-zA-Z0-9_\.]+)\s*!=\s*([a-zA-Z0-9_\.]+)', r'\1 == \2', 'Invert inequality != to =='),
    (r'\b([a-zA-Z0-9_\.]+)\s*<\s*([a-zA-Z0-9_\.]+)', r'\1 <= \2', 'Loosen strict inequality < to <='),
    (r'\b([a-zA-Z0-9_\.]+)\s*>\s*([a-zA-Z0-9_\.]+)', r'\1 >= \2', 'Loosen strict inequality > to >='),
    (r'\b([a-zA-Z0-9_\.]+)\s*<=\s*([a-zA-Z0-9_\.]+)', r'\1 < \2', 'Tighten inequality <= to <'),
    (r'\b([a-zA-Z0-9_\.]+)\s*>=\s*([a-zA-Z0-9_\.]+)', r'\1 > \2', 'Tighten inequality >= to >'),

    # Logical
    (r'&&', r'||', 'Swap logical AND (&&) to OR (||)'),
    (r'\|\|', r'&&', 'Swap logical OR (||) to AND (&&)'),
    (r'\btrue\b', r'false', 'Invert boolean literal true to false'),
    (r'\bfalse\b', r'true', 'Invert boolean literal false to true'),

    # Collection & String tests
    (r'\.isNotEmpty\b', r'.isEmpty', 'Invert .isNotEmpty to .isEmpty'),
    (r'\.isEmpty\b', r'.isNotEmpty', 'Invert .isEmpty to .isNotEmpty'),
    (r'\.first\b', r'.last', 'Swap .first to .last'),
    (r'\.last\b', r'.first', 'Swap .last to .first'),

    # Null checks
    (r'\b([a-zA-Z0-9_\.]+)\s*!=\s*null\b', r'\1 == null', 'Invert null check != null to == null'),
    (r'\b([a-zA-Z0-9_\.]+)\s*==\s*null\b', r'\1 != null', 'Invert null check == null to != null'),

    # Off-by-one arithmetic
    (r'\+\s*1\b', r'+ 2', 'Off-by-one: + 1 to + 2'),
    (r'\-\s*1\b', r'- 2', 'Off-by-one: - 1 to - 2'),
]


class Mutation:
    def __init__(self, file_path: str, line_no: int, original_text: str, mutated_text: str, description: str):
        self.file_path = file_path
        self.line_no = line_no
        self.original_text = original_text
        self.mutated_text = mutated_text
        self.description = description

    def to_dict(self) -> Dict:
        return {
            "file": self.file_path,
            "line": self.line_no,
            "original": self.original_text.strip(),
            "mutated": self.mutated_text.strip(),
            "description": self.description,
        }


def _split_test_cmd(test_cmd: str) -> List[str]:
    """Split test_cmd safely; falls back to shell if needed."""
    try:
        return shlex.split(test_cmd)
    except ValueError:
        return [test_cmd]


def _run_test_cmd(test_cmd: str, timeout: int) -> Tuple[int, str, str, float, bool]:
    """Run test_cmd without shell=True. Returns (returncode, stdout, stderr, elapsed, timed_out)."""
    argv = _split_test_cmd(test_cmd)
    start = time.time()
    try:
        # Use argv directly — no shell injection surface.
        res = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return res.returncode, res.stdout, res.stderr, time.time() - start, False
    except subprocess.TimeoutExpired as exc:
        out = exc.stdout.decode() if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        err = exc.stderr.decode() if isinstance(exc.stderr, bytes) else (exc.stderr or "")
        return 1, out, err, float(timeout), True
    except FileNotFoundError as exc:
        return 2, "", str(exc), time.time() - start, False


def _is_compile_failure(stdout: str, stderr: str) -> bool:
    """Heuristic: Dart compile failures contain these markers."""
    combined = (stdout + "\n" + stderr).lower()
    markers = [
        "error: ",
        "couldn't find",
        "not found:",
        "failed to compile",
        "dart compilation failed",
        "unexpected token",
        "expected ';'",
        "undefined name",
    ]
    return any(m in combined for m in markers)


def _is_generic_angle_match(desc: str, match: re.Match, line: str) -> bool:
    """Heuristic: True if this relational < / > match sits inside a generic
    type-argument list (e.g. List<String>, Map<K, V>) and should be skipped.

    Only applies to the two strict-inequality rules (< -> <= and > -> >=);
    the <= / >= rules never match angle brackets in practice.
    """
    is_lt = desc.startswith("Loosen strict inequality < to <=")
    is_gt = desc.startswith("Loosen strict inequality > to >=")
    if not (is_lt or is_gt):
        return False

    op_char = "<" if is_lt else ">"
    text = match.group(0)
    op_offset = text.find(op_char)
    if op_offset < 0:
        return False
    op_pos = match.start() + op_offset

    if is_lt:
        # Generic open bracket is immediately preceded by an identifier char
        # (no whitespace): `List<String>`, not `a < b` (formatted with spaces).
        if op_pos == 0 or not (line[op_pos - 1].isalnum() or line[op_pos - 1] == "_"):
            return False
        close = line.find(">", op_pos + 1)
        if close == -1:
            return False
        content = line[op_pos + 1:close]
        return re.fullmatch(r"[\w\s,?<>]*", content) is not None
    else:
        # For >, find the nearest preceding < that is a generic open.
        lt_pos = line.rfind("<", 0, op_pos)
        if lt_pos == -1:
            return False
        if lt_pos == 0 or not (line[lt_pos - 1].isalnum() or line[lt_pos - 1] == "_"):
            return False
        content = line[lt_pos + 1:op_pos]
        return re.fullmatch(r"[\w\s,?<>]*", content) is not None


def generate_mutations(source_path: str) -> List[Mutation]:
    """Generates candidate mutations from a Dart source file."""
    mutations: List[Mutation] = []
    with open(source_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    for line_idx, line in enumerate(lines):
        stripped = line.strip()
        # Skip comments, imports, exports, and blank lines
        if not stripped or stripped.startswith("//") or stripped.startswith("/*") or stripped.startswith("*"):
            continue
        if stripped.startswith("import ") or stripped.startswith("export ") or stripped.startswith("part "):
            continue
        # Skip lines that are purely string literals / annotations to reduce noise
        # (heuristic: line is mostly inside quotes)
        if stripped.startswith('"') or stripped.startswith("'") or stripped.startswith("@"):
            continue

        for pattern, replacement, desc in MUTATION_RULES:
            matches = list(re.finditer(pattern, line))
            for match in matches:
                # Skip matches inside string literals (odd number of quotes before match)
                prefix = line[:match.start()]
                if prefix.count('"') % 2 == 1 or prefix.count("'") % 2 == 1:
                    continue
                # Skip relational < / > matches that sit inside a generic type
                # argument list (e.g. List<String>, Map<K, V>). Heuristic only.
                if _is_generic_angle_match(desc, match, line):
                    continue
                start, end = match.span()
                sub = re.sub(pattern, replacement, line[start:end])
                mutated_line = line[:start] + sub + line[end:]
                if mutated_line != line:
                    mutations.append(Mutation(
                        file_path=source_path,
                        line_no=line_idx + 1,
                        original_text=line,
                        mutated_text=mutated_line,
                        description=desc,
                    ))

    return mutations


def run_mutation_pass(source_path: str, test_cmd: str, max_mutants: int = 50, start: int = 0, timeout: int = 240) -> Tuple[List[Dict], List[Dict], int, int]:
    """Runs mutation testing on source_path against test_cmd.

    Returns (killed, survived, uncompilable_count). Uncompilable mutants are not
    counted as killed — they indicate an equivalent or syntactically invalid mutant,
    not a gap closed by tests.
    """
    print(f"[*] Reading source file: {source_path}")
    with open(source_path, "r", encoding="utf-8") as f:
        original_content = f.read()

    print("[*] Running baseline test verification...")
    rc, out, err, _, _ = _run_test_cmd(test_cmd, timeout)
    if rc != 0:
        print(f"[!] Baseline tests failed. Cannot mutate while test is failing:\n{out}\n{err}")
        sys.exit(2)
    print("    [+] Baseline tests passed cleanly.")

    mutations = generate_mutations(source_path)
    print(f"[*] Generated {len(mutations)} candidate mutations across {source_path}")
    if start:
        print(f"    Skipping first {start} candidates (--start).")
    if start + max_mutants < len(mutations):
        print(f"    Window: candidates {start}..{start + max_mutants - 1} of {len(mutations)} (file order, not ranked).")
    mutations = mutations[start:start + max_mutants]
    if not mutations:
        print("    No candidates in this window.")
    else:
        print(f"    Evaluating {len(mutations)} candidate(s) in this shard.")

    survived: List[Dict] = []
    killed: List[Dict] = []
    uncompilable: int = 0
    timed_out: int = 0

    lines = original_content.splitlines(keepends=True)

    for i, mut in enumerate(mutations, start=1):
        line_idx = mut.line_no - 1
        mutated_lines = list(lines)
        mutated_lines[line_idx] = mut.mutated_text

        try:
            with open(source_path, "w", encoding="utf-8") as f:
                f.writelines(mutated_lines)

            rc, out, err, elapsed, was_timeout = _run_test_cmd(test_cmd, timeout)

            if was_timeout:
                timed_out += 1
                print(f"  [{i}/{len(mutations)}] TIMEOUT ({elapsed:.1f}s, cap {timeout}s): Line {mut.line_no}: {mut.description} — not counted as killed")
            elif rc != 0:
                if _is_compile_failure(out, err):
                    uncompilable += 1
                    print(f"  [{i}/{len(mutations)}] UNCOMPILABLE ({elapsed:.1f}s): Line {mut.line_no}: {mut.description} — not counted as killed")
                else:
                    killed.append(mut.to_dict())
                    print(f"  [{i}/{len(mutations)}] KILLED ({elapsed:.1f}s): Line {mut.line_no}: {mut.description}")
            else:
                survived.append(mut.to_dict())
                print(f"  [{i}/{len(mutations)}] SURVIVED! Line {mut.line_no}: {mut.original_text.strip()} -> {mut.mutated_text.strip()} ({mut.description})")

        finally:
            with open(source_path, "w", encoding="utf-8") as f:
                f.write(original_content)

    total = len(killed) + len(survived) + uncompilable + timed_out
    killable = len(killed) + len(survived)
    score = (len(killed) / killable * 100) if killable > 0 else 100.0
    print("\n" + "=" * 60)
    print(f"MUTATION TESTING SUMMARY for {source_path}")
    print(f"Timeout used: {timeout}s per mutant run")
    print(f"Total Mutants Evaluated: {total}  (killable: {killable}, uncompilable: {uncompilable}, timed_out: {timed_out})")
    print(f"Killed (Checked by tests): {len(killed)}")
    print(f"Survived (Test gaps!):     {len(survived)}")
    if uncompilable:
        print(f"Uncompilable (noise):      {uncompilable} — excluded from kill rate")
    if timed_out:
        print(f"Timed out (not a kill):    {timed_out} — excluded from kill rate")
    print(f"Mutation Kill Rate:        {score:.1f}%  (killed / killable)")
    if survived:
        print("NOTE: Every survivor needs human triage — many are equivalent mutants.")
    print("=" * 60)

    return killed, survived, uncompilable, timed_out


def format_issue_markdown(surviving_mutant: Dict, test_cmd: str) -> str:
    """Formats a surviving mutant as a ready-to-file GitHub Issue markdown."""
    file = surviving_mutant["file"]
    line = surviving_mutant["line"]
    orig = surviving_mutant["original"]
    mutated = surviving_mutant["mutated"]
    desc = surviving_mutant["description"]

    return f"""### Test Gap: Surviving Mutant in `{file}:{line}`

#### Description
The automated mutation engine applied the following semantic mutation:
**{desc}**

> **Triage required:** This engine is regex-based. Confirm the mutant is not
> inside a string/comment and is not an equivalent mutant before filing.

```diff
--- {file} (line {line})
+++ mutated
- {orig}
+ {mutated}
```

#### Verification
When this mutation was applied, the targeted test suite passed without failure:
```bash
{test_cmd}
```

#### Required Fix
1. Confirm the mutant is a real gap (not equivalent/noise).
2. Add a test in the relevant test suite that fails when this mutation is present.
3. Verify fail-to-pass proof against `origin/main`.
4. Reference the relevant `SPEC.md` invariant.
"""


def main():
    parser = argparse.ArgumentParser(description="Autonomous Dart Mutation Engine (regex-based, triage required)")
    parser.add_argument("--source", required=True, help="Path to Dart source file to mutate")
    parser.add_argument("--test-cmd", required=True, help="Command to run targeted tests (no shell injection — parsed via shlex)")
    parser.add_argument("--max-mutants", type=int, default=30, help="Maximum mutants to evaluate per shard")
    parser.add_argument("--start", "--skip", "--skip-m", dest="start", type=int, default=0, help="Skip the first N candidates (0-based index into the full candidate list)")
    parser.add_argument("--timeout", type=int, default=240, help="Timeout per test run in seconds")
    parser.add_argument("--output-json", help="Path to save results as JSON")
    parser.add_argument("--output-issue", help="Path to save the first surviving mutant as a markdown issue draft")
    args = parser.parse_args()

    killed, survived, uncompilable, timed_out = run_mutation_pass(
        source_path=args.source,
        test_cmd=args.test_cmd,
        max_mutants=args.max_mutants,
        start=args.start,
        timeout=args.timeout,
    )

    if args.output_json:
        os.makedirs(os.path.dirname(os.path.abspath(args.output_json)), exist_ok=True)
        with open(args.output_json, "w", encoding="utf-8") as f:
            json.dump({"source": args.source, "killed": killed, "survived": survived, "uncompilable": uncompilable, "timed_out": timed_out}, f, indent=2)
        print(f"[+] Saved results to {args.output_json}")

    if args.output_issue and survived:
        os.makedirs(os.path.dirname(os.path.abspath(args.output_issue)), exist_ok=True)
        issue_body = format_issue_markdown(survived[0], args.test_cmd)
        with open(args.output_issue, "w", encoding="utf-8") as f:
            f.write(issue_body)
        print(f"[+] Saved issue draft to {args.output_issue}")

    sys.exit(1 if survived else 0)


if __name__ == "__main__":
    main()
