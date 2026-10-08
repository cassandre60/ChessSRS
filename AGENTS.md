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
6. TARGETED VERIFICATION: run the specific test file — once, and on a budget
   (see §3.1). The owner's machine heats up under repeated local runs; every
   local run you skip is a run CI does for you on merge.
7. STATIC CHECK: `flutter analyze` on the files you touched.
   The full suite is CI's job — see the note on ./verify below. Do not run
   `./verify` as part of the inner loop.
8. RUNTIME VALIDATION (see §4) for anything user-visible.
9. FIX ROOT CAUSES; add permanent regression tests.
10. UPDATE IMPLEMENTATION_PLAN.md / spec docs if boundaries changed.
11. ATOMIC COMMIT matching repository conventions.
```

### 3.1 Local test budget (the machine is not a build server)

CI runs the full suite on every push. Local runs exist only to answer "does
my change do what I claim" — one answer, minimum heat:

- Iterate with `fvm flutter test <file> --plain-name '<test name>'`: one test,
  not the file. The full file runs exactly once, at the end.
- Never run neighbouring files, whole directories, or `./verify` locally to
  "be safe" — that safety is what the PR's CI run is for. If you have a
  concrete reason to suspect cross-file breakage, state it in the PR instead
  of running it.
- The fail-on-old-code check (stash + rerun) counts as the second run of the
  file: pass run + fail run, then stop. No third run.
- One `flutter analyze` per task, on the files touched, after the last edit —
  not after every edit.
- Never run two heavy commands at once (no test run beside build_runner, no
  parallel worktrees verifying simultaneously). The per-worktree
  `build_runner build` (~85s) is the one unavoidable cost; everything else is
  negotiable.
- `fvm flutter run -d linux` for runtime validation is exempt from the
  budget but stays bounded: launch, exercise, quit. No release builds, ever
  (§4).

### Isolation: one worktree per task, `main` only by merged PR

More than one agent works in this repository at a time. Each task gets its own
git worktree and its own branch, so no two agents share a working tree. `main`
is updated only by merging a PR that CI has passed — never pushed to directly.

**The repository is `cassandre60/ChessSRS`. Nothing else.** A second repository,
`cassandre60/chess-repertoire-srs`, held all 195 PRs until 2026-10-07 and is now
an archived read-only fork. It was created four days *later* than ChessSRS and so
looked newer, which is how every PR kept landing in the wrong place. Nothing has
landed there since. Do not open a PR against it, do not push a branch to it, do
not clone it, and if a remote resolves to `chess-repertoire-srs`, fix it before
doing anything else.

```bash
# once per task, from anywhere
git remote set-url origin https://github.com/cassandre60/ChessSRS.git
git worktree add ../chesssrs-<slug> -b <type>/<area>-<slug> origin/main
cd ../chesssrs-<slug>

# required before anything will compile: generated files are gitignored, so they
# are per-worktree. Without this every test fails with "No such file or directory"
# on a *.freezed.dart or *.g.dart import. ~85s.
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs

