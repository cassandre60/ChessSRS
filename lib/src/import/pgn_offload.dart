// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// When PGN work is worth offloading to a worker isolate.
///
/// This file owns the "when to offload" decision and is the only place that sniffs
/// `dart:io`'s `Platform.environment` for it (tech-debt item 8). Three call sites read
/// this helper instead of repeating the guard: `computePgnHashAsync` and `importPgnAsync`
/// in `pgn_importer.dart`, and `ReviewController.importPgnText`.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Byte length at or above which PGN work moves to a worker isolate.
///
/// Deliberate decision (POLISH-FIX-10): 8192, the lower of the two historical thresholds.
/// Tree building dominates hash cost, so isolating at 8 KB keeps typical 10–30 KB
/// repertoires' parse off the UI thread. A file whose hash is computed off-thread also has
/// its parse off-thread — the two must never disagree about the boundary.
const int pgnOffloadThresholdBytes = 8192;

/// Whether PGN work over [textLength] bytes should run on a worker isolate.
///
/// Always false on web (no `Isolate.run` for this work there) and in widget tests (spawning
/// real isolates under the test binding is slow and flaky; the work itself is covered by
/// synchronous tests).
bool shouldOffloadPgnWork({required int textLength}) {
  if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) return false;
  return textLength >= pgnOffloadThresholdBytes;
}
