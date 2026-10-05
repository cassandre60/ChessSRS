# ChessSRS — Market Research & Positioning Brief

Date: 2026-10-02
Audience: the owner, and coding/design agents working on ChessSRS.
Basis: the repomix snapshot of the repo (`repomix-chesssrs-lean.xml`) plus a web research pass on competitors.

> **How to read this document.** Section 1 is grounded in the repo. Sections 2–3 are
> grounded in web sources, much of it vendor-written or store-listing text, and may be
> stale. Section 4 is a hypothesis, not a finding. Section 5 is a proposed work order,
> not a decision. Nothing here has been verified hands-on by running competitor apps.
> Treat competitor pricing and feature claims as unverified until checked (see §9).

---

## 0. TL;DR

- Spaced repetition for openings is table stakes. FSRS is no longer rare either (ChessAtlas,
  FlexiChess, En Croissant all use it). **The algorithm is not the pitch.**
- The openings in the market are mostly **capped, subscription-gated, web-only, or
  single-platform.** A free, uncapped, offline, account-free, native-mobile trainer with a
  Lichess-grade board looks under-served, but this needs a hands-on check (§9).
- Working positioning hypothesis:
  **"Your Lichess studies and PGNs, drilled offline on your phone. Free. No account. No caps."**
- Biggest adoption risk: **cold start.** ChessSRS has no repertoire builder, so it only serves
  people who already have studies or PGNs.
- Highest-leverage features, in order:
  1. Refresh a Lichess study in place, keeping SRS progress.
  2. Deviation detection from the user's real games (no engine needed).
  3. Portable state: backup/export first, optional sync later.
- Monetization: a free core is itself a differentiator. If anything is ever charged for, charge
  for the part with real marginal cost (cloud sync). GitHub Sponsors is a tip jar, not a plan.

---

## 1. What ChessSRS is today (from the repo)

Sources: `PRODUCT.md`, `MVP.md`, `README.md`, `docs/*`, `lib/src/**`. Statements about
*intended* behavior come from docs; I did not run the app.

**Product definition.** A local-first chess repertoire trainer built as a fork of Lichess Mobile
(GPL-3.0). Core premise: show a position from the user's own repertoire and ask them to play
what they learned. The review loop is 100% local with no network on the training path.

**Implemented or evidenced in code/tests:**
- PGN import with variations, comments, NAGs, custom FENs; multi-chapter studies. Import chooser
  covers PGN file, pasted PGN text, and a Lichess study (URL or 8-char id parsed by
  `lichess_study_importer.dart`).
- PGN export, with orientation and opening classification surviving export → re-import
  (`pgn_exporter_test.dart`).
- Chess-tuned binary FSRS scheduler (`chess_fsrs_scheduler.dart`, decision D015: ratings
  collapse to again/good because thinking time in chess is calculation, not weak memory).
  A replaceable scheduler contract also exists.
- Graph-aware review (`graph_aware_review_coordinator.dart`) and canonical position identity:
  a position's memory is keyed by its complete accepted-move set, so divergent imports merge
  into one question with several accepted answers (`docs/game-import-and-quality-gate.md`).
- Only the repertoire side's moves become questions; opponent moves and already-learned moves
  auto-traverse until the next due decision.
- Move comments are hidden during recall and revealed after the move.
- Wrong move → non-modal feedback with an on-board arrow, immediate re-guess.
- Duplicate-import detection by PGN hash (`review_service.dart`, `importPgnText`).
- Settings screen: daily limit, target retention, scheduling algorithm, ease/interval scaling,
  notation/arrows/notes toggles, diagnostics HUD, theme/accent, board and pieces, sound,
  engine toggle, local DB size, logs.

**Documented in `PRODUCT.md` as intended; verify they exist in the shipped UI before marketing them:**
- Pre-match **Rehearsal / Cram mode** that is non-destructive (does not touch SRS intervals or lapses).
- **Active/inactive study** toggling so the daily queue only draws from active repertoires.
- **Opening Hubs**: virtual scopes that aggregate lines across studies by ECO/opening name.

**Known gaps / constraints stated in the repo:**
- No repertoire editor (explicitly out of scope; `docs/roadmap.md` lists study editing as "possible later").
- Cloud sync and accounts excluded from MVP (Phase 4 in the roadmap).
- Engine support is Android/iOS only; desktop has none (`docs/game-import-and-quality-gate.md`).
- Engine evals are not persisted on nodes (same doc), so any "analyze on import" feature needs a
  persistence decision first.
