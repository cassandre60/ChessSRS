// Copyright (C) 2024 ChessSRS contributors
library chess_srs.domain.review.review_engine;
// SPDX-License-Identifier: GPL-3.0-or-later

/// The order in which a [ReviewSession] presents its due queue.
///
/// The due *set* never depends on this: urgency filtering and the daily
/// quota cut always apply first. Only consecutive presentation order changes.
enum ReviewOrder {
  /// Most overdue first, wherever the positions fall (previous behavior).
  dueDate,

  /// Walk each line in order: study, then chapter, then tree order.
  /// Same due cards, fewer jumps between unrelated positions.
  byLine,

  /// Same due cards in shuffled order, for variety across sessions.
  random,
}
