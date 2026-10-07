# Domain Logic Audit Plan — Task 017

Scope: `lib/src/domain/`, `lib/src/review/`, `lib/src/persistence/`, `lib/src/import/`.
Baseline: `flutter test test/review/review_engine_test.dart test/persistence/canonical_rekey_migration_test.dart` green (29/29) after `build_runner` in this worktree. Full suite authority is CI.

- [x] 1. Daily quota day-boundary mixes UTC and local time (`getTodayReviewedPositionsCount` uses `DateTime.utc(y,m,d)` while events store local `toIso8601String`; exact-midnight local event compares smaller than UTC start and is excluded)
- [x] 2. `ReviewSession.retryMove` creates fallback `ReviewState.initial(decisionId: decision.id)` instead of canonicalId, diverging from `submitMove` which uses canonicalId
- [ ] 3. Incorrect-answer re-queue removes only by occurrence `id`, leaving a transposed duplicate (same canonicalId, different id) in queue so one position is asked twice
- [ ] 4. SRS queue dedupes transpositions only for global scope; single-study / chapter / opening scopes queue the same canonical position twice
- [ ] 5. `_canonicalByFenMove` (session) and `InMemoryReviewStateRepository` collide when two different questions share one FEN + one move but have different accepted sets; lookup prefers the map over the passed `decisionId` and can return the wrong canonical
- [ ] 6. `computePgnHash` / `computeRepertoireTreeHash` write `san` directly; a null SAN hashes as the literal string "null" and collides across unrelated trees (should fall back to UCI)
- [ ] 7. `chapterToPgn` trusts stored `move.san` (writes literal "null" when missing) and crashes on corrupt `startingFen` via unguarded `Setup.parseFen` (should recompute SAN from position + handle bad FEN)
- [ ] 8. Opening scope matching is inconsistent: `startSession` uses exact `c.opening == openingFamily` while `getDueSummary` trims both sides (whitespace-only difference hides a scope)
- [ ] 9. `getDueReviewStates` queries only legacy `srs_review_state` and ignores `position_knowledge_state`, so it under-reports due items (currently unused, but part of the repository contract)
- [ ] 10. `rekeyCanonicalReviewState` rewrites `position_knowledge_state` + `srs_decision` but leaves orphaned canonical rows in `srs_review_state` under old keys (dead weight; `getDueReviewStates` would surface them as due)
- [ ] 11. Graph exposure throttle `_isSameCalendarDay` compares calendar fields without normalizing `isUtc`, so the same instant in UTC vs local counts as different days (inconsistent with local-midnight daily quota)
- [ ] 12. Targeted verification: run affected test files + `flutter analyze` on touched files per change; full suite left to CI per AGENTS.md §4