- Deep-link records (`assetlinks.json`, apple-app-site-association) still reference the upstream
  Lichess identity (item "M20", an operations task, not code).
- `README.md` still says "Foundation phase".
- Firebase is retained (D017) and the project depends on Lichess Mobile's foundation.

---

## 2. Competitor landscape

Confidence tags: **[store]** = app store/official listing, **[vendor]** = written by a
competing vendor or affiliate (biased, possibly stale), **[forum]** = user posts, **[repo]** = repo page.

| Tool | Type / platforms | SRS | Pricing / limits (as found) | Notable |
|---|---|---|---|---|
| **Chessable** (as far as I know part of the Chess.com family) | Course marketplace + MoveTrainer; web, iOS, Android | MoveTrainer; one comparison page says SM2-based [vendor] | Courses roughly $10–60+ each [vendor]; PRO adds 300+ short courses and offline mode [store] | Strongest content library. Users can build private courses from PGN, though one forum post calls the import and authoring workflow a pain [forum] |
| **Chess.com** | Platform | Spaced-repetition courses inside the platform [vendor] | Freemium | Opening pages, lessons, practice. Broad ecosystem |
| **Lichess** | Research/studies; web, iOS, Android | No built-in opening SRS in most sources [vendor]; one page claims otherwise (see §9) | Free, open source | Best free explorer and Studies. Users on the forum ask for built-in opening training |
| **Chessbook** | Builder + trainer; iOS, web | Yes | Free users: 400 moves; Pro $7.99/mo or $79.99/yr [store]. Other sources cite 200 moves (older) and "$7/mo billed annually" | Gap finding, transposition handling, online-game review against your repertoire, PGN export, Lichess integration |
| **ChessAtlas** | Builder + trainer; web only, native app on their roadmap | FSRS | Free: 200 variations, 2 linked accounts. Premium $9.99/mo or $6.99/mo annual; game import and deviation detection are Premium [vendor, their own page] | Positions itself against the exact gaps in this brief |
| **Chess Tempo** | Web | Yes | Not verified | Trainer integrated with online play that shows where you deviated [vendor/page, possibly old]; a forum comment says free users get advanced SRS settings |
| **FlexiChess** | Web suite | FSRS | Free tier; $14/mo or $109/yr [listing] | 10.4M-game database, engine, opponent scouting, AI coach |
| **Chess Prep Pro** | iOS/Android | "Smart Train" is Premium | Premium for SRS, backup and sync, unlimited downloads [vendor] | Imports Lichess studies |
| **Listudy** | Web; free, open source (AGPL-3.0) | Yes | Free | PGN or Lichess-study based. Forum users note: no app, and updating a study means delete and re-import |
| **Chessdriller** | Web, open source | Yes | Free | Requires a Lichess login; repertoire stored as Lichess studies |
| **openings.gg** | Web | Yes | Free: unlimited imports/PGN/training per its forum post | Lichess OAuth study import, explorer, local Stockfish in browser |
| **En Croissant** | Desktop | FSRS | Free, open source | Repertoire practice mode; one forum user reported a practice-mode crash |
| **ChessMovio** | Mac + iOS | Yes | Free + IAP, markets "no subscription" [store] | PGN import, auto opponent moves, offline, iCloud sync. **Closest in philosophy; Apple-only** |
| **RepertoireLab** | Android | Yes | Not verified | Repertoire on-device, Lichess game analysis, deviation detection [store] |
| **ChessLines** | iOS (iPad-designed) | Yes | Free + IAP | "Data not collected" privacy label [store] |
| **Chess Opener (Lite/PRO)** | iOS (iPad-designed) | Not described as SRS | Lite free, PRO $8.99 | Offline, random opponent moves from your repertoire |
| **Chess Position Trainer** | Windows desktop | Yes | ~$40 full version per an old forum post | Long-standing desktop standard |
| **ZackMurry/chessrs** | Self-hosted web (Docker/NGINX/k8s) | Configurable | Free, GPL-3.0 | 4 stars, README lists Lichess game import and engine analysis. Hobby project; not real competition |
| Others seen once, not examined | Chessreps, ChessMood, Chessmate, Noctie.ai ($15/mo per a competitor page), SCID, Lucas Chess, a Lichess-blog repertoire builder in alpha | — | — | Worth a look before positioning copy is final |

