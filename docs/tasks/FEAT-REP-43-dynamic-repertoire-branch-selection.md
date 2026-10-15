# FEAT-REP-43 — Dynamic Repertoire Branch Selection (Encyclopedia vs Personal Repertoire)

> **For an agent picking up this task**: Follow this brief top-to-bottom.
> This feature introduces dynamic line unlocking for opening repertoires, separating
> reference encyclopedia material from active player repertoire decisions.

## 1. Problem Statement & Motivation

Currently, when PGN studies are imported, every single move for the player's repertoire side
becomes a `RepertoireDecision` and is immediately queued as due/new. In comprehensive
studies (which often include multiple alternative moves for White, e.g. `3. Nc3`, `3. e5`,
and `3. Nd2` vs the French), the user is forced into learning every alternative.

In real-world chess preparation:
- An opening study often acts as an **encyclopedia/reference**.
- For the player's side, a player chooses **one weapon** (e.g. `3. Nc3`) and wants to drill
  thoroughly against all opponent replies. Adding an alternative branch is a rare, deliberate decision.
- Mastered lines have long SRS intervals (e.g. 4 months), during which the root decision
  is not due, preventing the player from branching into new variations during normal SRS reviews.

## 2. Intended Architecture & Behavior

### 2.1 The Dynamic Repertoire Setting
Add an option (toggleable in SRS Settings, with scope overrides per opening and per study):
- **Full Reference Mode (Default)**: Every decision in every imported line is actively scheduled.
- **Dynamic Repertoire Mode**:
  - All candidate moves present in the reference studies are accepted as valid.
  - Only lines/branches explicitly chosen or activated by the user are scheduled in SRS.
  - Sibling branches that the user has not chosen remain inactive: they do **not** generate
    due cards, do **not** inflate new card counts, and when active lines are mastered, the
    queue correctly reports **0 due, 0 new**.

### 2.2 Practice Mode Opt-In Line Activation
To resolve the "4-month interval wait" without violating Practice Mode's zero-stakes contract:
- In `ReviewMode.practice`, the player can freely walk any repertoire tree from move 1 anytime.
- When the player plays a move that belongs to an inactive/dormant branch in the study:
  - Practice continues without modifying SRS intervals or recording lapses.
  - A discreet, non-blocking toast/banner appears:
    `"You played a new variation (e.g. 3. e5). Add this branch to your daily review queue? [Add to SRS]"`
  - Tapping **Add to SRS** unlocks that branch: its decisions enter the active SRS schedule.
  - If ignored or dismissed, the line remains dormant reference material.

### 2.3 Review Session Grading
- When presented with a prompt where multiple candidate moves exist in the reference studies,
  playing **any** in-scope candidate move is graded correct.
- If the played move corresponds to an already-active branch, review follows that continuation.
- If the user plays an invalid blunder (not in any study), quiet feedback is given (no spoiler arrows by default, preserving the quiet-feedback principle).

## 3. Implementation Steps

1. **Model & Preferences**:
   - Add `dynamicRepertoireMode` preference in `StudyPrefs` (and support per-study / per-opening toggles).
   - Add tracking for activated decision/branch IDs (e.g. in `srs_decision` or a lightweight `srs_active_branch` table).
2. **Review Service & Due Queue**:
   - In `ReviewService` and `ReviewSession`: when dynamic mode is active, filter out unactivated branches from `totalDueCount`, `openingDueCounts`, and `_unbufferedQueue`.
3. **Practice Mode Activation Banner**:
   - In `ReviewScreen`, when `ReviewMode.practice` plays a move at a node with an inactive branch, trigger the opt-in activation prompt.
4. **Verification & Tests**:
   - Unit tests covering:
     - All candidate moves accepted in dynamic mode.
     - Unactivated branches excluded from due/new tallies.
     - Activating a branch adds its descendants to the due queue.
