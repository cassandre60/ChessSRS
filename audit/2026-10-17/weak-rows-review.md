# Weak rows — w2-review + author (verbatim digests; grade 3 rows are counted per file in coverage.md)

## test/review + test/view/review — walker "w2-review"

Grade 0/1 verbatim:

- review/review_service_test.dart:43 — "incremental persistence: moves save state and event without rewriting trees" — grade 0 — known F2 (2026-10-16 audit, not re-opened): asserts only persisted rows, never tree-write volume.
- review/review_engine_test.dart:1146 — "with no allowance left, a session offers due work and no introductions" — grade 1 — asserts only initialDueCount==3, invariant even if 40 fresh positions are wrongly queued.
- review/review_flip_study_test.dart:180 — "answering on one side leaves the other side due" — grade 1 — asserts blackAfter==blackBefore with both 0 under INV-068; the canonical-collision bug cannot move the observed number.
- review/review_side_scope_test.dart:103 — "a side scope counts exactly that side" — grade 0 — every assert compares 0==0==0 in an all-fresh fixture; any scope leak passes.

Grade 2, one line each (file:line — title — the mutation it would miss):

- review_service:182 — ReviewScope.all excludes inactive studies — misses an isActive-filter leak in the getDueCount path (both counts are 0-by-freshness).
- review_service:236 — ReviewScope.opening aggregates studies — misses the same class of dueCount leak (only the session leg is live).
- review_service:582 — EaseScalingScheduler schedules intervals — misses any mutation of the scaling factor (1.8 never influences an asserted value).
- review_service:1297 — headline due figure not clamped — the two duplicate getDueSummary calls are self-declared tautologies; misses any getDueSummary-only regression that leaves the spent-quota leg at 5.
- review_engine:684 — prefetch buffers and refills at threshold — misses refill firing at the wrong threshold (only "refill happens" is observed).
- review_engine:2454 — sideFromFen, White start FEN — misses an always-white constant (only sibling :2461 catches it).
- review_engine:2461 — sideFromFen, Black after move 1 — misses a parse mutation that reads the wrong field yet still yields black on this single FEN.
- review_continuity:287 — continuity defaults due-only and round-trips — misses a paired encode/decode bug (both-broken round-trip passes).
- review_side_scope:66 — each chapter reports the side it trains — misses swapped orientation labels (set {white, black} unchanged; downstream fixtures self-derive).
- review_side_scope:150 — side session smaller than unscoped — misses due-count regressions (the two initialDueCount==0 asserts are 0-by-freshness).
- review/move_latency:127 — graded move inside one display frame — misses any real regression landing under the 16ms median bound (wall-clock, machine-dependent).
- session_constructor_cost:104 — measured at a scale that matters — misses 2–5× constructor slowdowns (threshold ~10× measured).
- session_constructor_cost:149 — inside one frame at realistic sizes — misses all sub-100ms regressions at 2000 decisions (headroom is deliberate).
- session_constructor_cost:178 — tree walk is the smaller half — a proportional slowdown of both passes keeps the ratio and passes; contention-flakeable.
- view/review/repertoire_import_dialog:85 — picked file after dismissal doesn't crash — misses a continuation delayed past the fixed 200ms window (:126) — bug exists, unobserved.
- review_screen:124 — medium-window layout — misses a copy-column overflow outside the asserted board-geometry probes.
- review_screen:240 — renders board and handles moves — misses on-screen auto-play ordering/content (only "Nothing due." after fixed 700ms pumps).
- review_screen:286 — RepaintBoundary isolates render layer — misses any isolation-semantics mutation short of deleting the ancestor (structure-only assert).
- review_screen:318 — lapse feedback and reguess — misses a re-test that settles just outside the fixed 700ms pacing window.
- review_screen:376 — Open in analysis at drilled position — misses an analysis entry that resolves after the fixed 200/500ms pumps.
- review_screen:429 — Reveal answer continues session — misses a reveal handler completing after the fixed 700ms wait.
- review_screen:671 — Analyze opens StudyScreen — would miss a state settling outside its fixed 200/500ms pumps (partially duplicate of :714/:1143).
- review_screen:714 — multi-chapter Analyze — same fixed-pump window; partially duplicate of :671.
- review_screen:1143 — Analyze survives slow chapter load — misses a delay-guard regression tuned to the baked-in 400ms delay + fixed pumps (constants drift defeats it).
- review_screen:1190 — commentary pauses advancement — misses a double-advance mutation that still lands on the completion state past the 700ms wait.
- review_screen:1247 — board overlay continues advancement — misses a state settling outside the fixed 700ms window; only completion, not timing, is asserted.
- review_screen:1293 (×2, Enter / arrowRight continue) — misses an advance that settles outside the fixed 700ms (1293–1328); completion-only assert.
- review_screen:1391 — drawer/caught-up progress metrics — misses a classification regression that materialises past the fixed 700ms move pacing (1449/1453).
- review_screen:1847 — selected row steps quiet labels to ink2 — misses a second incorrectly tinted row (set-of-colors assert counts membership, not multiset).
- review_screen:2053 — narrow layout without overflow — misses any RenderFlex overflow (harness swallows errors; takeException null near-vacuous).
- review_screen:2116 — offers the other colour with dues — misses an offer that resolves outside the fixed 700ms pacing (2160/2162).
- review_screen:2212 — hides cross-colour in narrowed scope — same pacing window miss (2254/2256).
- study_actions_sheet:245 — Create row reachable on short phone — misses the row clipped below the viewport (asserts rect height > 0 only).

TOP5 (walker): service:43 (0), side_scope:103 (0), engine:1146 (1), flip:180 (1), review_screen:1847 (2).

## Author's own walk (verbatim, self-graded)

test/review/review_order_test.dart (SPEC INV-066):

- :190 "by-line order walks each chapter in tree order despite due dates" — grade 3 — pins the exact visited-node sequence ['node-a-root','node-a-e5','node-b-root','node-b-d5']; reorder/skip mutations fail.
- :211 "due-date order still serves the most overdue first" — grade 2 — first prompt asserted only; due-date ties and the rest of the order unasserted.
- :236 "random order is deterministic per seed and covers the due set" — grade 2 — two seeded sessions must be identical and cover the four-card set; an algorithm change that stays deterministic and covers the set passes.
- :260 "the daily quota still cuts the most overdue first under by-line order" — grade 3 — quota=1 keeps the most urgent card and remainingDueCount==1; arbitrary-order quota cuts fail.

test/platform/app_store_links_test.dart:

- :20 "the package name is this app's own application id" — grade 3 — reads the gradle config; rename drift fails.
- :34 "the Play links name this app" — grade 3 — scheme/id/host/params exact.
- :43 "the App Store link is either this app's listing or a search, never another app" — grade 3 — pins the honest-options contract with both branches valid.
- :62 "no listing points at the upstream project it was forked from" — grade 3.
- :78 "the settings screen hardcodes no store identifier of its own" — grade 2 — source scan over a hand-maintained list; a new settings entrypoint added later is silently uncovered.

test/platform/verified_link_claims_test.dart:

- :30 "Android does not auto-verify lichess.org links" — grade 3 — filter pinned present, autoVerify absent, comments stripped.
- :48 "iOS claims no associated domains" — grade 3 — same shape.
- :62 "the removal is documented where it happened" — grade 2 — M20 marker existence; a marker carried by unrelated text passes.
