// Copyright (C) 2024 ChessSRS contributors
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
  byLine;

  String get label => switch (this) {
    ReviewOrder.dueDate => 'Due date',
    ReviewOrder.byLine => 'By line',
  };

  String get description => switch (this) {
    ReviewOrder.dueDate => 'Most overdue positions first, wherever they fall.',
    ReviewOrder.byLine => 'Walk each line in order; same due cards, less jumping.',
  };
}
