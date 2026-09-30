# Upstream sync + realign with lichess-org/mobile

## Principle (owner-set 2026-09-29)
Align with Lichess in CODE, differ in PRESENTATION. Deleting Lichess features
we don't want is fine and good. What must stop: drifting away by rewriting
Lichess-ready code (study, options layout, etc.) into fork-specific
reimplementations. The fork's distinct visual identity stays; the code under it
should track upstream wherever our product doesn't require a difference.

## Task 1 — Pull upstream updates
- Remote `upstream` = `https://github.com/lichess-org/mobile.git` (fetch+push
  already configured; note push URL points at Lichess — never push there).
- `git fetch upstream`, review delta since our graft point against the files we
  still share (study subsystem, settings screens, analysis, engine, widgets).
- Classify each upstream change: take / skip (= we deleted that feature) /
  take-later. Record the decision per subsystem, same style as CUT_PROPOSALS.md.

## Task 2 — Realign drifted code toward upstream
- Inventory fork-rewritten modules that upstream already covers, starting with:
  study scene + bottom bar (`lib/src/view/study/`, `lib/src/model/study/`),
  settings screens (`lib/src/view/settings/`), analysis screen chrome.
- For each: either revert to the upstream implementation with our visual tokens
  applied on top, or write down the product reason it must stay forked
  (then it becomes a spec entry, not silent drift).
- Presentation layer (`lib/src/design/`, tokens, SRS board background) is
  NOT in scope for realignment — that is the deliberate difference.

## Task 3 — Guardrails so we don't drift again
- New rule for spec docs: a forked reimplementation of an upstream-covered
  module needs a written product reason before code; otherwise reuse upstream.
- Relates to batch-2 item 2 (study scene): its option (a)/(b) decision must
  follow this principle — prefer upstream's study screen with our skin unless
  option (b) wins on product grounds stated in writing.
- Consider a periodic (e.g. monthly) upstream fetch + delta review task.
