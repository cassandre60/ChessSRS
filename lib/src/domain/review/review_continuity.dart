// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Line-continuity modes for in-line traversal after a correct move.
library;

/// How a [ReviewSession] walks the line after a correct answer. Orthogonal
/// to [ReviewOrder] (which orders the queued due set): [dueOnly] quizzes
/// only due positions; [fullLine] plays every line whole, start to end.
enum ReviewContinuity {
  /// Quiz only due positions; auto-play the rest (current behavior).
  dueOnly,

  /// Quiz every position along the walked line in tree order.
  fullLine,
}
