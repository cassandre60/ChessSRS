// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Move transposition matching scope options.
library;

/// Controls how far review-time transposition acceptance reaches (SPEC INV-065).
enum TransposeScope {
  /// Strict line grading: only moves on the prompted decision are accepted.
  off,

  /// Accepts transposed repertoire moves within the same [Study].
  withinStudy,

  /// Accepts transposed repertoire moves across the active [ReviewScope].
  inScope,
}
