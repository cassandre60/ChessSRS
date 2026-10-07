// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Outcome and grading models for recall reviews.
library;

/// The outcome of a single review attempt.
enum ReviewResult {
  /// The player recalled the correct repertoire move.
  correct,

  /// The player played an incorrect or unexpected move.
  incorrect,
}
