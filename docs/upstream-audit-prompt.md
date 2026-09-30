# Upstream Diff Audit — Chess Repertoire SRS vs lichess-org/mobile

Audit this fork against upstream. **Report only: do not merge, rebase, modify
code, push, or run builds/tests.** All verification happens on CI later; this
task only reads git history and files.

## Step 0: Load product authority (before looking at any diff)

Read, in order: `PRODUCT.md`, `MVP.md`, `CUT_PROPOSALS.md`, `docs/upstream-realign.md`,
`AGENTS.md` (§7 licensing, §3 budget). These decide relevance — not generic
"does it affect functionality":

- A subsystem in `CUT_PROPOSALS.md` as cut/deleted (puzzles, lobby, TV,
  correspondence, social, blog…) is **gone on purpose**. Its absence from the
  fork is `Intended`, never a flag, and no recommendation may propose
  restoring it.
- An upstream change touching only visuals/presentation our design system
  overrides (`lib/src/design/`, tokens, board styling) is `Skip` — we differ
  in presentation deliberately.
- An upstream change touching logic in a subsystem we keep (study, settings,
  analysis, engine, review, persistence) is a `Take` candidate.
- Anything else is `Take-later` with a written reason.

## Step 1: Identify upstream

- Run `git remote -v`. Expect `upstream → https://github.com/lichess-org/mobile.git`.
- **Push-URL trap:** that remote's push URL points at Lichess. Verify it, never
  alter remotes, never push anywhere in this task. If the remote is missing,
  add it temporarily (`--no-tags`) and remove it when done.

## Step 2: Sync (read-only)

- `git fetch upstream` only. No pull, merge, rebase, checkout of upstream code
  into the working tree.

## Step 3: Compare, per subsystem (not as one flat file dump)

Our `main` descends from both histories (grafted fork), so raw
`upstream/main...HEAD` stats are huge and mostly deletions-by-design. Work
subsystem by subsystem: study, settings, analysis, engine, review/persistence,
shared widgets, l10n, platform/splash. Cap file listings (`limit=100`) and
summarize the rest by directory.

Commands per subsystem:

```
git diff --name-status upstream/main...HEAD -- <subsystem path>
git log --oneline HEAD..upstream/main -- <subsystem path>   # upstream ahead
```

## Step 4: Categorize (fork-aware)

| Category | Meaning here |
|----------|--------------|
| Cut-intended | File/subsystem absent per `CUT_PROPOSALS.md`. Not a finding. |
| Presentation-only | Upstream changed visuals we override. `Skip`. |
| Logic-shared | Upstream changed logic in a kept subsystem. `Take` candidate. |
| Fork-diverged | Both sides changed the same shared-logic file. Flag as overlap. |
| License | Upstream notice removed where its code survives. Flag always (GPL §7). |

Risk levels (`Low`/`Medium`/`High`) apply only to `Logic-shared` and
`Fork-diverged` rows. Never emit a recommendation that contradicts Step 0.

## Step 5: Required callouts

1. **Study subsystem verdict** (blocks the Explore-study decision): can upstream's
   study screen + controller run against local (non-server) study data with
   skinning only, or does it fundamentally require lichess IDs/sockets/chat?
   Answer with file/line evidence, no refactoring.
2. **Dependency drift**: compare `pubspec.yaml` deps vs upstream's; flag
   outdated/ahead/removed/added with breaking-change notes from changelogs
   only — do not run audit/build commands locally.
3. **License headers**: list surviving upstream files missing GPL notices.

## Step 6: Report

Write the report to `docs/upstream-audit-<date>.md` and output three tables:

### Your changes vs upstream
| File/subsystem | Category | Change | Notes |

### Upstream changes not in fork (Take candidates only)
| Commit | Type | Summary | Merge effort (Trivial/Moderate/Complex) | Risk |

### Flags (Fork-diverged + License only)
| Type | Severity | Location | Evidence | Next step |

Then: 3-line summary (take count, flag count, the study verdict in one line).
Do NOT recommend merging upstream into a temp branch, rebasing, or any local
verification — those are separate tasks with their own prompts and CI runs.
