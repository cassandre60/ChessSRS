# ChessSRS Developer & Operator Troubleshooting Guide

> **Authoritative Homes:** See [AGENTS.md §1](../AGENTS.md#1-authority-and-conflicts) for normative rules, [CLAUDE.md](../CLAUDE.md) for development setup, [TEST_STRATEGY.md](../TEST_STRATEGY.md) for verification budgets, and [GATES.md](../GATES.md) for gate definitions.

---

## 1. Compile Errors Inside `*.freezed.dart` or `*.g.dart` After `git pull` or in a Fresh Worktree

**Symptom:**
`fvm flutter analyze`, `fvm flutter test`, or `fvm flutter run` fails with missing getters, mismatched constructor parameters, or missing part files inside `*.freezed.dart` or `*.g.dart`.

**Root Cause:**
Generated build_runner outputs (`*.freezed.dart`, `*.g.dart`) are gitignored (`AGENTS.md §3.1`). Neither `flutter run` nor `flutter test` triggers code generation automatically. When `git pull` updates a Freezed/JSON model or when you create a new git worktree, the generated files are either stale or absent.

**Fix:**
```bash
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
```
Or launch the app via `./scripts/dev_run.sh -d linux`, which runs `pub get`, `build_runner`, and `flutter run` in sequence.

---

## 2. SQLite Schema Migration & Downgrade Archive Recovery

### 2.1 `DatabaseNewerVersionException` / Opening an Older Build Against a Newer Database

**Symptom:**
Launching an older branch or build against a database already upgraded by a newer schema version fails or triggers downgrade protection.

**How ChessSRS Handles It:**
`openAppDatabase` in `lib/src/db/database.dart` never deletes or wipes a database with a higher `user_version` on downgrade. Instead, it archives the newer database file to `<dbPath>.pre-downgrade.bak` (and any `-wal`/`-shm` sidecars) before opening or refusal so user study and SRS memory are never silently destroyed.

**Recovery Procedure:**
1. Check the database directory for `.pre-downgrade.bak` or `.bak` snapshots.
2. Verify snapshot integrity and schema version before restoring:
   ```bash
   sqlite3 chess_srs.db.bak "PRAGMA integrity_check; PRAGMA user_version; SELECT COUNT(*) FROM position_knowledge_state;"
   ```
3. Checkpoint any WAL file before copying:
   ```bash
   sqlite3 chess_srs.db "PRAGMA wal_checkpoint(TRUNCATE);"
   ```
4. Switch back to `main` (which carries the latest schema version) and restore the backup copy if needed.

### 2.2 Stranded `srs_review_state` Mirrors or Legacy `NULL` `canonicalStateId`

- **INV-005 & INV-069:** Every shipped schema upgrade preserves all rows and derived identities (`canonicalStateId`, orientation, `pgnHash`) and leaves no unreachable `srs_review_state` mirror.
- Remember that `RepertoireDecision.canonicalId` falls back to `canonicalStateId ?? id`. Cleanup queries against `position_knowledge_state` or `srs_review_state` must check **both** `d.canonicalStateId` and `d.id` (see `test/persistence/v23_repair_preserves_memory_test.dart`).

---

## 3. FVM Version Mismatches & Linux Desktop Build Failures

### 3.1 Wrong Flutter / Dart SDK Version

**Symptom:**
Analyzer reports unfamiliar lint warnings, SDK constraint errors in `pubspec.yaml`, or CMake incompatibilities.

**Fix:**
Always invoke Flutter and Dart via `fvm` so the version pinned in `.fvmrc` is used:
```bash
fvm install
fvm flutter --version
```
Never invoke bare `flutter` or `dart` if your system PATH points to a different SDK installation (such as a Snap package).

### 3.2 Linux Desktop Native Build Errors (`gtk+-3.0`, `sqlite3`, `mpv`, `ld.lld`)

**Symptom:**
`fvm flutter run -d linux` fails during CMake configuration or linking.

**Fix:**
Install the required Ubuntu/Debian native headers and libraries:
```bash
sudo apt-get update && sudo apt-get install -y \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libstdc++-12-dev \
  libsqlite3-dev libmpv-dev mpv
```

---

## 4. Diagnosing Local Gate Failures (`./scripts/gates.sh t1`)

Always run `./scripts/gates.sh t1` **after committing** on your branch (`G07` and `G08` inspect `origin/main...HEAD`, not uncommitted working-tree changes).

| Gate | Failure Message / Cause | How to Fix |
|---|---|---|
| **G03** (`banned_apis_check.py`) | Domain file imports `package:flutter`, `dart:io`, `sqflite`, or uses `DateTime.now()` in scheduling/review paths (`SPEC INV-040/041/042`). | Pass time via `Clock` (`lib/src/domain/clock.dart`) and keep all I/O and Flutter imports outside `lib/src/domain/`. |
| **G05** (`spec_trace_check.py`) | An invariant in `SPEC.md` has no citing test (`// SPEC INV-XXX.`), or a test cites a nonexistent `INV-XXX` ID. | Add the `// SPEC INV-XXX.` comment to the covering test file, or fix the typo in the cited ID. |
| **G07** (`protected_paths_check.py`) | The branch modifies a referee or contract file listed in `.gates/protected-paths.txt` without approval. | Revert the protected file edit on product/docs branches. Protected edits require a dedicated `gate-change` or `spec-change` PR and explicit per-item owner consent (`AGENTS.md §10`). |
| **G08** (`test_weakening_check.py`) | Removed test assertions (`expect(`), deleted test files, added test skips, or added analyzer ignore suppressions. | Restore the deleted assertion/test, or if the removal was explicitly requested by the owner, include an acknowledgement trailer on its own line in the commit message (`GATES.md`). |
| **G10** (`ratchet_check.py`) | Regressed a monotone metric in `.gates/ratchet-baseline.json` (`direct_dependencies`, `analyzer_suppressions`, `test_skips`, `test_declarations`, `domain_loc`). | Remove unnecessary suppressions/skips, restore test declarations, or keep `lib/src/domain/` within the LOC ceiling. |
| **G13** (`vendor_drift_check.py`) | Files under `scripts/autonomous/` diverged from their pinned manifest hashes. | Restore `scripts/autonomous/` to match `scripts/autonomous/upstream.json`. |

---

## 5. Widget Test Layout Overflows (`TestProviderScope`)

**Symptom:**
A widget test fails with `A RenderFlex overflowed by X pixels on the right/bottom`.

**Root Cause:**
Since PR #357 / Q10 (`docs/open-questions.md`), `test/test_provider_scope.dart` registers the app's real font families and `srsThemeData` and fails on any `RenderFlex` overflow (0 px threshold) rather than swallowing layout overflows.

**Fix:**
1. If the test builds its own bare `MaterialApp` without `srsThemeData` or a `Scaffold`/`Material` ancestor, Flutter falls back to 48 px monospace error text, causing artificial overflows. Wrap the widget under test using the shared helper in `test/test_provider_scope.dart` (or supply `theme: srsThemeData(brightness: Brightness.light).themeData` and a `Scaffold`).
2. If the overflow occurs inside a production widget at narrow viewport widths (e.g. 320 px phone width per `SPEC INV-062`), wrap flexible text labels in `Flexible` / `Expanded` with `TextOverflow.ellipsis` or switch to a scrollable layout.
