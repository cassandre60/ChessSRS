# Architecture and Product Decisions

This file records decisions that should not be silently reversed during implementation.

## D001 — Review is the primary application

Decision: The app is Review-first. There is no conventional dashboard/product hierarchy.

Reason: The product's value is active repertoire recall, not study management.

Implication: Studies/openings are lightweight selectors that constrain Review.

## D002 — Local-first Review

Decision: The critical Review loop never requires the network.

Reason: The user must be able to play at thought speed and offline.

Implication: Local chess validation, repertoire lookup, and SRS updates happen locally.

## D003 — PGN is an input format, not the domain model

Decision: Normalize PGN into Study/Chapter/PositionNode/RepertoireDecision structures.

Reason: Future Lichess import and other sources must converge on one model.

## D004 — Study and opening are different concepts

Decision: A Study is a source/content container. An Opening is a cross-study classification/filter.

Reason: Users may want to review one opening across many studies.

## D005 — Engine is advisory, not the Review judge

Decision: Review correctness is repertoire-based.

Reason: The purpose is remembering the user's preparation, including how to punish opponent mistakes.

## D006 — One-time import analysis may warn about user-side aberrations

Decision: A future import-time engine pass may identify severe user-side evaluation collapses.

Rules: warn only; never block import; do not treat opponent inaccuracies as repertoire defects.

## D007 — Learned does not mean forgotten forever

Decision: Auto-traversed/non-due decisions remain scheduled and can become due again after long intervals.

Reason: Long-term retention requires eventual retrieval practice.

## D008 — No mandatory session completion

Decision: Review has no end-of-session page.

Reason: Artificial session boundaries add product weight without improving the core interaction.

## D009 — Future sync covers both studies and SRS state

Decision: Cloud synchronization should eventually cover both repertoire content and review state.

Reason: Both are small enough and both are required for a coherent cross-device experience.

## D010 — Reference repositories

Decision: Use `ZackMurry/chessrs` and `ArneVogel/listudy` as explicit implementation references.

Links:

- https://github.com/ZackMurry/chessrs
- https://github.com/ArneVogel/listudy

Reason: They provide relevant prior art for chess SRS and study/tree training behaviour.

## D011 — No premature feature expansion

Decision: New features need a product justification tied to repertoire retention/review.

Reason: The product's differentiation depends on focus and speed.

## D012 — Architectural reset to the Lichess Mobile foundation

Decision: The application is rebuilt as a fork of `lichess-org/mobile`
(GPL-3.0). The previous standalone implementation is archived at git tag
`legacy/pre-reset` and is reference material only.

Reason: The old implementation's UI/UX quality could not reach the product's
Lichess-standard requirements without reinventing what Lichess Mobile already
provides (board, theme, navigation, settings, persistence patterns).

Implication: Domain contracts are specified by the Markdown documents and
reimplemented cleanly inside the Lichess architecture. Old code is never
resurrected because class names look familiar.

## D013 — dartchess is the single chess representation

Decision: Use dartchess (the chess library of the Lichess ecosystem) for all
rules, FEN, SAN, UCI, and PGN parsing. chessground renders boards.

Reason: QUALITY.md forbids duplicated chess logic; the old `package:chess`
adapter is obsolete in the new foundation.

## D014 — Listudy behavior only, never code (AGPL)

Decision: Listudy (AGPL-3.0) serves as behavioral reference only. chessrs
(GPL-3.0) permits attributed adaptation, but reimplementation is preferred.

Reason: License incompatibility with our GPL-3.0 fork for direct AGPL reuse.

Links:

- `docs/INTEGRATION_MAP.md`
- `CUT_PROPOSALS.md`

## D015 — Pure Binary FSRS over Latency Grading

Decision: Grade move recall strictly as binary Pass/Fail (`Rating.good` vs `Rating.again`), completely excluding response latency from interval calculations.

