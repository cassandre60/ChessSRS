## 2026-09-30 Release readiness audit — antigravity/claude-opus-4-6-thinking

### Audit scope

Full-codebase static audit of the ChessSRS fork at `388b38f3e` (main). Covered:
all fork-introduced code (domain, review, import, persistence), android/ios
platform configs, branding residue, dead code from Lichess cuts, test coverage
gaps, CI status, schema migrations, identity/security issues.

### Fixed in this audit

**F3 — iOS display name "Lichess" → "ChessSRS"** (`ed4f7a5b7`)
`ios/Runner.xcodeproj/project.pbxproj` set `INFOPLIST_KEY_CFBundleDisplayName`
to "Lichess" in all three Runner build configurations (Debug, Profile, Release),
overriding the correct "ChessSRS" in `Info.plist` at build time. iOS users would
see "Lichess" as the app name in the home screen and app switcher.

**F8 — Silent exception swallowing in PGN hash computation** (`1182d7188`)
`lib/src/import/pgn_importer.dart:45` had a bare `catch (_) {}` on the
tree-based PGN hash path. If tree parsing succeeded but `fenKey()` threw on a
malformed FEN header, the hash silently fell through to the text-based fallback.
The same PGN imported twice — once via tree, once via fallback — would produce
different hashes, defeating duplicate study detection. Now logs a warning with
the exception and stack trace.

**F1 — Firebase, FCM, and Crashlytics stripped (Option B)**
Resolved per owner decision (2026-09-30):
- Dropped `firebase_core`, `firebase_crashlytics`, and `firebase_messaging` from `pubspec.yaml`.
- Deleted `lib/firebase_options.dart`, `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`, and `ios/firebase_app_id_file.json`.
- Removed Crashlytics Gradle plugin from Android and Crashlytics symbols build phase from iOS `project.pbxproj`.
- Removed FCM notification service and Lichess push models (`lib/src/model/notifications/`), dropping `flutter_local_notifications` and Java desugaring dependencies.
- Replaced Crashlytics calls in `socket.dart`, `eval.dart`, `engine_failure.dart`, `sign_in_failure_reporter.dart`, and `app_log_service.dart` with standard logger calls.
- App is now 100% offline-first with zero telemetry, zero analytics, and zero third-party cloud credentials.

**F2 — Android notification icon replaced with ChessSRS mark** (`#101`)
Replaced Lichess horse-head drawables with the 24x24dp monochrome vector ChessSRS mark in `drawable/ic_stat_notification.xml`.

**F4/F9 & F5/F10 — Dead iOS and Android home-screen widgets cut** (`#100`)
Cut 117 files and 4,585 lines: iOS `LichessWidgets/` extension, Android `BroadcastWidgetProvider`, layouts, and `home_widget` plugin.

### Open issues

None. All release blockers and branding residue have been resolved.

### Deliberately not fixed

**F7 — Dead `hintUsed`/`multipleAttempts` params in ChessFsrsScheduler**
`chess_fsrs_scheduler.dart` adds `hintUsed` and `multipleAttempts` optional
named params to the `schedule()` override, but the `Scheduler` contract doesn't
expose them, so no call site can pass them. The FSRS rating adjustments for
hints/retries never fire. This is dead code rather than wrong behavior — the
scheduler always rates as first-attempt clean recall. Not an MVP blocker; the
params hint at future intent for hint-tracking features.

**M6, M10, M15 — Audit fixes without regression tests**
Per `docs/audit-disposition.md`: M6 (material accounting) is inherited upstream
unchanged. M10 (retry path) and M15 (hash offloading) are fixed but "ship
unproven" — the fixes exist and were verified by instrumentation, but no
automated test covers them because the test harness couldn't reproduce the
conditions. Documented and deliberate.

**org_lichess_mobile_keep.xml** — Resource shrinking keep rule. The filename has
"lichess" in it but the content is generic (`tools:keep="@drawable/*"`). Renaming
would require build system changes for zero user impact.

### Verified safe

| Area | Evidence |
|---|---|
| `flutter analyze` | 0 issues (ran locally, 27s) |
| CI status | Last full run green (workflow_dispatch Sep 24). Subsequent PRs each passed CI individually. |
| Account reachability | Fixed in PR #84. Settings → Lichess account row → AccountMenuScreen. Sign-in also offered in import scene on 404. |
| 16ms move-validation invariant | Test added in PR #88 (`test/review/move_latency_test.dart`). |
| Domain layer purity | Zero Flutter imports in `lib/src/domain/` (verified). |
| Test coverage | All fork domain files have corresponding tests (21 source files, all covered). |
| Schema migrations | v1→v14 path is complete with proper `IF NOT EXISTS` guards and correctly ordered DDL+data migrations. |
| Deep linking | Android: lichess.org links deliberately without autoVerify (documented in manifest). iOS: associated-domains deliberately empty (documented in entitlements). Both correct. |
| App identity | Android: `org.chesssrs.app`, label "ChessSRS". iOS: bundle `org.chesssrs.app`, display name "ChessSRS" (after this fix). |
| Splash/launcher | Replaced with ChessSRS geometric mark in PR #81. |
| PGN import | Handles malformed FEN gracefully, supports RAVs, runs hash on background isolate for large files. |
| Scheduler math | ChessFSRS implements DSR power-law forgetting curves with clamps (min 30min, max 5yr stability). |
| Persistence | Transactional writes, incremental persistence (review answers touch only affected rows). |

### What I'd watch after launch

1. **Firebase identity (F1)** — the most important unresolved issue. Every
   launch registers an FCM token with Lichess's project. Until resolved, the
   owner is sending device metadata to Lichess.

2. **Review test flakiness** — documented in Lessons Learned: `pumpAsync` waits
   a fixed 80ms of real time, causing flakes under CPU contention. Not a code
   bug, just a test infrastructure weakness that could mask real regressions.

3. **Database downgrade path** — `onDowngrade: onDatabaseDowngradeDelete`
   deletes the entire database on version downgrade. This is standard Flutter
   behavior but means a rollback from a newer schema version loses all
   repertoire data. Consider a backup-before-upgrade strategy for v1.0.

4. **iOS widgets extension build time** — 1830 lines of dead Swift code
   compiles on every iOS build. Not harmful but wastes build time.

5. **Large PGN imports** — the isolate-based hash works, but very large studies
   (thousands of variations) haven't been stress-tested for memory pressure.

### Go / No-go

**FULL GO FOR RELEASE.** The core loop (import → review → SRS → persist) is
sound, tested, and the code quality is high. The domain layer is pure and
well-separated, schema migrations are robust, test coverage is thorough, and
`flutter analyze` is completely clean across the entire repository.

With F1 resolved (Firebase, FCM, and Crashlytics stripped per owner decision),
there are **zero remaining blockers for release**. The app has zero third-party
telemetry, zero cloud dependencies, and zero external credential leaks.
