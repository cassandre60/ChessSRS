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

/// The unguarded offload decision: at or above the threshold.
///
/// Split from [shouldOffloadPgnWork] so the documented boundary itself stays
/// testable — the public helper's web/test guard would otherwise make the
/// `8192` edge unobservable under `flutter_test` (mutation round MUTATION-10).
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
  return offloadsAt(textLength);
}

/// Whether [textLength] crosses the offload threshold — the pure boundary
/// decision behind [shouldOffloadPgnWork], "at or above" per POLISH-FIX-10.
bool offloadsAt(int textLength) => textLength >= pgnOffloadThresholdBytes;
