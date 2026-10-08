# Red-team case: rt-07-ratchet-dep

Status: active
Category: real-bug-class (unjustified dependency)
Expected catcher(s): G10 ratchets (direct_dependencies), G07 protected paths

## What the patch does
Adds one direct dependency to `pubspec.yaml` with no justification entry.

## Why it is wrong
Each dependency is a liability (size, startup, supply chain). Additions need
a written reason and approval.

## Why a naive gate would pass it
The suite is green and analysis is clean; only the dependency ratchet and
referee protection notice.

Patch file: `patch.diff` (git diff format, applies to the commit recorded below)
Recorded against: 21a137d67
