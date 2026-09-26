# Agent Operating Guidelines & Authority Hierarchy

## 0. Foundation context (read first)

This application is a **fork of Lichess Mobile** (GPL-3.0) rebuilt as a
**local-first chess repertoire + spaced-repetition trainer**. The previous
standalone implementation is archived at git tag `legacy/pre-reset` — it is
reference material only. Never resurrect old `lib/` code because class names
look familiar; the domain *contracts* are specified in the Markdown documents
and must be reimplemented cleanly inside the Lichess Mobile architecture.

Before doing anything in the codebase, read:
1. `ARCHITECTURE.md` (layer boundaries, licensing constraints)
2. `CUT_PROPOSALS.md` (what Lichess functionality is removed/kept, and status)
3. `docs/INTEGRATION_MAP.md` (how Listudy/chessrs concepts are integrated)
4. `CLAUDE.md` in the repo root — the Lichess Mobile contributor guide
   (Riverpod 3.x patterns, Freezed, code generation, formatting, testing
   patterns). It remains authoritative for the foundation's conventions.

## 1. The Authority Hierarchy

```text
PRODUCT.md
    ↓ (product vision, user journeys, functional & UX requirements)
MVP.md
    ↓ (current active scope, included/excluded capabilities)
ARCHITECTURE.md
    ↓ (Lichess foundation, layer boundaries, licensing)
QUALITY.md
    ↓ (non-negotiable engineering, domain, performance invariants)
TEST_STRATEGY.md
    ↓ (how invariants are mechanically proven)
IMPLEMENTATION_PLAN.md
    ↓ (phases, tasks, execution status)
AGENTS.md  ← you are here
```

**Rule**: Code implements specifications. Code is not the specification. If
requirements or architectural boundaries change, update the authoritative
specification documents accordingly.

## 2. Development phases (beta-first)

The strategy is: **foundation → minimal vertical slice → beta → feedback →
refinement → additional modules**. See `IMPLEMENTATION_PLAN.md` for the live
phase status. The owner is the beta tester. Do not gold-plate before the core
review loop is in the owner's hands.

Do NOT start Listudy/chessrs integration work until the foundation is stable
and the vertical slice exists (unless the task explicitly says otherwise).

## 3. The Development Loop

Every engineering task must follow:

```text
1. SELECT READY TASK from IMPLEMENTATION_PLAN.md (dependencies complete).
2. READ THE SPEC: PRODUCT/MVP/ARCHITECTURE/QUALITY sections that apply.
3. DEFINE A SMALL CONTRACT: testable, incremental brick.
4. WRITE TESTS with the contract (dart test, widget test, or integration
   test as appropriate).
5. IMPLEMENT minimally, following Lichess Mobile conventions (CLAUDE.md).
6. TARGETED VERIFICATION: run the specific test file, appending `--no-pub`
   when dependencies are already resolved (package config newer than the
   pubspec files) to skip the redundant per-run resolution.
7. STATIC CHECK: run the repo's local gate on the files you touched
   (e.g. `./gate.sh <files>` where a gate script exists, else
   `fvm flutter analyze` on those files).
   The full suite is CI's job — see the note on ./verify below. Do not run
   `./verify` as part of the inner loop.
8. RUNTIME VALIDATION (see §4) for anything user-visible.
9. FIX ROOT CAUSES; add permanent regression tests.
10. UPDATE IMPLEMENTATION_PLAN.md / spec docs if boundaries changed.
11. ATOMIC COMMIT matching repository conventions.
```

### Isolation: one worktree per task, `main` only by merged PR

More than one agent works in this repository at a time. Each task gets its own
git worktree and its own branch, so no two agents share a working tree. `main`
is updated only by merging a PR that CI has passed — never pushed to directly.

```bash
# once per task, from anywhere
git worktree add ../chesssrs-<slug> -b <type>/<area>-<slug> origin/main
cd ../chesssrs-<slug>

# required before anything will compile: generated files are gitignored, so they
# are per-worktree. Without this every test fails with "No such file or directory"
# on a *.freezed.dart or *.g.dart import. ~85s.
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs

# ... work, stage BY NAME, commit, push
git push -u origin <branch>
gh pr create -R mansourvery-hub/chess-repertoire-srs

# after the PR is green and merged
git worktree remove ../chesssrs-<slug> && git worktree prune
```

Branch names are `<type>/<area>-<slug>` — `fix/review-redirects`,
`feat/design-tokens`. Not `agent1/…`: the branch should describe the change, so
it reads the same whoever picks it up.

