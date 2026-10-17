# Weak rows — w2-network/analysis/utils (verbatim digest; grade 3 rows counted per file in coverage.md)

No test graded 0 or 1 in this walker's scope.

Grade 2, one line each (file:line — title — the mutation it would miss):

- network/socket_test.dart:593 — does not reconnect when closed while a connection attempt is in flight — misses a phantom reconnect that fires beyond/mispaced within the real 50/400ms race against the 100ms delayed factory.
- socket_test:621 — discards a connection that succeeds after the client was closed — misses a stale channel adopted or closed outside the real 50/200ms settle window.
- socket_test:1441 — reconnects the socket as soon as the device is back online — misses a lag/connection event that lands after the 20ms real settle.
- socket_test:1699 — reconnects the socket when a failed connectivity check is followed by an online one — misses a reconnect landing beyond the 20ms settle.
- socket_test:1738 — does not reconnect the socket while the app is in the background — misses a suppressed attempt firing just after the 20ms settle.
- socket_test:1845 — reports no lag as soon as the device is known to be offline — misses a lag still propagating at the 20ms settle.
- connectivity_test:49 — a connected socket has no say in the status — misses a socket-driven status flip needing more than the 20/50ms settles.
- http_redaction_test:47 — redacts the email address and username — misses over-redaction (whole query string stripped, secret and diagnostics together).
- http_redaction_test:83 — matches the parameter name case-insensitively — misses case-insensitivity implemented by nuking every query param.
- http_redaction_test:108 — handles a relative URI (FCM registration shape) — misses relative-URI over-redaction (route not positively pinned).
- view/analysis/analysis_screen:238 — offers no move times chart for a game played without a clock — misses a Times tab that never renders at all (absence-only).
- analysis_screen:378 — Cannot change variant in PGN analysis — misses a menu item rendered but silently dead (absence-only).
- analysis_screen:960 — computer variations not displayed when server analysis disabled — misses the variation widget broken universally (absence-only gate).
- analysis_screen:1104 — not displayed if computer analysis not allowed — misses EngineLine broken universally.
- analysis_screen:1111 — not displayed if computer analysis not enabled (analysed game) — misses EngineLine broken universally.
- analysis_screen:1125 — not displayed if engine disabled by preferences — misses EngineLine broken universally.
- analysis_screen:1132 — not displayed if disabled by user preferences — misses EngineLine broken universally.
- analysis_screen:1192 — gauge not displayed if computer analysis not allowed — misses EngineGauge broken universally.
- analysis_screen:1199 — gauge not displayed if computer analysis not enabled — misses EngineGauge broken universally.
- analysis_screen:1213 — gauge not displayed if engine disabled by preferences — misses EngineGauge broken universally.
- analysis_screen:1243 — arrow not displayed if best-move arrow disabled — misses BoardShapeWidget broken universally.
- analysis_screen:1250 — arrow not displayed if computer analysis not allowed — misses BoardShapeWidget broken universally.
- analysis_screen:1257 — arrow not displayed if engine disabled by preferences — misses BoardShapeWidget broken universally.
- utils/rate_limit_test:6 — should call the callback after the delay — misses timing-shifted mutations inside the wall-clock window (negative half is flake-prone).
- rate_limit:18 — not more than once if called multiple times — misses dedupe differences inside the 150ms window.
- rate_limit:34 — cancels the previous callback — misses supersede behavior variations inside the 150ms window.
- rate_limit:47 — cancel should cancel the callback — misses a cancel racing the 20ms pre-cancel gap.
- rate_limit:70 — calls only once within delay — misses throttle dedupe differences inside the 150ms window.
- rate_limit:86 — drops a call within the delay when not trailing — misses drop-vs-defer differences landing inside the window.
- rate_limit:96 — trailing call once the delay expires — misses a trailing run at the window's edge.
- rate_limit:107 — coalesces calls into a single trailing run — misses last-wins differences inside the 300ms window.
- rate_limit:117 — a trailing run opens a new delay of its own — misses re-arm timing differences inside the two 150ms windows.
- rate_limit:130 — cancel drops a pending trailing call — misses a cancel racing the 150ms window.
- rate_limit:140 — multiple calls if delay passed — misses series-timing differences inside three 150ms windows.
- utils/l10n_test:90 (de/fr/ja/ar rows) — renders the English fallback — pins generated strings, not lib logic; breaks legitimately when Crowdin translates.

TOP5 (walker): rate_limit file (11/12 tests wall-clock `Future.delayed` chains where fakeAsync would be instant and exact), socket 593/621 (50–400ms races), analysis_screen absence cluster (13 tests), http_redaction negative-only asserts (47/83/108), socket/connectivity 20–50ms settles (1441/1699/1738/1845 + connectivity:49).

Fixed real sleeps passed through this scope: socket :610(50ms) :615(400ms) :639(50) :642(200) :1462(20) :1731(20) :1757(20) :1854(20) (+ :1458/:1727/:1769 with 1s timeout polls); connectivity :64(20ms) :72(50ms); rate_limit :12(50) :14(100) :30(150) :43(150) :53(20) :55(150) :82(150) :90(50) :92(150) :100(50) :103(150) :113(300) :122(150) :126(150) :136(150) :149(150) :153(150) :157(150). None in http_test, server_status, http_redaction, the analysis files, or the other utils files (note: non-fakeAsync socket pong tests use real 5ms pong timers but always await stream events).
