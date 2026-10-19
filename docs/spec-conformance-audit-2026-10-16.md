# Spec conformance audit — 2026-10-16

A single-pass check of the codebase at `bad86151f` against `PRODUCT.md`,
`MVP.md`, `SPEC.md` and `QUALITY.md`. It exists to answer the question the suites
cannot: do the 44 invariants hold for the right reasons, and is anything the spec
claims still false about the code?

Method, so the reader can weigh the evidence:

- **Suite and gates.** `Tests` was green on `main` (run 38949459645) and
  `./scripts/gates.sh t1` was clean — 44/44 invariants traced (G05), ratchets OK,
  G03 clean. That is what answers "is the suite green"; it is not repeated here.
- **Per-invariant reading.** Each invariant was read against its implementing
  code *and* its covering test, judged on one question: would the test fail if the
  invariant broke? G05 proves an invariant is **cited**, never that the test checks
  the right thing. The open findings below are exactly that gap.
- **Live data.** The owner's database was inspected **read-only**. The app was
  not driven by hand (see "Not verified").

## Headline

- 44/44 invariants traced; CI green; ratchets OK.
- The live DB confirms INV-068 (fresh / due / scheduled partition).
- One invariant was **stale, not the code** (INV-006) → fixed in #191.
- One gap was **already fixed** while this audit ran (INV-067, #179).
- Open: a wording drift (INV-060), three tests that cannot fail
  (INV-002 / INV-005 / INV-051), and 117 orphan rows in the live DB.
  Dispositions recorded 2026-10-19 at the end of this document: F2 (#227),
  F3 (#236), F4 (#232 and #223/#238), F5 (#239).

## Open findings

### F1 — INV-060 says "repertoire move", the app says "study move" *(owner decision)*

INV-060 quotes the lapse announcement as `Not this move. The repertoire move is
{san}.`; the app ships `Not this move. The study move is {param}.`
(`lib/l10n/app_en.arb:313`). The design docs disagree with each other too:
`design/docs/01-identity.md:96` says "study move", `design/docs/04-screens-and-flows.md:99`
says "repertoire move". The covering test hardcodes the shipped wording, so the
suite would not notice either way. Raised as **Q7** in `docs/open-questions.md`.

### F2 — INV-002's test cannot fail

`test/review/review_service_test.dart:43` is titled "incremental persistence:
moves save state and event **without rewriting trees**", but the body only reads
back the state and the events. It never snapshots the chapter blob or counts
writes, so it passes unchanged if `saveAnswerBatch` rewrote the whole tree. The
behaviour looks correct; the test simply cannot catch a regression.

### F3 — INV-005 migration coverage is partial

"Every shipped schema version upgrades without data loss" is proven end-to-end
for four steps only: v12→13 and v13→14
(`test/persistence/sqlite_study_repository_test.dart:1896`, `:1938`), v16→17 and
v17→18 (`test/db/srs_upgrade_test.dart:35`, `:92`). Versions v6–v11 and v14–v15
are never upgraded from an on-disk database.

### F4 — INV-051's chunk and prefetch tests cannot fail

- `test/persistence/sqlite_study_repository_test.dart:1745` ("deleteStudy chunks
  large decision sets (>400)") inserts 450 decisions — under SQLite's ~32,766
  bind-parameter ceiling — so a single unchunked `DELETE ... IN (...)` passes it.
- `test/review/review_engine_test.dart:646` (prefetch) asserts only that all 10
  decisions are surfaced, which holds with the prefetch buffer disabled.

### F5 — 117 orphaned `srs_review_state` rows (live DB)

The live database has 589 review states for 472 matching decisions: **117 rows
whose `decisionId` appears in no `srs_decision` row**. There is no foreign key
from `srs_review_state` to `srs_decision`, so nothing cascades them in general;
`deleteStudy` and `deleteChapter` do clean their own decisions explicitly. They
are inert for the due count (those queries join `srs_decision`), but the origin
was not identified and the rows should not be there.

### F6 — lower-severity notes (not confirmed defects)

- **INV-030.** `ReviewScope.matches` normalizes names (case, `defence`→`defense`),
  but the session path (`startSession`'s opening branch) compares exact `trim()`
  values, so the normalization the invariant names is not the one the session
  build uses. Both sides currently derive from the same stored value, so it is
  latent, not live.
- **INV-033.** The covering list names `test/review/review_engine_test.dart`,
  which contains **zero** castling assertions. Equivalence is proven by the
  primitive in `test/domain/entities_test.dart` and one board test; the
  king-takes-rook form is never driven through grading.
- **INV-001.** Three of four citations prove something else (PRAGMAs, frame-0 UI,
  ghost FK removal); only `test/persistence/sqlite_study_repository_test.dart`
  actually closes and reopens the store.
- **INV-025.** "A lapse resets the streak" is false for `ChessFsrsScheduler`,
  which deliberately keeps `repetitionCount` on lapse; the default `simple`
  scheduler conforms, and the FSRS deviation is asserted on purpose.
- **INV-068.** A state row with a null `nextDueAt` is classed due, which the
  invariant's first sentence ("its scheduled date has arrived") does not cover.
  Intentional per `test/domain/due_status_test.dart`.
- **Domain time.** `lib/src/domain/study.dart` and `chapter.dart` default
  `createdAt` to `DateTime.now()`. The banned-API rule scopes time reads to
  schedulers / coordinator / review state / session, so this is not a gate
  violation, but a domain entity reading the wall clock sits against the spirit
  of INV-040/042.

## Fixed during or by this audit

- **INV-006 — stale spec, not a leak (#191).** The invariant claimed the login
  code, email and username are "never" sent as query parameters. They are: the
  mobile-code endpoints deliberately retry with them in the query string when
  lila demands it, and H4's `redactUriForLogging` blanks them before the
  `http_log` write. The invariant was restated to the contract the code actually
  keeps; no product behaviour changed.
- **INV-067 — already fixed (#179).** A direct `[Opening "..."]` header was stored
  unvalidated, so a name that merely mentions a family could become a hub. This
  landed during the audit window (2026-10-16 21:19), which is why it appears in
  no finding above.

## Disposition (2026-10-19)

- **F1 — still open.** Q7 is with the owner; nothing here can settle which
  wording is right.
- **F2 — closed by #227.** The INV-002 test now snapshots the chapter blob and
  records every study/chapter/decision writer, and fails when the answer path
  re-saves a decision.
- **F3 — closed by #236.** `test/persistence/migration_fixtures_test.dart`
  carries v6–v11 and v14–v15 through the real `openAppDatabase` path, built as
  "the current schema minus additions after N" so a stale strip fails loudly.
- **F4 — closed by #232 and #223/#238.** The chunking oracle now records the
  bound-argument count of every cleanup delete and fails if any exceeds the
  401-variable bound (fail-to-pass shown by raising `chunkSize` 400 → 1000 in a
  scratch mutation). The prefetch half: `review_session`'s buffer semantics are
  driven directly (null batch, refill threshold, lapse requeue behind the
  buffer, #223), and the engine's `prefetchBatchSize` / `prefetchRefillThreshold`
  pass-through is asserted in the wiring test (#238), so dropping or overriding
  it fails.
- **F5 — origin found, closed by #239.** The 117 sha1-keyed rows are 50 live
  canonical mirrors (a decision references them via `canonicalStateId`) plus 67
  unreachable ones. Cause: the v14/v16 canonical rekeys moved
  `position_knowledge_state` rows to the new keys and rewrote
  `srs_decision.canonicalStateId`, but never touched the `srs_review_state`
  mirror written next to each knowledge row (`saveAnswerBatch` writes the
  pair); the mirrors stayed under the old, pre-side-split keys. No delete path
  was involved, so the ledger's cascade-trigger idea was rejected as guarding
  the wrong mechanism. `rekeyCanonicalReviewState` now carries mirrors through
  the rekey and the v19→v20 upgrade step sweeps rows that neither a decision
  (by `id` or `canonicalStateId`) nor a knowledge row names; review events are
  untouched. Both test files fail on the pre-fix code.
- **F6 — unchanged.** The notes remain latent, none confirmed as a defect.

## Not verified

The runtime review-loop walkthrough was **not performed** — it needs a human with
the app running and was declined. Nothing in this document claims runtime
behaviour beyond "the app launches cleanly and renders the first-launch scene",
observed once before the walkthrough was dropped. Sound and haptics are
structurally outside the suite and are recorded in `docs/manual-test-log.md`.

## Caveat on the snapshot

The shared checkout fast-forwarded mid-audit (`5697f8e10` → `bad86151f`, with #179
landing at 21:19). F1–F5 were re-checked against `bad86151f` before being written
here; the earlier `INV-067` observation was against the pre-pull tree and is
recorded as fixed rather than open.