#!/usr/bin/env python3
"""Upstream Tracker for ChessSRS.

Tracks, filters, and manages commits and PRs from lichess-org/mobile against
ChessSRS. Deterministically filters out cut subsystems, chores, and deleted files,
recording evaluation status in docs/upstream-ledger.json.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

LEDGER_PATH = Path("docs/upstream-ledger.json")
APPLIED_MD_PATH = Path("docs/upstream-applied.md")
UPSTREAM_REPO = "lichess-org/mobile"
DEFAULT_BASE_SHA = "f7f71d120"  # Audit baseline from 2026-09-30

CUT_PREFIXES = (
    "lib/src/view/puzzle",
    "lib/src/model/puzzle",
    "lib/src/view/tv",
    "lib/src/model/tv",
    "lib/src/view/play",
    "lib/src/model/play",
    "lib/src/model/lobby",
    "lib/src/view/lobby",
    "lib/src/model/challenge",
    "lib/src/view/challenge",
    "lib/src/model/game",
    "lib/src/view/game",
    "lib/src/view/learn",
    "lib/src/model/learn",
    "lib/src/view/coordinate",
    "lib/src/model/coordinate",
    "lib/src/view/broadcast",
    "lib/src/model/broadcast",
    "lib/src/view/tournament",
    "lib/src/model/tournament",
    "lib/src/view/community",
    "lib/src/model/community",
    "lib/src/view/inbox",
    "lib/src/model/inbox",
    "lib/src/view/message",
    "lib/src/model/message",
    "lib/src/view/blog",
    "lib/src/model/blog",
    "lib/src/model/firebase",
    "scripts/firebase",
    "ios/LichessWidgets",
    "test/view/game",
    "test/model/game",
    "test/view/puzzle",
    "test/model/puzzle",
    "test/view/tv",
    "test/model/tv",
    "test/view/learn",
    "test/model/learn",
    "test/view/tournament",
    "test/model/tournament",
    "test/view/broadcast",
    "test/model/broadcast",
    "test/view/challenge",
    "test/model/challenge",
)

CHORE_SUBJECT_PATTERNS = (
    re.compile(r"^Bump version", re.IGNORECASE),
    re.compile(r"^New Crowdin translations", re.IGNORECASE),
    re.compile(r"^New translations", re.IGNORECASE),
    re.compile(r"AGENTS\.md", re.IGNORECASE),
    re.compile(r"^Remove lila-gitpod setup instructions", re.IGNORECASE),
    re.compile(r"^Restore LF line endings", re.IGNORECASE),
)

CHORE_FILE_PATTERNS = (
    re.compile(r"^lib/l10n/.*\.arb$"),
    re.compile(r"^ios/LichessWidgets/Localizable\.xcstrings$"),
    re.compile(r"^\.gitattributes$"),
)

KNOWN_APPLIED_COMMITS: Dict[str, Dict[str, Any]] = {
    "a99dad8a1": {"pr": 3746, "fork_pr": 94, "notes": "Email login in POST body"},
    "214bb0353": {"pr": 3746, "fork_pr": 94, "notes": "Email login in POST body"},
    "25cf0fae5": {"pr": 3733, "fork_pr": 98, "notes": "Board editor illegal FENs"},
    "60309eb8d": {"pr": 3730, "fork_pr": 99, "notes": "App links exact host"},
    "c60a0edd8": {"pr": 3706, "fork_pr": 102, "notes": "Index openings.epd"},
    "498ce10a7": {"pr": 3702, "fork_pr": 103, "notes": "Await openings cleanup"},
    "ed3dbea51": {"pr": 3750, "fork_pr": 120, "notes": "Drop unrequired abiFilters"},
    "1a3a4dda8": {"pr": 3718, "fork_pr": 120, "notes": "Cancel eval stream subscription"},
    "e6be63d22": {"pr": 3670, "fork_pr": 120, "notes": "Linux audio playback pw-play"},
    "cd25cd5f8": {"pr": 3763, "fork_pr": 121, "notes": "Cancel superseded PR runs"},
    "54f7eeedd": {"pr": None, "fork_pr": 122, "notes": "chessground 10.3.0 & dartchess 0.14.0"},
}


def run_git(args: List[str], cwd: Optional[Path] = None) -> str:
    res = subprocess.run(
        ["git"] + args,
        cwd=cwd,
        capture_output=True,
        text=True,
        check=True,
    )
    return res.stdout.strip()


def extract_pr_number(title: str) -> Optional[int]:
    match = re.search(r"\(#(\d+)\)", title)
    if match:
        return int(match.group(1))
    match = re.search(r"\bPR\s*#?(\d+)\b", title, re.IGNORECASE)
    if match:
        return int(match.group(1))
    match = re.search(r"Merge pull request #(\d+)", title, re.IGNORECASE)
    if match:
        return int(match.group(1))
    return None


def categorize_candidate(files: List[str]) -> str:
    if any(f in ("pubspec.yaml", "pubspec.lock") for f in files):
        return "dependency"
    if any(f.startswith("android/") or f.startswith("ios/") or f.startswith("linux/") for f in files):
        return "platform"
    if any("openings" in f or "database" in f for f in files):
        return "database"
    if any(f.startswith("lib/src/model/") for f in files):
        return "core_logic"
    if any(f.startswith("lib/src/widgets/") or f.startswith("lib/src/view/") for f in files):
        return "ui_widget"
    return "general"


def classify_commit(
    sha: str,
    subject: str,
    files: List[str],
    repo_root: Path,
) -> Tuple[str, str, List[str]]:
    """Returns (status, category, surviving_files)."""
    # Check known applied commits
    short_sha = sha[:9]
    pr_num = extract_pr_number(subject)
    for known_sha, meta in KNOWN_APPLIED_COMMITS.items():
        if sha.startswith(known_sha) or (pr_num is not None and meta.get("pr") == pr_num):
            return "APPLIED", "applied", [f for f in files if (repo_root / f).exists()]

    # Chores by commit message
    if any(pat.search(subject) for pat in CHORE_SUBJECT_PATTERNS):
        return "SKIPPED_CHORE", "chore", []

    # Check which files survive in ChessSRS
    surviving_files: List[str] = []
    cut_files: List[str] = []
    not_in_fork_files: List[str] = []
    chore_files: List[str] = []

    for f in files:
        if any(f.startswith(p) for p in CUT_PREFIXES):
            cut_files.append(f)
        elif any(pat.search(f) for pat in CHORE_FILE_PATTERNS):
            chore_files.append(f)
        elif (repo_root / f).exists():
            surviving_files.append(f)
        else:
            not_in_fork_files.append(f)

    if not surviving_files:
        if cut_files:
            return "SKIPPED_CUT", "cut", []
        if chore_files:
            return "SKIPPED_CHORE", "chore", []
        return "SKIPPED_NOT_IN_FORK", "not_in_fork", []

    # If only chore files survived (e.g. translation files in a commit touching only arb files)
    if all(any(pat.search(f) for pat in CHORE_FILE_PATTERNS) for f in surviving_files):
        return "SKIPPED_CHORE", "chore", []

    # We have surviving files that matter!
    category = categorize_candidate(surviving_files)
    return "CANDIDATE", category, surviving_files


def load_ledger(path: Path = LEDGER_PATH) -> Dict[str, Any]:
    if not path.exists():
        return {
            "version": 1,
            "upstream_repo": UPSTREAM_REPO,
            "last_synced_sha": DEFAULT_BASE_SHA,
            "last_synced_date": None,
            "stats": {"total": 0, "candidates": 0, "applied": 0, "skipped": 0},
            "commits": {},
        }
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_ledger(ledger: Dict[str, Any], path: Path = LEDGER_PATH) -> None:
    # Recalculate stats
    commits = ledger.get("commits", {})
    candidates = sum(1 for c in commits.values() if c.get("status") == "CANDIDATE")
    applied = sum(1 for c in commits.values() if c.get("status") == "APPLIED")
    skipped = sum(1 for c in commits.values() if c.get("status", "").startswith("SKIPPED"))

    ledger["stats"] = {
        "total": len(commits),
        "candidates": candidates,
        "applied": applied,
        "skipped": skipped,
    }

    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(ledger, f, indent=2, sort_keys=True)
        f.write("\n")


def cmd_sync(args: argparse.Namespace, repo_root: Path) -> int:
    ledger = load_ledger(LEDGER_PATH)
    base_sha = ledger.get("last_synced_sha") or DEFAULT_BASE_SHA

    # Verify upstream remote exists
    remotes = run_git(["remote"], cwd=repo_root).split()
    if "upstream" not in remotes:
        print("Adding remote 'upstream' pointing to https://github.com/lichess-org/mobile.git")
        run_git(
            ["remote", "add", "upstream", f"https://github.com/{UPSTREAM_REPO}.git"],
            cwd=repo_root,
        )
        run_git(["remote", "set-url", "--push", "upstream", "no_push"], cwd=repo_root)

    if args.fetch:
        print(f"Fetching upstream main (depth: {args.depth})...")
        run_git(["fetch", f"--depth={args.depth}", "upstream", "main", "--no-tags"], cwd=repo_root)

    # Check if base_sha is valid
    try:
        run_git(["rev-parse", "--verify", base_sha], cwd=repo_root)
    except subprocess.CalledProcessError:
        print(f"Warning: base_sha {base_sha} not found in shallow history. Fetching deeper...")
        run_git(["fetch", "--deepen=100", "upstream", "main", "--no-tags"], cwd=repo_root)

    # Get commits between base_sha and upstream/main
    rev_list = run_git(
        ["rev-list", "--reverse", f"{base_sha}..upstream/main"],
        cwd=repo_root,
    )
    shas = [s.strip() for s in rev_list.split() if s.strip()]

    if not shas:
        print(f"Up to date. No new upstream commits found since {base_sha[:9]}.")
        return 0

    print(f"Found {len(shas)} new commits to evaluate since {base_sha[:9]}.")

    commits_dict = ledger.setdefault("commits", {})
    new_candidates = 0
    new_skipped = 0
    new_applied = 0

    for sha in shas:
        short_sha = sha[:9]
        if short_sha in commits_dict or sha in commits_dict:
            continue

        subject = run_git(["log", "-1", "--format=%s", sha], cwd=repo_root)
        author = run_git(["log", "-1", "--format=%an", sha], cwd=repo_root)
        date = run_git(["log", "-1", "--format=%cI", sha], cwd=repo_root)
        files_raw = run_git(["diff-tree", "--no-commit-id", "--name-only", "-r", sha], cwd=repo_root)
        files = [f.strip() for f in files_raw.splitlines() if f.strip()]

        status, category, surviving_files = classify_commit(sha, subject, files, repo_root)
        pr_num = extract_pr_number(subject)

        fork_pr = None
        notes = ""
        if status == "APPLIED":
            new_applied += 1
            # Look up fork PR
            for k, meta in KNOWN_APPLIED_COMMITS.items():
                if sha.startswith(k) or (pr_num is not None and meta.get("pr") == pr_num):
                    fork_pr = meta.get("fork_pr")
                    notes = meta.get("notes", "")
                    break
        elif status == "CANDIDATE":
            new_candidates += 1
        else:
            new_skipped += 1

        commits_dict[short_sha] = {
            "sha": sha,
            "short_sha": short_sha,
            "pr": pr_num,
            "title": subject,
            "author": author,
            "date": date,
            "status": status,
            "category": category,
            "surviving_files": surviving_files,
            "all_files": files,
            "fork_pr": fork_pr,
            "notes": notes,
        }

    latest_sha = shas[-1]
    ledger["last_synced_sha"] = latest_sha
    ledger["last_synced_date"] = datetime.now(timezone.utc).isoformat()
    save_ledger(ledger, LEDGER_PATH)

    print("\n--- Sync Summary ---")
    print(f"Total new commits processed: {len(shas)}")
    print(f"  - Candidates requiring review: {new_candidates}")
    print(f"  - Applied: {new_applied}")
    print(f"  - Skipped (cut/chore/deleted): {new_skipped}")
    print(f"Latest synced commit: {latest_sha[:9]}")
    print(f"Ledger saved to {LEDGER_PATH}")

    if new_candidates > 0:
        print(f"\nRun `python3 scripts/upstream_tracker.py candidates` to view candidates.")
    return 0


def cmd_status(args: argparse.Namespace, repo_root: Path) -> int:
    ledger = load_ledger(LEDGER_PATH)
    stats = ledger.get("stats", {})
    last_sha = ledger.get("last_synced_sha", "unknown")
    last_date = ledger.get("last_synced_date", "never")

    print("=== Upstream Tracker Status ===")
    print(f"Upstream repository : {ledger.get('upstream_repo', UPSTREAM_REPO)}")
    print(f"Last synced commit  : {last_sha[:9]} ({last_date})")
    print(f"Total commits logged: {stats.get('total', 0)}")
    print(f"  - Candidates      : {stats.get('candidates', 0)}")
    print(f"  - Applied         : {stats.get('applied', 0)}")
    print(f"  - Skipped         : {stats.get('skipped', 0)}")

    candidates = [
        c for c in ledger.get("commits", {}).values() if c.get("status") == "CANDIDATE"
    ]
    if candidates:
        print(f"\nActive Candidates ({len(candidates)}):")
        for c in candidates:
            pr_label = f"#{c['pr']}" if c.get("pr") else c["short_sha"]
            print(f"  [{c['short_sha']}] {pr_label:8} ({c.get('category', 'general'):11}) : {c['title']}")
    else:
        print("\nNo pending candidates.")
    return 0


def cmd_candidates(args: argparse.Namespace, repo_root: Path) -> int:
    ledger = load_ledger(LEDGER_PATH)
    candidates = [
        c for c in ledger.get("commits", {}).values() if c.get("status") == "CANDIDATE"
    ]

    if not candidates:
        if args.format == "json":
            print(json.dumps([], indent=2))
        elif args.format == "markdown":
            print("No pending upstream candidates.")
        else:
            print("No pending upstream candidates to review.")
        return 0

    if args.format == "json":
        print(json.dumps(candidates, indent=2))
        return 0

    if args.format == "markdown":
        print(generate_markdown_report(candidates))
        return 0

    # Default text format
    print(f"=== {len(candidates)} Pending Upstream Candidates ===\n")
    for idx, c in enumerate(candidates, 1):
        pr_str = f"PR #{c['pr']}" if c.get("pr") else "No PR"
        pr_url = f"https://github.com/{UPSTREAM_REPO}/pull/{c['pr']}" if c.get("pr") else f"https://github.com/{UPSTREAM_REPO}/commit/{c['sha']}"
        print(f"{idx}. [{c['short_sha']}] {c['title']}")
        print(f"   Category: {c.get('category')}")
        print(f"   Upstream: {pr_url}")
        print("   Shared files:")
        for f in c.get("surviving_files", []):
            print(f"     - {f}")
        print()
    return 0


def generate_markdown_report(candidates: List[Dict[str, Any]]) -> str:
    lines = [
        "## Upstream Intake: Candidates for Review",
        "",
        f"Automated scan found **{len(candidates)}** upstream changes affecting files surviving in ChessSRS.",
        "",
        "| Upstream | Title | Category | Shared Files |",
        "|---|---|---|---|",
    ]

    for c in candidates:
        pr_str = f"[#{c['pr']}](https://github.com/{UPSTREAM_REPO}/pull/{c['pr']})" if c.get("pr") else f"[`{c['short_sha']}`](https://github.com/{UPSTREAM_REPO}/commit/{c['sha']})"
        files_summary = "<br>".join(f"`{f}`" for f in c.get("surviving_files", [])[:3])
        if len(c.get("surviving_files", [])) > 3:
            files_summary += f"<br>*(+{len(c['surviving_files']) - 3} more)*"
        clean_title = c['title'].replace("|", "\\|")
        lines.append(f"| {pr_str} | {clean_title} | `{c.get('category', 'general')}` | {files_summary} |")

    lines.extend([
        "",
        "### How to Port a Candidate",
        "1. Create a task branch / worktree:",
        "   ```bash",
        "   git worktree add ../chesssrs-upstream-<pr> -b feat/upstream-<pr> origin/main",
        "   ```",
        "2. Cherry-pick or adapt the patch:",
        "   ```bash",
        "   git cherry-pick <sha> # or apply patch from github",
        "   ```",
        "3. Run targeted tests and verify:",
        "   ```bash",
        "   fvm flutter analyze <files>",
        "   fvm flutter test <test_file>",
        "   ```",
        "4. Mark candidate in ledger and commit:",
        "   ```bash",
        "   python3 scripts/upstream_tracker.py mark <sha> APPLIED --fork-pr <your-pr>",
        "   ```",
    ])
    return "\n".join(lines)


def cmd_mark(args: argparse.Namespace, repo_root: Path) -> int:
    ledger = load_ledger(LEDGER_PATH)
    commits = ledger.setdefault("commits", {})
    target = args.target

    # Find commit by sha prefix or pr number
    match_key = None
    target_pr = None
    if target.isdigit():
        target_pr = int(target)

    for k, c in commits.items():
        if k.startswith(target) or c.get("sha", "").startswith(target):
            match_key = k
            break
        if target_pr is not None and c.get("pr") == target_pr:
            match_key = k
            break

    if not match_key:
        print(f"Error: Commit or PR '{target}' not found in ledger.")
        return 1

    entry = commits[match_key]
    old_status = entry.get("status")
    entry["status"] = args.status
    if args.fork_pr:
        entry["fork_pr"] = args.fork_pr
    if args.notes:
        entry["notes"] = args.notes

    save_ledger(ledger, LEDGER_PATH)
    print(f"Updated {match_key} ({entry.get('title')}): {old_status} -> {args.status}")

    # If marked as APPLIED, optionally sync to docs/upstream-applied.md
    if args.status == "APPLIED" and APPLIED_MD_PATH.exists() and args.fork_pr:
        append_to_applied_markdown(entry)
    return 0


def append_to_applied_markdown(entry: Dict[str, Any]) -> None:
    content = APPLIED_MD_PATH.read_text(encoding="utf-8")
    sha_str = f"`{entry['short_sha']}`"
    if sha_str in content:
        return  # already in table

    pr_str = f"#{entry['pr']}" if entry.get("pr") else ""
    summary = f"{entry.get('title', '')} {pr_str}".strip()
    fork_pr_str = f"`{entry.get('fork_pr')}`" if entry.get("fork_pr") else "-"
    files_str = ", ".join(f"`{f}`" for f in entry.get("surviving_files", [])[:2])
    notes = entry.get("notes", "")

    new_row = f"| `{entry['short_sha']}` | {summary} | {fork_pr_str} | {files_str} | {notes} |\n"
    content += new_row
    APPLIED_MD_PATH.write_text(content, encoding="utf-8")
    print(f"Appended entry to {APPLIED_MD_PATH}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Upstream tracker for ChessSRS")
    subparsers = parser.add_subparsers(dest="command")

    # sync
    p_sync = subparsers.add_parser("sync", help="Sync and classify new upstream commits")
    p_sync.add_argument("--fetch", action="store_true", default=True, help="Fetch upstream first (default: true)")
    p_sync.add_argument("--no-fetch", action="store_false", dest="fetch", help="Do not fetch upstream")
    p_sync.add_argument("--depth", type=int, default=100, help="Fetch depth (default: 100)")

    # status
    subparsers.add_parser("status", help="Show summary status of the upstream ledger")

    # candidates
    p_cand = subparsers.add_parser("candidates", help="List active candidates")
    p_cand.add_argument(
        "--format",
        choices=["text", "markdown", "json"],
        default="text",
        help="Output format (default: text)",
    )

    # mark
    p_mark = subparsers.add_parser("mark", help="Mark the status of a commit or PR")
    p_mark.add_argument("target", help="SHA prefix or PR number")
    p_mark.add_argument(
        "status",
        choices=["CANDIDATE", "APPLIED", "SKIPPED_CUT", "SKIPPED_VISUAL", "SKIPPED_CHORE", "SKIPPED_NOT_IN_FORK", "BACKLOG"],
        help="New status",
    )
    p_mark.add_argument("--fork-pr", type=int, help="Associated fork PR number")
    p_mark.add_argument("--notes", type=str, default="", help="Optional notes")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        return 0

    repo_root = Path.cwd()
    if args.command == "sync":
        return cmd_sync(args, repo_root)
    elif args.command == "status":
        return cmd_status(args, repo_root)
    elif args.command == "candidates":
        return cmd_candidates(args, repo_root)
    elif args.command == "mark":
        return cmd_mark(args, repo_root)
    return 0


if __name__ == "__main__":
    sys.exit(main())
