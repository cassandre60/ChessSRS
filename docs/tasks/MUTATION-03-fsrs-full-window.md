# MUTATION-03 — `chess_fsrs_scheduler.dart`, full candidate window

**Verdict: 0 real gaps. 4 surviving mutants, all four provably equivalent. No tests added.**

This is a **confirmation run**, not a new audit. The file is already `COMPLETED` in
`docs/AUTONOMOUS_WORK_LEDGER.md` (PR #203, content hash `f23a3db68`, *"76 curated mutants: 20
killed, 23 compile-killed, 33 survivors; 29 real gaps closed with 9 tests … 4 documented
equivalents (L144, L152, L236, L330)"*). The content hash is unchanged since that audit, so the
dedup rule applies. What this run adds is different evidence: #203 was a **hand-curated** mutant
set, while this is the **mechanical generator's complete 77-candidate list**, every shard
evaluated. It reproduces #203's four equivalents exactly and finds nothing new.

## Run metadata

| | |
|---|---|
| Target | `lib/src/domain/chess_fsrs_scheduler.dart` |
| Content hash | `f23a3db6876ebd271b22b6c24f24ebc201fb4a34` (`git hash-object`) |
| Base | `origin/main` @ `ed86543f1`; target and test file unchanged since the runs began |
| Test command | `fvm flutter test test/domain/chess_fsrs_scheduler_test.dart` |
| Test file | 25 tests, baseline green, ~27 s wall including Flutter startup |
| Engine | `scripts/autonomous/mutation_engine.py` at `origin/fix/mutation-engine-instrument` (PR #222); generic-suppression + timeout bucket + `--skip-m`. Used as an uncommitted local file, excluded from this PR. |
| Timeout | `--timeout 240` per mutant (default 60 is under 3× the baseline and was raised for the graph_aware run for the same reason) |
| Shards | `--max-mutants 20 --skip-m 0 / 20 / 40 / 60` |

```bash
python3 scripts/autonomous/mutation_engine.py \
  --source lib/src/domain/chess_fsrs_scheduler.dart \
  --test-cmd "fvm flutter test test/domain/chess_fsrs_scheduler_test.dart" \
  --max-mutants 20 --skip-m <0|20|40|60> --timeout 240
```

## Shard results

| Shard | `--skip-m` | Window | Killed | Survived | Uncompilable | Timeout |
|---|---|---|---|---|---|---|
| 0 | 0 | 0–19 / 77 | 11 | 0 | 9 | 0 |
| 1 | 20 | 20–39 / 77 | 11 | 0 | 9 | 0 |
| 2 | 40 | 40–59 / 77 | 15 | 3 | 2 | 0 |
| 3 | 60 | 60–76 / 77 | 12 | 1 | 4 | 0 |
| **Total** | | **77 / 77 (100 %)** | **49** | **4** | **24** | **0** |

Kill rate over killable mutants: **49 / 53 = 92.5 %**. `lib/` verified byte-identical to
`origin/main` after every shard (`git diff --exit-code -- lib/` empty; hash re-checked).

## The four survivors — all equivalent

| # | Line | Mutation | Verdict |
|---|---|---|---|
| 2/1 | 144 | `elapsedDays < 0 ? 0.0 : elapsedDays` → `< 0` → `<= 0` | **equivalent** |
| 2/3 | 152 | `raw.isFinite && raw > 0 ? raw : 0.0` → `> 0` → `>= 0` | **equivalent** |
| 2/14 | 236 | `diffMs <= 0 ? 0.0 : diffMs / _dayMs` → `<= 0` → `< 0` | **equivalent** |
| 3/16 | 330 | `if (steps <= 0) return const [];` → `<= 0` → `< 0` | **equivalent** |

Why each is equivalent — in every case the moved boundary is the value that makes both arms
return the same thing:

- **L144.** At `elapsedDays == 0`, the true arm returns the literal `0.0` and the false arm returns
  `elapsedDays`, which *is* `0.0`. The subsequent `math.pow(1 + kFsrsFactor * t / stabilityDays,
  …)` sees the same `t`.
- **L152.** At `raw == 0`, the ternary's fallback is `0.0` and the mutant returns `raw`, i.e.
  `0.0`. For `raw < 0`, `>= 0` is false just like `> 0`, so both yield `0.0`. `raw == 0` is the
  only reachable equality, and it comes from `stabilityDays == 0` (the test at line 63 pins that
  `fsrsIntervalForTarget(0.0, 0.90) == 0.0`). Signed zero is not a distinction here: `-0.0`
  reaches the same `clamp(minIntervalDays, …)` as `0.0`.
- **L236.** At `diffMs == 0`, the mutant computes `0 / 86400000 == 0.0`, the value the original
  assigns in its true arm. A same-instant review is exactly the `elapsedDays == 0` case.
- **L330.** At `steps == 0`, the original returns a `const []`; the mutant falls through to
  `for (var i = 0; i < 0; i++)`, runs zero iterations and returns `List.unmodifiable(<double>[])`.
  Both are empty and unmodifiable, and `Step==0` is already pinned by the test at line 332
  (`isEmpty`). No observable difference.

These are the same four lines #203 documented as equivalents, found independently by the
generator. That agreement is the useful part: it means the curated audit did not miss a behaviour
that only the mechanical list reaches.

## The 24 uncompilable mutants are instrumentation noise, and now of one kind

All 24 are flow-analysis breaks, not test gaps:

- **20 × `&&` → `||` inside an `==` field chain** (lines 86–103 on `ChessFsrsParams`, 307–310 on
  `ChessFsrsScheduler`). `&&` binds tighter than `||`, so flipping any link splits `other is T &&
  …` into `(other is T && …) || …` and the following `other.wN` is no longer promoted to non-null
  — `Operator '==' isn't defined for 'Object'`-class errors.
- **2 × `!= null` → `== null`** at line 234 (`if (anchor != null)`), same promotion loss.
- **2 × `!=` → `==`** at line 234, which also unpromotes `anchor` for the member access below.

Worth recording for PR #222: **zero generic-type candidates appeared in this run.** The
graph_aware run (#217) lost 15 of 20 slots to `List<String>` → `List <= String>`; this file is
just as generic-heavy (`Map<String, DateTime>` in `hashCode`, `List<double>` in the preview) and
the generic-angle heuristic suppressed all of them. The remaining waste is 24/77 = 31 % of the
budget on null-promotion, which is exactly the class the engine header still lists as unfixed.

## Duplicate-target finding (for the owner, not decided here)

The ledger row for this file exists on `main` and matches the content hash exactly, yet
`IMPLEMENTATION_PLAN`/catalogue still lists it as a live Stream 1 target. Two consequences:

1. An agent that reads the catalogue and not the ledger will repeat a completed audit — which is
   what happened here. The brief that sent this run predates the ledger row's merge (it landed in
   the #224 sweep), so the collision was unavoidable from inside the task.
2. The `[x]` checkbox and the row disagree in emphasis: the row is the authoritative record.

Suggested (owner decision): the catalogue's Stream 1 target list should point at the ledger rather
than enumerate files, or the ledger row's hash should be checked by whatever dispatches these
tasks. Not changed in this PR.

## Honest status

- **Ran:** four engine shards covering all 77 candidates; baseline green before each shard;
  `lib/` verified byte-identical to `origin/main` after each shard; targeted test file only.
- **Not run:** full suite and CI `Tests` (CI's job); no runtime or visual validation applies (no
  user-visible change). No local `./verify`.
- **Tests added:** none. There is no surviving non-equivalent mutant to be red against, and a test
  that only pins an equivalent mutant would pass on both the mutated and clean code — a vacuous
  test, which the Stream 2 rules forbid.
- **Rate-limit/quota episodes:** 0.
