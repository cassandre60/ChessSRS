# Upstream Tracker Guide

This document describes the automated upstream tracking system for maintaining alignment with `lichess-org/mobile`.

---

## 1. Architecture

```text
upstream/main (lichess-org/mobile)
    │
    ▼ [scripts/upstream_tracker.py sync]
    ├── Touches cut paths? ─────────────► Auto-skip (SKIPPED_CUT)
    ├── Touches deleted files? ──────────► Auto-skip (SKIPPED_NOT_IN_FORK)
    ├── Chores/translations? ────────────► Auto-skip (SKIPPED_CHORE)
    └── Touches surviving files?
            │
            ▼
    [docs/upstream-ledger.json] (High-water mark & commit status ledger)
            │
            ▼
    [.github/workflows/upstream-sync.yml] (Weekly cron / workflow_dispatch)
            │
            ▼
    [GitHub Issue #... ([Upstream Tracker])] (Notifies with candidate PRs & files)
```

---

## 2. Fast CLI Usage

### Check tracker status
```bash
python3 scripts/upstream_tracker.py status
```

### Sync new upstream commits
Fetches new upstream commits and evaluates them against ChessSRS file boundaries:
```bash
python3 scripts/upstream_tracker.py sync
```

### View active candidates
View only the upstream changes that touch surviving files in ChessSRS:
```bash
python3 scripts/upstream_tracker.py candidates
python3 scripts/upstream_tracker.py candidates --format markdown
```

### Mark candidate status
When an upstream change is ported, skipped, or backlogged:
```bash
# Mark as applied when porting:
python3 scripts/upstream_tracker.py mark <sha_or_pr> APPLIED --fork-pr <your-pr> --notes "Ported in PR #..."

# Or mark as skipped if not needed:
python3 scripts/upstream_tracker.py mark <sha_or_pr> SKIPPED_CUT --notes "Not relevant to ChessSRS"
```

---

## 3. Automation Workflow

The GitHub Action `.github/workflows/upstream-sync.yml`:
1. Runs automatically every Monday at 06:00 UTC (and on `workflow_dispatch`).
2. Scans for upstream commits since the last recorded high-water mark.
3. Automatically classifies cut features, deleted files, and chore commits.
4. If actionable candidates exist, creates or updates a GitHub Issue with the label `upstream-sync`.
5. Updates `docs/upstream-ledger.json` via a pull request to `main`.
