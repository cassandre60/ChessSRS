// Copyright (C) 2024 ChessSRS contributors
library chess_srs.domain.review.review_engine;
// SPDX-License-Identifier: GPL-3.0-or-later

/// The operational mode for a [ReviewSession].
enum ReviewMode {
  /// Standard spaced-repetition mode: queries due items, updates intervals,
  /// records lapses and logs recall events.
  srs,

  /// Non-destructive practice / cram mode (PRODUCT.md Journey 4):
  /// trains all positions in the repertoire regardless of due date without
  /// modifying review states or logging events.
  practice,
}