**A docs-only PR gets no CI run at all, and that is deliberate.** The workflow's
`paths` filter lists what the job actually reads — `lib/`, `test/`, the build and
lint configuration, `assets/`, `scripts/` — and Markdown is not among them,
because no step in the job reads it. So for a change touching only `.md` files,
"CI is green" means *no checks were reported*, not *checks passed*. Say so in the
PR rather than leaving a reviewer to wonder whether it ran. If a docs change ever
does need a check, add a small dedicated workflow triggered on `**.md`; do not
widen the test job's filter just to make a doc edit look verified.

Four rules, each of which exists because breaking it has cost real work:

- **Never run a git command that writes outside your own worktree.** No
  `git -C <other-path> reset`, `checkout --`, `clean`, or `stash`. A `git reset
  --hard` or `git checkout -- .` in a *shared* tree silently destroys every
  uncommitted change another agent has made, and there is no undo for it:
  unstaged content is never written to the object store, so `git fsck` cannot
  recover it. This has happened here once already.
- **Never `git add -A`.** Stage by name. It is the same failure by another route,
  and it survives into a commit.
- **Never delete a worktree you did not create.** `git worktree list` first.
- **Check `git status` before and after anything that touches the tree**, so you
  can tell what you changed from what someone else changed.

Isolation makes conflicts *visible* — two agents editing one file become a merge
conflict instead of a silent overwrite. It does not make them *agree*. When two
tasks touch the same subsystem, say so before starting; the worktree will not
resolve a disagreement about what the code should do.

**Recovery is faster than prevention, but it is not guaranteed.** If another
agent's uncommitted work is at risk, it exists only in their working tree.
Commit early and often on your own branch, and take a filesystem snapshot if
you have one.


### Lichess Mobile conventions that always apply

- Riverpod 3.x (`.value`, not `valueOrNull`; no `ProviderListenable` type
  annotations). Prefer HTTP-layer mocking over provider overrides in tests.
- Freezed + fast_immutable_collections for data classes; generated files are
  never committed; run `dart run build_runner build` after model changes.
- Analyze every edited file (including tests) through the repo's local gate
  when one exists (`./gate.sh <files>`), else `fvm flutter analyze` — zero
  warnings.
- `dart format` every edited file (page width 100).
- Package imports, single quotes, strict-casts/inference/raw-types.
- Translations: hardcoded English first; l10n pipeline only after stability.

### Visual work

For anything touching layout, colour, typography, iconography, motion, or
component choice, follow `design/docs/` (see `design/README.md`), not Lichess
Mobile's visual conventions in the inherited `CLAUDE.md`. Lichess Mobile
conventions still apply to non-visual engineering practices (testing,
architecture, commit hygiene) inherited via `CLAUDE.md`.

Screenshot evidence is required for visual PRs (this was already the rule; it
now also applies against the design package): capture the affected screens at
phone, tablet and desktop widths, light and dark, and compare them against
`design/reference/index.html` shown at the same sizes/themes.

## 4. Runtime validation is mandatory

Past sessions produced green `./verify` runs while the real app had runtime
errors or looked nothing like the intended UI. Therefore, for every
user-visible milestone:

1. The suite is green — from CI, or `./verify` when working offline.
2. **Launch the real application** (Linux desktop or attached device) and
   manually exercise the affected feature.
3. Visually inspect the UI. For UI work, screenshot/runtime inspection is
   required — "tests pass" is not evidence of "visual pass".
4. Only then declare the milestone complete and record it in
   `IMPLEMENTATION_PLAN.md`.

Commands (FVM-pinned toolchain):

```bash
fvm flutter pub get
dart run build_runner build      # after model/codegen changes
fvm flutter analyze
fvm flutter test
fvm flutter run -d linux          # runtime validation
```

`./verify` runs `flutter analyze` followed by `flutter test` over the whole
suite — around 1400 tests, with no path filter. That saturates the machine
and takes minutes, so it is a **pre-push and milestone gate, not an
inner-loop step.**

- **Per change:** the local gate on the files you touched (e.g.
  `./gate.sh <files>` plus the one test file covering the change), or
  `fvm flutter analyze` on those files where no gate script exists.
  That is the loop. The fastest per-edit signal is the IDE's Dart analysis
  server (warm diagnostics as you type); gate and test runs confirm, they
  don't discover.
- **Per push / before declaring a milestone:** `./verify` once, or let
  GitHub Actions do it — CI runs `flutter test` on every push and is the
  authority on whether the suite is green.

Say plainly in the commit message when a change was verified only by
targeted tests, so nobody mistakes it for a full-suite result.

## 5. Quality gates and invariants