### What the paid tools lead with (competitor marketing, i.e. what users are being taught to want)
1. A repertoire **builder** with gap finding.
2. **Game import and deviation detection** against your real games.
3. Modern scheduler (FSRS) and fewer reviews.
4. Sync across devices.
5. Curated content.

---

## 3. What is NOT a differentiator

- Spaced repetition per se.
- FSRS per se (several competitors advertise it).
- Transposition/merge handling (Chessbook, ChessAtlas advertise it; ChessSRS's canonical identity is
  good engineering, but users will not choose an app for it).
- Lichess-quality board. Valuable, but a table-stakes expectation for anyone coming from Lichess.
- Local-first/offline alone. ChessMovio, Chess Opener, ChessLines, RepertoireLab also claim local or offline use.

Things that may be differentiating but I did **not** see in any competitor listing (could exist
unlisted): non-destructive pre-match rehearsal mode; "comments hidden during recall, shown after";
multi-answer positions as first-class. Confirm they work well before leaning on them.

---

## 4. Positioning hypothesis (to test, not assume)

**The gap, as observed:** among tools found, the best ones are capped, subscription-gated,
web-only, desktop-only, or Apple-only. No single tool surfaced that is simultaneously
free, uncapped, offline, account-free, native on mobile, and built on a Lichess-grade board.
Nearest Android competitor to check: RepertoireLab. Nearest on Apple: ChessMovio.

**Candidate one-liner:** *Your Lichess studies and PGNs, drilled offline on your phone. Free. No account. No caps.*

**Target user:** players who already author or receive repertoire material (Lichess Studies, coach
PGNs, ChessBase exports) and are tired of caps, subscriptions, or web-only trainers.

**Honest risks:**
1. **Cold start.** No builder means no repertoire for people who don't have one. Competitors with
   builders, gap finding, and game-based repertoire generation serve a wider audience.
2. **Discoverability.** The name is nearly identical to ZackMurry's "ChesSRS" and is hard to search.
3. **"Free" is not a moat.** Others can go free. The durable edge is the combination (offline +
   native + no account + no caps + good board), plus any workflow feature that closes a real pain.
4. **Lichess could add SRS.** Forum threads request it. If it ships, the Lichess-adjacent
   workflow value shrinks. Features that stay valuable regardless: offline, deviation detection, portability.

---

## 5. Proposed work order

Each item lists the **verify-first** step, because several depend on facts I could not confirm from the snapshot.
If adopted, authoritative docs need updating in their hierarchy order (per `docs/game-import-and-quality-gate.md`:
`MVP.md`, `QUALITY.md`, `IMPLEMENTATION_PLAN.md`).

### WI-1: Refresh a Lichess study in place, keeping progress
**Why:** the pain point is documented for Listudy (delete and re-import to update). Lichess Studies are
living documents, so this fits the target user's workflow exactly.

**Current behavior (from `review_service.dart`):** `importPgnText` hashes the PGN. An identical hash
switches to the existing study; a title match only counts when the hash also matches. An edited study has a new
hash, so it imports as a **new study** and leaves the old one to delete.

**Verify first:**
- Does the canonical-state design already carry SRS state for unchanged positions across studies? Inspect
  `canonical_rekey_migration.dart` and its tests, and `sqlite_study_repository_test.dart`.
- Does `Study` persist its Lichess study id and host? If not, add it.

**Design sketch:** a "Refresh from Lichess" action on a study that re-fetches by stored id, imports, matches positions by
canonical id, and shows a summary (new / changed / removed). Decide explicitly what happens to removed positions
(archive vs delete) and to a changed answer (new accepted-move set means a new canonical state).

**Acceptance:** edit a study on Lichess (add a line, change an answer), refresh; no duplicate study appears;
unchanged positions keep stability and due date; new positions are due; the summary is accurate; review
still works offline afterward.

### WI-2: Deviation detection from the user's real games (no engine)
**Why:** this is what the paid tools lead with, and it needs no engine: compare the game's moves to the repertoire tree.

