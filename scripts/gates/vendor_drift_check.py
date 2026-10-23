#!/usr/bin/env python3
"""Fail when the vendored fleet tools drift from their pinned upstream tree.

`scripts/autonomous/` is a copy of `cassandre60/skills`:
`skills/autonomous-improvement/scripts/autonomous`. Copies drift silently —
this repo ran a fleet several releases behind, and a local fix was about to be
written into the copy instead of upstream. `.gates/vendor-autonomous.json`
pins the upstream directory's git tree SHA and each file's git blob SHA.

Usage:
  vendor_drift_check.py                              # offline: working tree vs manifest
  vendor_drift_check.py --remote                     # also: has upstream main moved?
  vendor_drift_check.py --write --tree-sha <sha>     # after copying an upstream tree

Exit codes: 0 in sync, 1 drift or upstream moved, 2 usage/config/tooling error.

`local_files` in the manifest (this repo's `config.example.json`, and the
gitignored `config.json`) are never copied, hashed, or reported. A local change
to a synced file belongs upstream; if it must stay here, list the file as local
in the same gate-change PR that introduces it, with a reason.
"""
import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path


class ToolError(Exception):
    pass


def git_blob_sha(path):
    data = path.read_bytes()
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def load_manifest(path):
    try:
        with open(path, encoding="utf-8") as fh:
            manifest = json.load(fh)
    except OSError as exc:
        raise ToolError(f"cannot read {path}: {exc}")
    except json.JSONDecodeError as exc:
        raise ToolError(f"{path} is not valid JSON: {exc}")
    for key in ("source", "upstream_path", "tree_sha", "local_path", "local_files", "files"):
        if key not in manifest:
            raise ToolError(f"{path} is missing '{key}'")
    overlap = set(manifest["files"]) & set(manifest["local_files"])
    if overlap:
        raise ToolError(f"{path} lists local files in 'files': {', '.join(sorted(overlap))}")
    return manifest


def write_manifest(path, manifest):
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2, sort_keys=True)
        fh.write("\n")


def local_files(manifest):
    root = Path(manifest["local_path"])
    skip = set(manifest["local_files"])
    found = {}
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        if rel in skip or "__pycache__" in path.parts or path.suffix == ".pyc":
            continue
        found[rel] = path
    return found


def check(manifest):
    errors = []
    expected = manifest["files"]
    found = local_files(manifest)
    for rel, path in found.items():
        if rel not in expected:
            errors.append(f"{manifest['local_path']}/{rel}: not in the manifest")
        elif git_blob_sha(path) != expected[rel]:
            errors.append(f"{manifest['local_path']}/{rel}: differs from upstream")
    for rel in expected:
        if rel not in found:
            errors.append(f"{manifest['local_path']}/{rel}: missing on disk")
    return errors


def gh_api(endpoint):
    proc = subprocess.run(["gh", "api", endpoint], capture_output=True, text=True)
    if proc.returncode != 0:
        detail = proc.stderr.strip() or proc.stdout.strip()
        raise ToolError(f"gh api {endpoint} failed: {detail}")
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise ToolError(f"gh api {endpoint} returned non-JSON: {exc}")


def upstream_entries(manifest, tree_sha):
    tree = gh_api(f"repos/{manifest['source']}/git/trees/{tree_sha}?recursive=1")
    if tree.get("truncated"):
        raise ToolError(f"{manifest['source']} tree {tree_sha} is truncated; cannot verify")
    entries = {}
    for item in tree.get("tree", []):
        if item.get("type") == "blob":
            entries[item["path"]] = item["sha"]
    return entries


def upstream_tree_sha(manifest):
    repo = gh_api(f"repos/{manifest['source']}")
    branch = repo.get("default_branch") or "main"
    tree = gh_api(f"repos/{manifest['source']}/git/trees/{branch}?recursive=1")
    for item in tree.get("tree", []):
        if item.get("path") == manifest["upstream_path"] and item.get("type") == "tree":
            return item["sha"], branch
    raise ToolError(
        f"{manifest['upstream_path']} not found in {manifest['source']}@{branch}"
    )


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", default=".gates/vendor-autonomous.json")
    ap.add_argument("--remote", action="store_true", help="also compare with upstream main")
    ap.add_argument("--write", action="store_true", help="record a copied upstream tree")
    ap.add_argument("--tree-sha", help="upstream directory tree SHA to record (with --write)")
    args = ap.parse_args(argv)

    if args.write and not args.tree_sha:
        print("error: --write needs --tree-sha (the upstream directory tree copied)", file=sys.stderr)
        return 2

    try:
        manifest = load_manifest(args.manifest)

        if args.write:
            upstream = upstream_entries(manifest, args.tree_sha)
            upstream = {k: v for k, v in upstream.items() if k not in manifest["local_files"]}
            local = local_files(manifest)
            errors = []
            for rel, path in local.items():
                if rel not in upstream:
                    errors.append(f"{manifest['local_path']}/{rel}: not in upstream {args.tree_sha}")
                elif git_blob_sha(path) != upstream[rel]:
                    errors.append(f"{manifest['local_path']}/{rel}: differs from upstream {args.tree_sha}")
            for rel in upstream:
                if rel not in local:
                    errors.append(f"{manifest['local_path']}/{rel}: missing locally")
            if errors:
                print("refusing to write the manifest; the local tree is not the upstream tree:", file=sys.stderr)
                for err in errors:
                    print(f"  {err}", file=sys.stderr)
                return 1
            manifest["tree_sha"] = args.tree_sha
            manifest["files"] = dict(sorted(upstream.items()))
            write_manifest(args.manifest, manifest)
            print(f"recorded {len(upstream)} files from {manifest['source']}@{args.tree_sha}")
            return 0

        errors = check(manifest)
        if errors:
            print("vendored skill drift:", file=sys.stderr)
            for err in errors:
                print(f"  {err}", file=sys.stderr)
            print(
                "\nsync the folder from the upstream tree, then run:\n"
                f"  python3 {sys.argv[0]} --write --tree-sha <upstream tree>",
                file=sys.stderr,
            )
            return 1
        local = ", ".join(manifest["local_files"]) or "none"
        print(
            f"ok: {len(manifest['files'])} vendored files match "
            f"{manifest['source']}@{manifest['tree_sha'][:12]} (local: {local})"
        )

        if args.remote:
            pinned = manifest["tree_sha"]
            current, branch = upstream_tree_sha(manifest)
            if current != pinned:
                print(
                    f"upstream {manifest['source']}@{branch} moved: "
                    f"pinned {pinned[:12]}, upstream {current[:12]}",
                    file=sys.stderr,
                )
                return 1
            print(f"ok: upstream {manifest['source']}@{branch} is still {pinned[:12]}")
        return 0
    except ToolError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
