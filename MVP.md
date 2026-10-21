# Current Beta Scope

Authority: included and deferred capabilities. `PRODUCT.md` owns intent;
`SPEC.md` owns exact acceptance behavior; `IMPLEMENTATION_PLAN.md` owns
delivery status and evidence. This is the evolved beta, not the original
Phase 2-only scope. See `docs/documentation-map.md`.

## 1. Goal

Deliver and refine the local-first loop:
**PGN import → normalized repertoire tree → active recall → durable local SRS**.
The owner is the beta tester. The technical foundation is Lichess Mobile;
the visual identity is Diagram (`design/README.md`).

## 2. Included capabilities

| Capability | Scope / contract |
|---|---|
| PGN import | Local file/text, multi-game chapters, RAVs, comments, NAGs, custom FENs; structured quarantine (INV-010/011/012) |
| Lichess study import | URL/ID import and bulk owned-study import; optional Lichess sign-in for protected sources; local snapshots, not live synchronization |
| Repertoire normalization | Study → Chapter → branching tree → player decisions; per-chapter orientation and shared position memory (INV-013/015/016/017) |
| Active review | Interactive board, repertoire grading, configurable transposition acceptance, non-blocking lapse/reguess/re-test (INV-020/021/033/065) |
| Traversal and presentation | Due-aware opponent replies, due-only/full-line continuity; Due date/By line/Random order (INV-022/066) |
| Review scopes | Active pool, side, study, chapter and cross-study opening hubs (INV-030) |
| SRS | Three selectable schedulers behind Scheduler; exact math in the scheduling architecture; fresh introduction and daily caps (INV-024–029/031/068) |
| Practice | Non-destructive rehearsal (INV-023) |
| Local persistence and PGN export | Incremental durable answers and study/chapter export; PGN export does not back up SRS history (INV-001/002/014) |
| Review UX/settings | Diagram surfaces, quiet feedback, spoiler-free annotations, board/piece/sound and SRS controls (INV-060–063) |
| Explore/analysis tools | Retained inherited tools; optional network/engine assistance outside local review; cuts governed by CUT_PROPOSALS |

## 3. Deferred / excluded

- Full-library backup **and restore of SRS history**: P-EXPORT-ALL; needs a
  persisted-format decision. Current PGN export is not that feature.
- Cross-device content/history sync and an owned cloud/account backend: P-SYNC.
  Optional existing Lichess authentication is included; mandatory accounts are not.
- Automatic synchronization of imported studies with remote edits.
- Advisory import health check: future optional work, never a prerequisite.
- Scheduling proposals such as tournament mode, fitted personal weights,
  confusion-registry interleaving and prerequisite priors: not current scope.
- Tactics training, multiplayer, social feeds/leaderboards, gamification and
  dashboards unrelated to repertoire recall (PRODUCT §6).

## 4. Acceptance and verification

The exact contracts are in SPEC, not restated here. Clean import, durable
memory, bounded latency and non-modal review remain required. Fresh material
is introduced after due work, not counted as already due (INV-068). Runtime
acceptance follows `TEST_STRATEGY.md`; a green suite alone is not a visual or
real-device pass.

## 5. Limitations

Repertoires are local snapshots. Mobile email-code sign-in still needs real-device
confirmation (F-MOBILELOGIN in IMPLEMENTATION_PLAN). Supported release artifacts
and platform limitations live in `docs/releases.md`.