**Behavior:**
- For each game where the user played side S, walk the moves along the repertoire tree for S.
- If the user played a move **not** in the accepted set at a decision position → queue that position for review ("you left prep here").
- If the **opponent** left the tree → report "out of book at move N" (report only, since there is no editor; optionally link to the position on Lichess analysis).

**Open questions for the owner / verify first:**
- Lichess public game export: check the current API docs for auth and rate limits (my understanding is public games need no token, **unverified**).
- Network scope: this is the first feature that needs the network outside importing. Keep the review path offline
  (existing invariant in `QUALITY.md`/`PRODUCT.md`); make the fetch an explicit user action with only a username as input.
- The existing proposal (`docs/game-import-and-quality-gate.md`) bundles *importing games as repertoire content* with an *engine quality
  gate*. That gate is phone-only, costly on large imports, and blocked by unpersisted evals. Treat deviation detection
  as a separate, much smaller feature and decide on the engine gate independently.
- Chess.com support later via its public API (verify terms).

**Acceptance:** given a username and N recent games, the app lists each deviation with the game, move number, and the
repertoire's expected move, adds the position to the review queue, and works with no engine.

### WI-3: Portable state
**Why:** removes the "my progress is trapped on one phone" objection without accounts.
**Step 1:** export/import of studies + SRS state as a file (extends the existing PGN export, which carries no SRS history).
**Step 2 (optional, later):** async sync per roadmap Phase 4; this is the natural candidate for a paid tier because it has real server cost.

### WI-4: Cold-start path (no editor)
**Why:** people without a repertoire cannot use the app.
**Options, cheapest first:** an onboarding screen explaining how to get a repertoire from Lichess Studies or a coach PGN; a short curated
list of public Lichess study links. **Check licence/permission before bundling or scraping any content**, including Listudy's.
A line editor remains out of scope unless the owner reverses that decision.

### WI-5: Messaging and store presence
- Store listing and README built around the one-liner in §4, with screenshots of the review loop, import chooser, and rehearsal mode (once verified).
- Replace "Foundation phase" in `README.md`.
- Decide on the name collision.

### Explicit non-goals (keep, per `PRODUCT.md` / `docs/roadmap.md`)
Tactics generator, social/leaderboards, XP/streak gamification, engine-defined correctness, line editor, courses/content marketplace.

---

## 6. Monetization

- Market norm found: roughly $7–15 per month, or ~$50–110 per year, with free tiers capped by moves/variations
  (Chessbook 400 moves; ChessAtlas 200 variations) or by feature (game import, sync).
- Your marginal cost per user is near zero for local training, so **free and uncapped is credible and is itself a differentiator.**
- **GitHub Sponsors:** reasonable as a low-friction tip jar (single link in About; no nagging). In my judgment it will not fund
  much on its own; this is an opinion, not data.
- If charging is ever considered, charge for what costs money to run (cloud sync/backup), and keep drilling, import, export,
  and deviation detection free.
- Alternatives to evaluate: one-time optional "supporter" purchase; donations via Ko-fi/Open Collective.

---

## 7. Pre-ship checklist (non-feature)

- **Licensing:** the app is a fork of Lichess Mobile under GPL-3.0. There is a long-running debate about GPL and Apple's App Store terms.
  Lichess's own app is distributed by its copyright holders, which differs from a third-party fork. Get a proper legal check before iOS distribution.
  Also keep the stated posture on Listudy (AGPL, behavioral reference only) and chessrs (GPL-3.0) consistent with `docs/INTEGRATION_MAP.md`.
- **Deep links (M20):** publish updated `assetlinks.json` / apple-app-site-association for the app's own identity if link hand-off is wanted.
- **Firebase (D017):** confirm the project, data handling, and privacy label match the "no account, local-first" promise before claiming it publicly.
- **Name:** collides with ZackMurry/chessrs ("ChesSRS") and is hard to search.
- **README/store copy:** align with §4 and remove stale status text.

---

## 8. Owner decisions needed

1. Final positioning statement and target user (§4).
2. Whether the network may be used for an optional, user-initiated game fetch (WI-2).
3. Whether to split deviation detection from the engine quality gate (WI-2).
4. Monetization stance: fully free + tip jar, or free core + paid sync (§6).
5. iOS distribution given GPL (§7).
6. Whether a minimal editor stays permanently out of scope (§5 WI-4, §4 risk 1).