Reason: Chess recall is fundamentally different from vocabulary flashcards. In chess, stopping to verify candidate moves, calculate tactical variations, and check piece safety is disciplined play. Penalizing thinking time builds toxic habits (reflexive blitzing, clock panic) and penalizes deep verification. FSRS maintains its full mathematical predictive power in binary mode ($R = (1 + F \cdot t/S)^C$, $R_{\text{target}}$ solving), while keeping move input 100% natural chess without clock anxiety.

Rules:
1. `Rating.good`: First committed move on the board is correct, regardless of thinking duration.
2. `Rating.again`: Incorrect move, hint used, or a corrected false-start attempt.
3. Latency is demoted from a scheduling input to an optional analytics metric (`latencyEmaMs`), strictly firewalled from interval computation.

## D016 — Visual identity is independent of Lichess Mobile

Decision: ChessSRS's visual identity ("Diagram") is designed and specified
independently of Lichess Mobile's theme, per the design package in `design/`.
Lichess Mobile remains the technical foundation only: chess board rendering
(chessground), chess rules (dartchess), and the underlying Flutter/Riverpod
architecture are kept; the Material-themed widget layer, Lichess board/piece/
sound assets, Lichess iconography, and Lichess component conventions are
replaced.

Date: 2026-09-22

Context: D012 chose to fork Lichess Mobile for its technical foundation
(chessground, dartchess, the Riverpod architecture, board rendering).
PRODUCT.md's original "Lichess Professional Polish" section also mandated
inheriting Lichess's visual theme (colours, typography, component style). Ship
review and outside research concluded that this made ChessSRS visually
indistinguishable from a trimmed Lichess Mobile, which undermines the
product's goal of being recognised as its own product.

Consequences: `lib/src/styles/` and the Material-based widgets in
`lib/src/widgets/` are no longer preserved as-is (supersedes the "NOT cut"
note in `CUT_PROPOSALS.md` for those two paths specifically — see the
amendment there). New screens use the primitives and tokens in the design
package instead of `material_ui`/`cupertino_ui` components. This is a
presentation-layer change only; it does not affect scheduling, persistence,
import, or any domain logic.

## D017 — Keep Firebase, pointed at Lichess, until reminders are actually built

Decision: keep Firebase and notifications (C1, C2 in `CUT_PROPOSALS.md`). Do not
strip them, and do not create a new Firebase project yet. `lib/firebase_options.dart`
stays pointed at `lichessv2` / `org.lichess.mobileV2`.

Date: 2026-09-29

Context: C1 and C2 sat `[G]` GREY — undecided — through the whole audit, and the
audit flagged the Firebase project as an open item. The owner's test for deciding
was whether notifications need it, and they do: the FCM path starts at launch
(`lib/src/app.dart:123`) and registers a device token, so removing Firebase would
remove a live capability.

But "notifications need Firebase" and "Firebase is correctly configured for
ChessSRS" are two different claims, and only the first is true. What the plumbing
delivers today is **Lichess's** push, registered against Lichess's backend:

```dart
// lib/src/model/notifications/notification_service.dart:475
client.post(Uri(path: '/mobile/register/firebase/$token'))
```

The SRS review reminders that C2 was written for — "like Anki", the reason anyone
would want notifications in a local-first trainer — were never built. No
`zonedSchedule`, no topic subscription, nothing that schedules anything.

Consequences:

- FCM device tokens register on Lichess's backend, and Crashlytics non-fatals
  (including sign-in failures, `lib/src/model/auth/sign_in_failure_reporter.dart`)
  reach Lichess's console. Accepted knowingly for now, since the fork is not
  distributed and both destinations are Lichess's own infrastructure.
- The account menu being unreachable (fixed in PR #84) meant no user could sign in,
  and `_registerToken` returns early without a signed-in user (`:471`) — so
  notifications were fully unreachable too, not just study import. Worth knowing
  when weighing how serious that bug was.
- `lib/firebase_options.dart` is generated, so switching projects is a
  console-and-regenerate task, never a hand edit. Recorded so nobody attempts the
  edit.

Revisit when: a daily review reminder is actually built. That feature needs a
backend we own, and at that point owning the Firebase project stops being
optional rather than merely preferable.
