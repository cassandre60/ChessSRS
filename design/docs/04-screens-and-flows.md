# 04. Screens, state machine, interaction, accessibility

## 1. Screens

| Screen | Prototype control | Notes |
|---|---|---|
| Review | `Recall` / `Correction` / `Note` | The product. See §2 for the state machine. |
| Nothing due | `Nothing due` | Reached automatically when due count hits 0 outside Practice. |
| Scope list | `Scope` | Sheet/popover over Review. |
| Library | `Library` | Sheet/popover over Review. |
| First launch / Import | `First launch` | Shown when there is no data yet, and reused as the Import sheet body later. |
| Settings | `Settings` | Full screen, reached from Library. |

No other top-level screens exist in this design. Analysis/Explorer/Editor are reachable only via Library →
Explore, pending the open decision in `00-agent-brief.md`.

## 2. Review state machine

States: **prompt → (correct) → quiet → prompt** *or* **prompt → (correct, has note) → note → prompt**;
**prompt → (incorrect) → correction → (plays correct move) → correct path**.
`due == 0` (outside Practice) transitions to **Nothing due** instead of back to prompt.

```mermaid
stateDiagram-v2
  [*] --> prompt
  prompt --> quiet: correct move, no note
  prompt --> note: correct move, has note
  prompt --> correction: wrong move
  correction --> quiet: plays the correct move (no note)
  correction --> note: plays the correct move (has note)
  quiet --> prompt: due > 0, after 560ms
  quiet --> nothingDue: due == 0 and not Practice
  note --> prompt: Continue tapped / Space
```

- **prompt:** board is live for the user's side. Notation line shows the dashed blank. Skip is visible.
- **correction:** triggered by any move that is not the repertoire move (including "no legal repertoire move
  matches"). Draw the arrow from the repertoire move's from/to. Fill the slot with the Answer view. The board
  **stays interactive** — the user should still be able to try again or Skip. **Do not decrement due** and do
  **not** advance until the correct move is actually played (or Skip is used — see §3).
- **quiet:** a 560 ms pause after a correct answer that has no note, before returning to `prompt` (or to
  Nothing Due). This exists so a bare-correct move doesn't feel like it vanished instantly; it is not a
  celebration and has no visual content beyond the piece having moved.
- **note:** shown after a correct answer when the position has a comment and "Show notes after a move" is on.
  Persists until the user taps Continue (or presses Space). The opponent's reply (if any) plays when the user
  continues, not before.
- Skip's behaviour depends on state (§3).
- Due count decrements by 1 on each correct answer (not in Practice mode). Practice mode never changes the due
  count or the schedule; it shows `Practice` in the top bar instead of a number.

## 3. Skip

- In **prompt**: reveal the correct move as if the user got it wrong (goes to `correction`), matching "Skip"
  meaning "show me the answer" rather than "silently pass". This is what the prototype does (`skip()` calls
  the wrong-move path when in prompt). Confirm this matches the product's actual FSRS semantics for a skip
  before wiring it to real scheduling — if the domain layer treats skip as a lapse, lower-confidence rating,
  or a no-op, keep that logic and only change how it looks.
- In **correction**: the action is labelled **Reveal answer** (owner wording decision 2026-10-04: a
  bare "Skip" mislabels what is left once recall has already failed). It plays the correct move on the
  user's behalf through the normal retry path — the lapse already stands, so this changes the flow,
  not the grade — and proceeds as if answered correctly.
- Skip is hidden during `note` (Continue is the only action) and during `quiet`.

## 4. Input

- **Pointer/touch:** tap-to-move (commit on the destination tap, not on release) and drag-to-move (5px
  threshold, commit on release over a square) both work everywhere, simultaneously.
- **Keyboard** (desktop/web, and any device with a hardware keyboard attached):
  - `Space` or `Enter`: Continue, when a note is showing.
  - `S`: the visible text action (Skip in prompt, Reveal answer in correction).
  - `P`: Practice, on the Nothing Due screen.
  - `Esc`: close any open sheet.
  - Standard tab order: scope button → due/practice (not focusable, it's not actionable) → overflow button →
    board (as one focusable region is acceptable; full square-by-square keyboard chess input is out of scope
    unless the product already supports it elsewhere) → notation line (not focusable) → Skip/Continue.
  - Show `kbd` hints only when a hardware keyboard is plausible (desktop/web, or `Theme.of(context).platform`
    plus keyboard-attached heuristics on tablets). Never show them on phones.
- **Piece selection:** selecting a piece and then tapping an invalid destination (not a legal repertoire
  square) still counts as an attempt and goes to `correction` — do not silently ignore illegal-looking
  destinations before checking the repertoire logic; let the existing move-legality layer decide what's
  legal, and treat "legal but not the repertoire move" the same as "illegal" for feedback purposes (both are
  "not this move").

## 5. Sheets (scope, library)

- Open: fade+slide in (150/180 ms) with the scrim. Close: reverse, plus Esc, scrim tap, or selecting a row.
- Only one sheet open at a time. Opening one while another is open replaces it (no stacking).
- Sheets sit above the Review screen; the screen behind is inert (aria-hidden / semantics excluded) while open.
- On wide layouts they are non-modal-looking popovers but should still trap focus for keyboard users and
  restore focus to the button that opened them on close.

## 6. Accessibility

- **Contrast:** all text and the accent meet WCAG 2.2 AA (4.5:1 normal text, 3:1 large text/graphics). Token
  contrast values are in `02-tokens.md`.
- **Non-colour feedback:** correction uses an arrow + large move text, never colour alone. Memory states use
  shape (solid/hatch/outline), not colour alone.
- **Screen reader:** announce position changes via a live region: `Correct. {san}.` / `Not this move. The
  repertoire move is {san}.`. The board itself should expose the current position in a way the platform's
  chess/board semantics conventions support (check what chessground/the current app already does here; keep
  it, only restyle).
- **Dynamic type / large text:** the notation line, answer move and note text should scale with the platform
  text-scale setting without breaking the board (the board's size is independent of text scale; only the side
  column's text reflows).
- **Reduced motion:** `MediaQuery.disableAnimationsOf(context)` collapses all durations in `02-tokens.md` §5 to
  zero; the correction arrow appears fully drawn instantly instead of animating in.
- **Touch targets:** minimum 44x44 for every interactive control, including sheet rows and switches (the
  visible switch is 44x26; pad its hit area vertically to reach 44).
- **Focus visibility:** 2px accent ring, 2px offset, on every focusable control (buttons, switches, segmented
  items, accent dots, rows, sheet items).
- **Reflow:** nothing requires horizontal scrolling at any supported width; the settings rows stack under 520.

## 7. Memory-state thresholds (product decision required)

The three-state memory bar (`03` §8) needs a mapping from FSRS fields to **new / learning / retained**. Suggested
default, to be confirmed against the actual scheduler in `lib/src/domain`:

- **new**: repetition count is 0 (never reviewed).
- **learning**: repetition count > 0 and (`stability` below a threshold OR `retrievability` below the
  configured target retention).
- **retained**: repetition count > 0 and `stability`/`retrievability` at or above threshold.

Do not invent new persisted fields; compute this at the presentation layer from existing FSRS state. If the
exact fields/threshold differ from this sketch, use the real ones and document the mapping where the bar is
built.
