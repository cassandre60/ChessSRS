# MUTATION-04 — mutation audit of `openings_database.dart`

**Date:** 2026-10-23
**Stream:** 1 (Mutation Testing & Test-Gap Elimination)
**Class:** test-only (no production code)
**Target:** `lib/src/db/openings_database.dart` (47 lines, content hash `9f745f2c3`)
**Mapped test:** `test/db/openings_database_test.dart`
**Selection:** top NEVER-audited candidate from `ledger.py next --stream 1` after
the app_links round (#406). `srs_toast`, the next candidate, was skipped: seven
in-flight branches touch its test file.

## Engine settings used

```bash
python3 scripts/autonomous/mutation_engine.py \
  --source lib/src/db/openings_database.dart \
  --test-cmd "fvm flutter test test/db/openings_database_test.dart" \
  --max-mutants 100 --timeout 200 \
  --output-json /tmp/mut_openings.json
```

`--timeout 200` ≈ 10x the measured clean baseline (19.6 s wall). Full window
(the file generates only 3 candidates).

## Totals

| Outcome | Before | After |
|---|---|---|
| Killed | 0 | 2 |
| Survived | 3 | 1 (the documented equivalent) |
| Uncompilable | 0 | 0 |
| Kill rate | **0.0%** | 66.7% (2/3) |

## Why 0%: the mapped test never exercised the source

The pre-existing test opens `assets/chess_openings.db` directly from the
filesystem and checks an index — a real asset-integrity check, but it never
imports the service, so `_openDb`'s whole flow (directory creation, stale-version
cleanup, asset copy, read-only open) had no oracle at all. The same shape as
the #401/user.dart and app.dart rounds: the honest before-rate is 0% because
there was nothing to kill mutants with.

## Triage

**2 real gaps — closed by 3 new tests (1 → 4 in the mapped file), each red
under its mutant and green on the restored tree:**

| Mutant | Gap | Killing test |
|---|---|---|
| L28 `recursive: true → false` | nothing pinned that a fresh install builds the whole `.dart_tool/sqflite_common_ffi/databases` chain: with `recursive: false` the create throws (swallowed), `directory.list()` then throws and the provider fails | `a first run creates the databases directory, copies the asset and opens it read-only` |
| L46 `readOnly: true → false` | nothing pinned that the static openings dataset is opened read-only — a writable handle is how the shared dataset gets corrupted; the test asserts `CREATE TABLE` is refused | same test |

The same tests also pin behavior the regex pack cannot mutate: stale
`chess_openings*` files are deleted while unrelated files are kept (name
prefix, not a sweep), the copied file's bytes match the asset, and an existing
database is opened without being rewritten from the asset.

**1 equivalent — full mapped file green under the mutant, recorded EQUIVALENT
in `docs/AUTONOMOUS_MUTANTS.md`:**

- L43 `flush: true → false`: flush only affects durability under crash or
  power loss; any subsequent read sees identical bytes, so no test can
  distinguish the two.

## Mechanics worth recording

- The ffi factory pins `getDatabasesPath()` against the cwd of the FIRST
  resolution, so per-test cwd redirects do not isolate: tests share one temp
  root (cwd set once in `main()`) and each wipes the databases tree.
- The ffi factory treats a RELATIVE `openDatabase` path as relative to the
  databases directory, not the cwd — the existing-database test resolves its
  probe path via `getDatabasesPath()` for exactly that reason.
- Read-only is asserted behaviorally (a write must throw
  `DatabaseException`), not by inspecting options.

## Honest status

- Ran: one engine pass before (3 mutants, all survived) and one after (2/3
  killed); 3 per-mutant hand re-applications for triage; full mapped file
  green on clean code (4/4); `lib/` byte-identical after every restore.
- Not run: full suite and CI locally (CI lane runs on the PR); no runtime
  validation applies (no user-visible change).
- Tests added: 3 (1 → 4); no product code changed.
