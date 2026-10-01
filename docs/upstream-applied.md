# Applied Upstream Commits

This ledger records upstream commits from `lichess-org/mobile` that have been cherry-picked, adapted, or manually applied into `chess-repertoire-srs`.

Because `HEAD` does not share a linear ancestor history with recent upstream commits (see `docs/upstream-audit-2026-09-30.md` §1), `git log HEAD..upstream/main` will list these commits even though their changes are already present in the codebase. Consult this ledger when performing diff audits to avoid re-investigating or double-applying changes.

---

## Applied Commits Ledger

| Upstream Commit | Upstream PR / Summary | Fork Commit / PR | Subsystem / Files | Notes |
|---|---|---|---|---|
| `a99dad8a1` / `214bb0353` | Send email login credentials in POST body, not query string (#3746) | `bcb66ad5b` (#94) | `lib/src/model/auth/auth_repository.dart` | Eliminates credential leakage into URL/proxy logs |
| `25cf0fae5` | Board editor accepts FENs describing illegal positions (#3733) | `a0d9ed580` (#98) | `lib/src/view/editor/editor_screen.dart` | Allows editing boards with illegal piece setups |
| `60309eb8d` | Route app links by exact host, not prefix match (#3730) | `0fad2d1e3` (#99) | `lib/src/model/common/service/app_links_service.dart` | Fixes routing of lichess deep links |
| `c60a0edd8` | Index openings.epd for per-position lookup (#3706) | `7f2a0c4e7` (#102) | `scripts/update_openings_db.py`, `lib/src/model/common/service/openings_service.dart` | Performance index for opening lookups |
| `498ce10a7` | Await openings database cleanup (#3702) | `02d91a23f` (#103) | `lib/src/model/common/service/openings_service.dart` | Prevents race condition during DB reset |
| `ed3dbea51` | Remove unrequired abiFilters in build.gradle.kts (#3750) | In-flight (upstream sync) | `android/app/build.gradle.kts` | Drops x86 from abiFilters as Flutter excludes x86 |
| `1a3a4dda8` | Cancel eval stream subscription of replaced eval request (#3718) | In-flight (upstream sync) | `lib/src/model/engine/evaluation_mixin.dart` | Cancels subscription on new eval request and on dispose |
| `e6be63d22` | Native Linux audio playback support (#3670) | In-flight (upstream sync) | `lib/src/model/common/service/sound_service.dart` | Linux audio playback using pw-play/paplay/aplay system backends |
