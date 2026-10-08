# Red-team case: rt-05-banned-import

Status: active
Category: real-bug-class (layer violation)
Expected catcher(s): G03 banned APIs, G02 boundary test

## What the patch does
Adds `import 'package:flutter/widgets.dart';` to
`lib/src/domain/study.dart`, pulling UI into the pure core.

## Why it is wrong
SPEC INV-040: the domain layer is pure Dart. A UI import compiles fine and
all tests pass, but the layer boundary is breached and every future agent
can follow the precedent.

## Why a naive gate would pass it
The suite is green and analysis is clean; only the boundary scan notices.

Patch file: `patch.diff` (git diff format, applies to the commit recorded below)
Recorded against: 21a137d67
