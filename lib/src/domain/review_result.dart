// Copyright (C) 2024 ChessSRS contributors
library chess_srs.domain.review_result;

// SPDX-License-Identifier: GPL-3.0-or-later

/// The outcome of a single review attempt.
enum ReviewResult {
  /// The player recalled the correct repertoire move.
  correct,

  /// The player played an incorrect or unexpected move.
  incorrect,
}
