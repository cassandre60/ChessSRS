// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Line-continuity modes for in-line traversal after a correct move.
library;

/// How a [ReviewSession] walks the repertoire line after a correct answer.
///
/// Orthogonal to [ReviewOrder] (which orders the queued due set): continuity
/// governs what happens *inside* one line. `dueOnly` quizzes only due
/// positions and auto-plays the rest (SRS-efficient, current behavior).
/// `fullLine` quizzes every position in tree order, even when not yet due —
/// slower, but the line stays coherent (no A → C jumps over an unasked B).
enum ReviewContinuity {
  /// Quiz only due positions; auto-play known moves (current behavior).
  dueOnly,

  /// Quiz every position along the walked line in tree order.
  fullLine,
}