- `QUALITY.md` invariants are binding: pure domain layer, single chess
  representation (dartchess), local-first critical path, variation
  preservation, position identity, incremental persistence, deterministic
  clocks.
- `TEST_STRATEGY.md` defines the enforcement matrix; update it when the
  enforcement mechanism changes (not just when tests move).
- Old legacy tests (tag `legacy/pre-reset`) are *contract references*: mine
  them for intended behavior, then translate valuable cases into new tests.
  Never copy old tests that merely encode the old architecture.

## 6. Feature-creep policy

Default answer to new features is **no**. No achievements, gamification,
dashboards, social features, analytics, cloud sync, or accounts unless
explicitly justified by the product specs or later beta feedback (clustered
and reviewed first). When uncertain: prefer deleting unnecessary things.

## 7. Licensing discipline

- We are a GPL-3.0 fork: preserve `LICENSE`/`COPYING.md` and copyright
  notices whenever trimming Lichess code.
- chessrs (GPL): attribution if adapting; prefer reimplementation.
- listudy (AGPL): behavior only, never code.

## 8. Chess-domain references

When solving PGN-tree, repertoire-training, or SRS problems, inspect the
reference repositories first (see `docs/INTEGRATION_MAP.md` for what to take
and what to ignore):

- https://github.com/ZackMurry/chessrs (SRS scheduling, review queues)
- https://github.com/ArneVogel/listudy (study trees, training variations)

Do not invent a third architecture when proven behavior exists. Also check
Lichess Mobile's own `model/study/` and `model/common/node.dart` — the
foundation already contains study-tree and game-tree prior art.

## 9. Cut discipline (Phase 1 and beyond)

- Follow `CUT_PROPOSALS.md`; do not silently make controversial cuts.
- One subsystem per commit; after each cut: targeted tests + launch + smoke
  run. Run the full gate once at the end of a batch, not per cut.
- Trace dependencies before deleting: a removed feature may leave a reusable
  primitive (filter widget, avatar, sheet) that other survivors need.
- Keep GPL notices of any removed-origin code that still shares files.

## Lessons Learned

- [2026-09-25, Space Bunny Free] The full suite is a pre-push gate, not a
  per-commit one; this file used to mandate the opposite, and an agent following
  it saturated the machine on every change. Do not restore per-commit
  `./verify` without measuring it. Verified by: the owner reporting 100% CPU
  and full-speed fans after repeated full-suite runs.
- [2026-09-26, Space Bunny Free] A shared working tree is not survivable with more
  than one agent: `git reset --hard` run to sync with a squash-merge destroyed
  17 files of another agent's uncommitted work, ~10 of it recoverable from no ref
  at all. Unstaged content is never written to the object store, so `git fsck`
  cannot bring it back — recovery depends on editor history or a filesystem
  snapshot. Hence the worktree-per-task rule in §3. Verified by: `git status`
  going from 23 dirty files to 7, and by `git diff --quiet` against every branch
  showing the lost files identical to `main`.
- [2026-09-26, Space Bunny Free] A fresh worktree cannot run a single test until
  `dart run build_runner build` has run in it — `*.freezed.dart` and `*.g.dart`
  are gitignored, so codegen output is per-worktree, not shared. The symptom is a
  wall of `No such file or directory` on generated imports that looks like a
  broken checkout. Costs ~85s per new worktree. Verified by: `flutter test`
  failing in a new worktree, then passing after build_runner.
- [2026-09-26, Space Bunny Free] Audit's "High confidence" ratings do not
  predict whether a finding is a live defect in this fork. Of the findings
  checked line-by-line against upstream, five collapsed: M23 was 1 of 3 claims
  in scope, M4 was already fixed, H1's evidence was stale, M18 was not a defect
  (`ref.onDispose` fires on rebuild as well as on disposal, which is what clears
  the accumulator), and M17 was inherited unchanged *and* unreachable because
  nothing writes the table it reads. What correlated with a real, in-scope defect
  was file-level evidence pointing at fork-introduced code. Verified by: CI logs
  and `git diff upstream/main` on each claim before acting.

- [2026-09-26, Space Bunny Free] `makeTestProviderScope` stubs
  `preloadedDataProvider`, which is the only code that reads the stored token and
  fires `/api/token/test` on startup. So no app-level test can ever observe the
  token check: the request cannot be issued by anything. A test asserting it was
  skipped for days and blamed on a CI/machine difference; it failed identically
  locally. Before debugging a missing startup request, check whether the harness
  replaced the provider that makes it. Verified by: counting HTTP client
  constructions in the test — the app built one, for FCM, and none for the token
  check. Full account in `docs/audit-disposition.md`.