---

## 9. Data confidence and what to verify

**Verify before quoting competitors publicly or building on these assumptions:**
- Hands-on test of the nearest competitors against the §4 gap claim: RepertoireLab (Android), ChessMovio (Apple), Chess Prep Pro, Chessbook free tier, Chessable free tier and private-course import.
- Chessbook's free-tier cap and pricing vary by source (100 per side / 200 / 400 moves; $7 vs $7.99 monthly). The App Store listing says 400 and $7.99/$79.99.
- ChessAtlas, FlexiChess, and several "best of 2026" roundups are vendor-authored; their comparisons are marketing.
- Chess Tempo's page was an old snapshot; its current state and pricing are unverified.
- **Conflict:** one comparison page says Lichess's MoveTrainer uses spaced repetition; other sources and my understanding say Lichess has no built-in opening SRS. Check Lichess directly.
- Lichess game-export auth/rate limits (WI-2).
- Whether Rehearsal mode, active/inactive toggling, and Opening Hubs are actually in the shipped UI (§1).
- Chessable's corporate relationship to Chess.com is from my own background knowledge, not from a source read here.

**Not covered:** Chessreps, ChessMood, Chessmate, Noctie.ai, SCID, Lucas Chess, and the Lichess-blog repertoire builder were only seen in passing.

---

## 10. Sources (retrieved 2026-10-02)

- Chessbook App Store listing: https://apps.apple.com/app/id6466343415
- Chessbook pricing note: https://simplycodes.com/store/chessbook.com
- Chessbook review (free-tier cap): https://mattplayschess.substack.com/p/chessbook-a-game-changer-for-adult
- Chessbook interview: https://saychess.substack.com/p/an-interview-with-marcus-buffett
- ChessAtlas buyer's guide (vendor): https://chessatlas.net/blog/tool-comparisons/what-to-look-for-in-a-chess-opening-trainer-2026-buyers-guide
- ChessAtlas 7-tool comparison (vendor): https://chessatlas.net/blog/tool-comparisons/best-chess-opening-trainers-2026-honest-comparison-of-7-tools
- Opening trainers roundup: https://darksquares.net/blog/chess-training-apps/best-chess-opening-trainers-2026-compared
- Chessmate roundup: https://www.trychessmate.com/blog/best-chess-opening-trainer-apps-2026
- Opening trainer comparison (Chessable/ChessMood/Listudy): https://www.raindropchess.com/the-best-opening-trainer-apps-chessable-vs-chessmood-vs-listudy/
- Chessiverse comparison pages: https://chessiverse.com/compare/best-app-for-practicing-chess-openings and https://chessiverse.com/compare/chess-opening-practice-tools-compared
- Chessable App Store listing mirror: https://apps.appfollow.io/ios/chessable-study-chess-smarter/1523279049?country=gb
- Chessable authoring/import discussion: https://lichess.org/ublog/OEPayaq2/discuss
- Chess Tempo trainer page: https://chesstempo.com/opening-training/
- FlexiChess: https://alternativeto.net/software/flexichess/about/
- Chess Prep Pro: https://chesspreppro.com/
- Listudy: https://listudy.org/ and https://alternativeto.net/software/listudy/about/
- Lichess forum, Listudy request thread: https://lichess.org/forum/redirect/post/S3n4bFBg
- Chessdriller: https://github.com/gtim/chessdriller
- openings.gg thread: https://lichess.org/forum/general-chess-discussion/spaced-repetition-for-lichess-studies-a-free-tool-i-made
- En Croissant docs mirror: https://www.mintlify.com/franciscoBSalgueiro/en-croissant/features/repertoire-training
- En Croissant bug report: https://lichess.org/forum/redirect/post/DObURC9i
- ChessMovio: https://apps.apple.com/qa/app/id6757606915
- RepertoireLab: https://play.google.com/store/apps/details?id=com.anonymous.repertoirelab&hl=en_US
- ChessLines: https://apps.apple.com/us/app/chesslines/id1617560548
- Chess Opener: https://apps.apple.com/app/id1489282483
- ZackMurry/chessrs: https://github.com/ZackMurry/chessrs
- Lichess forum, request for opening SRS: https://lichess.org/forum/lichess-feedback/puzzle-improvements-for-a-better-learning-experience
