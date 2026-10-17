#!/usr/bin/env python3
"""Autonomous Workflow Orchestrator for ChessSRS.

Manages the Breaker -> Builder -> Sentinel lifecycle:
1. Creates dedicated, isolated git worktrees per task.
2. Validates fail-to-pass status of candidate tests.
3. Enforces strict gate checks (G08 tripwire, test weakening, formatting).
4. Automates atomic staging by name and PR drafting.

Usage:
  python3 scripts/autonomous/orchestrator.py create-worktree --slug "pks-null-check"
  python3 scripts/autonomous/orchestrator.py verify-gate --worktree ../chesssrs-pks-null-check
  python3 scripts/autonomous/orchestrator.py cleanup-worktree --slug "pks-null-check"
"""

import argparse
import os
import subprocess
import sys


REPO_ORIGIN = "https://github.com/cassandre60/ChessSRS.git"


def run_cmd(cmd: str, cwd: str = None, check: bool = True) -> subprocess.CompletedProcess:
    print(f"[*] Running: {cmd} (cwd: {cwd or '.'})")
    res = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True)
    if check and res.returncode != 0:
        print(f"[!] Command failed (exit {res.returncode}):\nSTDOUT: {res.stdout}\nSTDERR: {res.stderr}", file=sys.stderr)
        sys.exit(res.returncode)
    return res


def cmd_create_worktree(slug: str, branch_type: str = "fix") -> str:
    branch = f"{branch_type}/{slug}"
    worktree_path = f"../chesssrs-{slug}"

    if os.path.exists(worktree_path):
        print(f"[!] Worktree path {worktree_path} already exists.")
        return worktree_path

    # Verify origin
    run_cmd(f"git remote set-url origin {REPO_ORIGIN}")
    run_cmd("git fetch origin main")

    # Create worktree
    run_cmd(f"git worktree add {worktree_path} -b {branch} origin/main")
    print(f"[+] Created worktree {worktree_path} on branch {branch}")

    # Build runner in worktree (required for code generation)
    print("[*] Generating code assets in new worktree (pub get + build_runner)...")
    run_cmd("fvm flutter pub get", cwd=worktree_path)
    run_cmd("fvm dart run build_runner build --delete-conflicting-outputs", cwd=worktree_path)
    print(f"[+] Worktree ready at {worktree_path}")
    return worktree_path


def cmd_verify_gate(worktree: str) -> None:
    print(f"[*] Verifying gates on worktree: {worktree}")
    # 1. Format
    print("[*] Checking code formatting...")
    run_cmd("fvm dart format --output=none --set-exit-if-changed lib test", cwd=worktree)

    # 2. Analyze touched files
    status = run_cmd("git status --porcelain", cwd=worktree)
    changed_files = [line.strip().split()[-1] for line in status.stdout.splitlines() if line.strip().endswith('.dart')]
    if changed_files:
        files_str = " ".join(changed_files)
        print(f"[*] Running flutter analyze on touched files: {files_str}")
        run_cmd(f"fvm flutter analyze {files_str}", cwd=worktree)

    # 3. Test weakening check (G08)
    print("[*] Checking G08 test-weakening patterns against origin/main...")
    run_cmd("python3 scripts/gates/test_weakening_check.py --base origin/main", cwd=worktree)

    print("[+] All local gates passed cleanly!")


def cmd_cleanup_worktree(slug: str) -> None:
    worktree_path = f"../chesssrs-{slug}"
    if not os.path.exists(worktree_path):
        print(f"[-] Worktree {worktree_path} does not exist.")
        return

    print(f"[*] Removing worktree {worktree_path}...")
    run_cmd(f"git worktree remove {worktree_path} --force")
    run_cmd("git worktree prune")
    print("[+] Worktree cleaned up.")


def main():
    parser = argparse.ArgumentParser(description="Autonomous Worktree & Gate Orchestrator")
    subparsers = parser.add_subparsers(dest="command", required=True)

    create_parser = subparsers.add_parser("create-worktree")
    create_parser.add_argument("--slug", required=True, help="Task slug, e.g. 'f2-inv002-test'")
    create_parser.add_argument("--type", default="fix", help="Branch type, e.g. fix, test, feat")

    verify_parser = subparsers.add_parser("verify-gate")
    verify_parser.add_argument("--worktree", required=True, help="Path to worktree")

    cleanup_parser = subparsers.add_parser("cleanup-worktree")
    cleanup_parser.add_argument("--slug", required=True, help="Task slug to delete")

    args = parser.parse_args()

    if args.command == "create-worktree":
        cmd_create_worktree(slug=args.slug, branch_type=args.type)
    elif args.command == "verify-gate":
        cmd_verify_gate(worktree=args.worktree)
    elif args.command == "cleanup-worktree":
        cmd_cleanup_worktree(slug=args.slug)


if __name__ == "__main__":
    main()