# ... work, stage BY NAME, commit, push
git push -u origin <branch>
gh pr create -R cassandre60/ChessSRS

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
- **Never push to, merge, or close a branch or PR you did not create without
  re-reading its live state first.** More than one agent pushes here: `git
  fetch origin <branch>` and compare tips before pushing (a rejected push means
  someone else moved it — integrate, don't force), and re-read the PR's state
  and head-sha immediately before merging or closing it. A reading minutes old
  has closed, merged, or moved under you before. Verified 2026-10-08: one
  rejected push, one close overridden by reopen, one merge raced, all on
  shared branches.

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
- `flutter analyze` on every edited file (including tests) — zero warnings.
- `dart format` every edited file (page width 100, from `analysis_options.yaml` —
  so run `fvm flutter pub get` first: with unresolved includes the formatter
  silently falls back to width 80 and rewrites hundreds of lines).
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

- **Per change:** `flutter analyze` on the files you touched, plus the one
  test file covering the change. That is the loop.
- **Per push / before declaring a milestone:** let GitHub Actions do it. CI
  runs `flutter test` on every push and is the authority on whether the suite
  is green, so a local full-suite run before that push is duplicate work, not
  extra safety. Run `./verify` locally only when CI is unavailable or you
  specifically need the answer before pushing. Wait on a run with
  `gh run watch <id> --exit-status`, not sleep-and-poll loops.

Say plainly in the commit message when a change was verified only by
targeted tests, so nobody mistakes it for a full-suite result.

**Release builds never run on a dev machine.** `flutter build appbundle/apk --release`
(R8 + native engines) OOM-killed a 15GB desktop mid-build, and Gradle's Groovy compiler cannot
run on that machine's Java 27 at all. Release artifacts come only from the `release-proof`
workflow on GitHub runners (dispatch it, or touch its file in a PR). Never attempt a local
release build to "prove" anything — the proof already has a home, and the crash it risks is the
owner's working machine, not a throwaway VM.

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

## 10. Quality gates: rules for any agent or contributor working here

This repository is gated. Your job is to get a change accepted by the gates
honestly, not to make the gates go green. Before editing, read `SPEC.md`
(invariants with stable IDs), `GATES.md` (everything that can reject you),
`GATES_PLAN.md` (what is deliberately not gated), and `.gates/`.

1. Classify your change (bugfix, perf, refactor, feature, test-only,
   dependency, docs, gate-change, spec-change) and gather the evidence that
   class requires — see `.github/PULL_REQUEST_TEMPLATE.md` and `GATES.md`.
   A bugfix starts with a test that fails on the current code.
2. Never edit the referee to get a pass: `SPEC.md`, `GATES.md`,
   `GATES_PLAN.md`, `QUALITY.md`, `TEST_STRATEGY.md`, `CODEOWNERS`, `.gates/`,
   `redteam/`, `scripts/gates*`, CI config, `analysis_options.yaml`,
   `pubspec.yaml`, ratchet baselines, `AGENTS.md`/`CLAUDE.md`, the PR
   template. If you think a gate is wrong, stop and propose a separate
   gate-change PR with evidence — never bundle it with product code.
3. Never weaken a check: no deleted or loosened assertions, no
   skip/ignore/xfail, no new suppressions, no widened tolerances, no mocking
   the subject under test, no hardcoded expected values, no catch-all error
   handling. The tripwire (G08) diffs for exactly this.
4. When a gate fails, fix the code. Reproduce with the printed command, and
   address the root cause. After 3 failed attempts on the same gate, stop and
   report what you learned instead of iterating blindly.
5. Run `./scripts/gates.sh t1` (needs `BASE_REF`, defaults to `origin/main`)
   before pushing — **after committing**, because the diff-based gates read
   `origin/main...HEAD` and see nothing at all while your work is still in the
   working tree. A pre-commit run that reports G08 "clean" is not evidence; run
   the same command again on the committed branch. The full suite stays CI's job
   per §3.1.
6. New tests cite their invariant (`// SPEC INV-xxx.`); G05 rejects
   orphaned invariants and unknown IDs.
7. Fixing a bug the gates missed? Follow `docs/ESCAPE_TO_GATE.md` —
   regression test, SPEC invariant, red-team case, escapes-log row, in
   that order. The flywheel only turns if you turn it.
8. Report honestly: what you ran, what passed, what you could not run, and
   what remains unverified.

## 11. Releases: when to cut one (agent decides, owner doesn't)

The release workflow (`.github/workflows/release.yml`) is the executable
truth. Tags (`git tag vX.Y.Z && git push origin vX.Y.Z`) trigger automatic
build + publish (see `docs/releases.md` for full policy). The agent
evaluates after every merged green batch and cuts a release when ALL hold:

- Something the owner can feel changed (feature, fix, copy). Gate/CI/
  refactor/test-only/docs-only deltas ride silently.
- The work's PR went in green (T1 + Unit tests) with evidence intact.
- Nothing known-broken is pending; no unverified claims in release notes.

Not worth releasing: invisible delta, same batch already tagged, or red tree.

Versioning: patch (`x.y.Z`) fixes/copy, minor (`x.Y.0`) features/settings.
Major stays `0` until owner declares otherwise. Watch Release workflow
to green; report download link. Tags publish — never push casually,
never move/delete a published tag.

## Lessons Learned

- [2026-10-07, Space Bunny Free] `./scripts/gates.sh t1` run *before* committing is a
  green light that means nothing: the diff-based gates read `origin/main...HEAD`, so
  while the work is uncommitted HEAD is still the base and the diff is empty. Two
  reskin PRs (#186, #187) both reported `no test-weakening patterns found` locally and
  both failed CI's G08 with 8 and 13 findings respectively. Run the gate after the
  commit, or run `python3 scripts/gates/test_weakening_check.py --base origin/main`
  directly, which reads the same committed range and cannot be fooled by a dirty tree.
  Verified by: `gates.sh t1` printing "clean" with six modified files unstaged, then
  the same script run directly on the identical tree printing the findings CI did.

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
- [2026-09-27, Space Bunny Free] A test earns its place only if it fails when the
  code is **wrong**, not when it is merely **different**. The qualifying cases
  are: a defect just fixed, a contract that has already bitten us (44px targets,
  a tap actually reaching its row, a viewport not clipping its content), or an
  invariant in `QUALITY.md`. Of 18 tests added across the four settings
  reskin batches, 5 met that bar, 4 were reasonable, and 3 asserted only that a
  widget was absent -- so they would fail once the reskin deleted the type and
  would have to be deleted by hand. Mechanical renames get no per-item test: a
  reskin PR tests the defects it finds, not one assertion per file it converts.
  Verified by: removing the row count and the value text from the engine slider
  and watching both new tests fail, then pruning the three absent-type asserts
  and finding the suite unchanged.
- [2026-09-28, Space Bunny Free] Several review tests are load-sensitive and will
  flake in a large run, because `pumpAsync` waits a fixed 80ms of *real* time for
  the controller's database futures and then pumps the fake clock by fixed amounts.
  Under CPU contention less real work fits inside that window, so the controller has
  not reloaded when the assertions run and they fail on absent data. `flutter test`
  gives each file its own isolate, so this is timing and not shared state: the same
  four directories failed three tests on one run and passed all 128 on the next,
  unchanged. Before blaming a change for one of these, re-run the file alone, and
  expect a large parallel run to be the trigger. The real fix is polling on a
  condition instead of sleeping a fixed interval, across the shared helpers.
  Verified by: `review_controller_test.dart` failing inside a 128-test run and
  passing 30/30 in isolation, with `pumpAsync`'s `Future.delayed` as the only
  wall-clock wait in the path.
- [2026-09-29, Muse Spark] "Run the specific test file" is not a budget: across
  eight phone-feedback PRs the agent ran each file 3-5 times (new-test-only,
  full file, stash fail-check, neighbouring files, repeat analyzes), plus a
  62-test engine file and a 15-test account batch locally — all work CI repeats
  on every push anyway. The owner's PC heated up for zero extra safety. Hence
  §3.1: iterate with --plain-name, one full-file run at the end, fail-check
  counts as run two, neighbours and ./verify are CI's job. Verified by: the
  owner reporting the heat and asking for the rule, against a history of green
  CI runs that had already covered every locally re-run file.
- [2026-09-28, Space Bunny Free] `build_runner` writes `lib/l10n/*.dart` with
  different line wrapping than what is committed, so a fresh worktree shows 52
  files and ~38,000 changed lines that are pure formatting. Run
  `dart format lib/l10n/` after codegen and the diff disappears entirely.
  Do not commit the churn, and do not read a non-empty `git status` as real
  work: check whether `git diff lib/l10n/` is a formatting-only rewrite before
  concluding anything about what a worktree has changed. Verified by: 52 files
  / 13,844 insertions / 24,106 deletions before the format, empty after, with
  the test suite green either way.
- [2026-09-29, Space Bunny Free] Merging a batch of PRs is not delivering it: the
  owner's own `fvm flutter run` in the primary checkout is the acceptance gate for
  user-visible work, and that checkout stayed at `ea1d09678` while seven PRs merged
  to `388b38f3e`. A whole session was spent on "the Account section is missing from
  Settings" — a feature that arrived in PR #84, *after* the frozen commit — plus a
  second app window from a worktree, so two windows with different features produced
  contradictory observations that were chased in the wrong direction each time. After
  merging, pull `main` in the primary checkout and tell the owner it is current;
  verify with `git log --oneline -1` there against `origin/main`. Verified by: the
  Account section being unconditional in `SrsSettingsScreen` and present in
  `388b38f3e` but absent from `ea1d09678`, and the checkout log showing the stale
  commit throughout.
- [2026-09-29, Space Bunny Free] *"We couldn't find any user by this name"* blames
  the user's typing and sends you auditing a regex and a repository that are
  byte-identical to upstream. **Superseded 2026-10-02:** the host default is now
  `lichess.org` (#124), so `--dart-define=LICHESS_HOST=lichess.org` is a no-op,
  and sign-in is verified working — that symptom had five separate causes, not
  one. Two parts of the original note still hold: no Lichess client accepts a
  password, so a "user + password" request is not implementable; and the
  ruled-out suspects (`_emailRegExp`, `AuthRepository`, `AuthController`,
  `UserRepository.usernameExists` are byte-identical to upstream) stay ruled out.
  Current state, the five-defect chain, and what is still unverified:
  `docs/open-email-login-handoff.md`. Verified by: the owner signing in through
  the browser on Linux desktop, and `GET /api/study/Gg4E2sIS.pgn → 200` in the
  app's `http_log`.
- [2026-09-29, Space Bunny Free] A worktree is not a working directory, it is
  the *only* place you may write, and the isolation rule is easy to break by
  inattention rather than by a `git reset`. Editing two docs in the shared main
  tree while a worktree sat idle put the edits among another agent's in-flight
  l10n churn, where they would have been committed as part of unrelated work or
  reverted with it. Nothing was lost because the diff was saved first, but it
  had to be extracted, checked line by line to confirm it contained only those
  two files' changes, reverted, and redone in a worktree. Do all editing inside
  the worktree and branch from `origin/main`, not local `main`: local main was
  1 commit ahead of origin with another agent's unpushed work, so a branch cut
  from it would have carried their commit into the PR. Verified by: diffing the
  two files to confirm 29 added lines and 0 deletions before reverting, then
  re-applying the same patch on a fresh branch off `ea1d09678`.
- [2026-09-30, Space Bunny Free] `e57fcb411` is NOT an ancestor of `HEAD`, so
  `git log HEAD..upstream/main` overstates the upstream gap: fixes reach this fork
  only as hand-squashed cherry-picks, and at least five are already applied under
  different hashes (`a99dad8a1`→`bcb66ad5b`, `25cf0fae5`→`a0d9ed580`,
  `60309eb8d`→`0fad2d1e3`, `c60a0edd8`→`7f2a0c4e7`, `498ce10a7`→`02d91a23f`).
  Never attempt `git merge upstream/main` — it conflicts on files that are already
  correct. Realign subsystem-by-subsystem per `docs/upstream-realign.md`; current
  state and Take ranking in `docs/upstream-audit-2026-09-30.md`. Verified by:
  `git merge-base --is-ancestor e57fcb411 HEAD` returning non-zero with 167
  upstream-only commits, and each pair confirmed against both diffs.
- [2026-09-30, Space Bunny Free] "387 surviving upstream files have no per-file
  GPL header" is a false positive: upstream puts no per-file headers in those same
  files either, and licensing here is file-level `LICENSE` + `COPYING.md` exactly
  as upstream does it. Do not re-raise it in a future audit without first
  checking the same files at `upstream/main`. Verified by: header grep scoring 0
  for both fork and upstream on `study_controller.dart`, `network/http.dart`,
  `analysis_screen.dart`, `board.dart`, `game.dart`, with `LICENSE` and
  `COPYING.md` present in both trees.
- [2026-10-01, antigravity/gemini-3.8-flash-tiered] GitHub branch protection
  requires both 'T1 fast gates' and 'Unit tests on ubuntu-latest'. When a PR touches
  only files in docs/**, gates.yml does not trigger, leaving 'T1 fast gates'
  unreported and blocking merge even with --admin. Verified by: PR #119 failing
  merge with 'GraphQL: Required status check \"T1 fast gates\" is expected', while
  PR #112 merged cleanly because touching AGENTS.md triggered gates.yml.
