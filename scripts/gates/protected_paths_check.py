#!/usr/bin/env python3
"""Fail when a change touches protected paths (the referee) without approval.

Protected patterns live in a text file, one glob per line ('#' comments allowed).
'*' matches across '/' (fnmatch semantics), so 'tests/golden/*' covers subfolders.

A pattern may carry the directive ``auto=additive-ledger-rows`` (the audit
catalog does). A change that touches *only* such patterns, adds *only* complete
single-target audit rows, and records each target's blob hash at HEAD is
approved automatically: machine bookkeeping should not need a human rubber
stamp. Anything else - an edited or deleted row, a non-row line, a hash that
does not match HEAD, a change to any other protected file, or a PR that bundles
anything besides the catalog - still needs ``--approved``.

Usage:
  protected_paths_check.py --base origin/main [--head HEAD] [--patterns .gates/protected-paths.txt] [--approved]

Exit codes: 0 nothing protected touched (or --approved, or auto-approved), 3 protected paths touched, 2 usage error.
CI passes --approved only when a designated human reviewer/label has signed off.
"""
import argparse
import fnmatch
import re
import subprocess
import sys

# Row shapes the ledger parser can see (common.py AUDITED_STATUSES).
AUDITED_STATUSES = {"COMPLETED", "SOUND"}
AUTO_ADDITIVE = "auto=additive-ledger-rows"
CELL_RE = re.compile(r"`([^`]+)`")


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)


def changed_files(base, head):
    out = git("diff", "--name-only", "--no-renames", f"{base}...{head}")
    if out.returncode != 0:
        print(out.stderr, file=sys.stderr)
        sys.exit(2)
    return [line for line in out.stdout.splitlines() if line]


def load_patterns(path):
    """[(pattern, {directives})], '#' comments and blank lines skipped."""
    patterns = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            fields = line.split()
            patterns.append((fields[0], set(fields[1:])))
    return patterns


def hash_at_head(path):
    """9-char blob hash of ``path`` at HEAD, or None when absent."""
    out = git("rev-parse", f"HEAD:{path}")
    if out.returncode != 0 or not out.stdout.strip():
        return None
    return out.stdout.strip()[:9]


def added_lines(base, head, path):
    """Added lines of ``path``, or None when the diff is not purely additive."""
    out = git("diff", "--unified=0", "--no-renames", f"{base}...{head}", "--", path)
    if out.returncode != 0:
        return None
    added = []
    for line in out.stdout.splitlines():
        if line.startswith("+++") or line.startswith("---"):
            continue
        if line.startswith("+"):
            added.append(line[1:])
        elif line.startswith("-"):
            return None
    return added


def audited_row(line):
    """(target, recorded_hash) when ``line`` is a complete audit row, else None."""
    if not line.strip().startswith("|"):
        return None
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) < 8:
        return None
    targets = CELL_RE.findall(cells[2])
    hashes = CELL_RE.findall(cells[3])
    status = cells[4].strip().strip("*`").upper()
    if len(targets) != 1 or len(hashes) != 1 or status not in AUDITED_STATUSES:
        return None
    return targets[0], hashes[0]


def additive_catalog_approved(base, head, files):
    """True when ``files`` are additive-only audit rows recorded at HEAD.

    ``files`` are the protected files the diff touches; the caller guarantees
    every one carries the auto directive. The whole diff must consist of those
    files alone - the auto lane never covers a bundle.
    """
    everything = set(changed_files(base, head))
    if everything != set(files):
        print(f"auto lane refused: the diff touches files besides the catalog: "
              f"{sorted(everything - set(files))}")
        return False
    approved_any = False
    for path in files:
        rows = added_lines(base, head, path)
        if rows is None:
            print(f"auto lane refused: {path} is not purely additive")
            return False
        if not rows:
            print(f"auto lane refused: {path} changed without adding a row")
            return False
        for line in rows:
            parsed = audited_row(line)
            if parsed is None:
                print(f"auto lane refused: {path} adds a line that is not a "
                      f"complete single-target audit row")
                return False
            target, recorded = parsed
            source = recorded.split(":", 1)[0].strip()
            current = hash_at_head(target)
            if not source or len(source) > 40:
                print(f"auto lane refused: {path} records no usable hash for {target}")
                return False
            if current is None:
                print(f"auto lane refused: {path} names a target absent at HEAD: {target}")
                return False
            if not current.startswith(source):
                print(f"auto lane refused: {path} records {source} for {target} "
                      f"but HEAD is {current}")
                return False
            approved_any = True
    return approved_any


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--head", default="HEAD")
    ap.add_argument("--patterns", default=".gates/protected-paths.txt")
    ap.add_argument("--approved", action="store_true")
    args = ap.parse_args()

    try:
        patterns = load_patterns(args.patterns)
    except OSError as exc:
        print(f"error: cannot read patterns: {exc}", file=sys.stderr)
        return 2

    hits = sorted(
        {(f, p, tuple(sorted(d)))
         for f in changed_files(args.base, args.head)
         for p, d in patterns
         if fnmatch.fnmatch(f, p)}
    )
    if not hits:
        print("no protected paths touched")
        return 0
    print("Protected paths touched:")
    for f, p, _ in hits:
        print(f"  {f}   (matches {p})")

    # Automatic lane: catalog rows produced by the ledger tool. The patterns
    # file (read from the trusted base, never the PR tree) decides which
    # protected entries may use it.
    files = sorted({f for f, _, _ in hits})
    if hits and all(AUTO_ADDITIVE in set(d) for _, _, d in hits):
        if additive_catalog_approved(args.base, args.head, files):
            print("auto-approved: additive audit-catalog rows recorded at HEAD "
                  f"({AUTO_ADDITIVE})")
            return 0

    if args.approved:
        print("approved by a human reviewer: allowing")
        return 0
    print("\nThis change edits the referee (gates/specs/baselines/CI). It needs human approval "
          "and must be a separate 'gate-change' PR, not bundled with product code.")
    return 3


if __name__ == "__main__":
    sys.exit(main())
