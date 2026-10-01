#!/usr/bin/env python3
"""Produce metrics.json for the monotone ratchets (see .gates/ratchet-baseline.json).

Every metric is deterministic and needs no toolchain: plain text scans of the
working tree. CI and `scripts/gates.sh` both call this, so each metric has
exactly one definition.

Usage: collect_metrics.py [--root .] [--out metrics.json]
Prints the metrics table; writes metrics.json only with --out.
"""
import argparse
import os
import re
import sys

SKIP_DIRS = {".git", ".dart_tool", "build", ".fvm", "node_modules", "__pycache__"}
# Generated files are gitignored but present after codegen; they carry
# machine-written ignores. The analyzer config excludes them too, so the
# metric follows the same definition and stays stable either way.
GENERATED_SUFFIXES = (".freezed.dart", ".g.dart", ".mocks.dart")


def dart_files(root, *tops):
    out = []
    for top in tops:
        base = os.path.join(root, top)
        if not os.path.isdir(base):
            continue
        for dp, dns, fns in os.walk(base):
            dns[:] = [d for d in dns if d not in SKIP_DIRS]
            for fn in fns:
                if fn.endswith(".dart") and not fn.endswith(GENERATED_SUFFIXES):
                    out.append(os.path.join(dp, fn))
    return sorted(out)


def read_lines(path):
    with open(path, encoding="utf-8", errors="ignore") as fh:
        return fh.readlines()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    root = args.root
    lib_files = [p for p in dart_files(root, "lib") if "/l10n/" not in p.replace(os.sep, "/")]
    test_files = dart_files(root, "test")

    # Direct dependencies: top-level keys of the dependencies: block in pubspec.yaml.
    with open(os.path.join(root, "pubspec.yaml"), encoding="utf-8") as fh:
        pubspec = fh.read()
    m = re.search(r"^dependencies:\n(.*?)^dev_dependencies:", pubspec, re.S | re.M)
    if not m:
        print("error: cannot find dependencies block in pubspec.yaml", file=sys.stderr)
        return 2
    direct_dependencies = sum(1 for line in m.group(1).splitlines() if re.match(r"^  [A-Za-z0-9_]+:", line))

    # Analyzer suppressions outside generated l10n (the analyzer config excludes it too).
    suppressions = 0
    for path in lib_files + test_files:
        for line in read_lines(path):
            if "ignore_for_file" in line:
                suppressions += 1
            elif re.match(r"^\s*//\s*ignore:", line):
                suppressions += 1

    # Test skips: `skip:` named arguments in test files (Dart's skip marker).
    # Deliberately NOT matching `.skip(`: that is the Iterable API and the
    # ReviewSession.skip() product call, both of which appear in honest tests.
    skips = 0
    for path in test_files:
        for line in read_lines(path):
            if re.search(r"[(,]\s*skip\s*:", line):
                skips += 1

    # Test declarations: test('...') and testWidgets('...') occurrences.
    test_decl = re.compile(r"(^|[^_a-zA-Z])(test|testWidgets)\(")
    test_declarations = 0
    for path in test_files:
        for line in read_lines(path):
            test_declarations += len(test_decl.findall(line))

    # Domain size: total lines of the pure core (bloat tripwire, wide tolerance).
    domain_loc = 0
    for path in dart_files(root, "lib/src/domain"):
        domain_loc += len(read_lines(path))

    metrics = {
        "direct_dependencies": direct_dependencies,
        "analyzer_suppressions": suppressions,
        "test_skips": skips,
        "test_declarations": test_declarations,
        "domain_loc": domain_loc,
    }
    for name, value in metrics.items():
        print(f"{name}={value}")
    if args.out:
        import json

        with open(args.out, "w", encoding="utf-8") as fh:
            json.dump(metrics, fh, indent=2, sort_keys=True)
            fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
