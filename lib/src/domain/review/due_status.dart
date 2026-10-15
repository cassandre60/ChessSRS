// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/review_state.dart';

/// Where a position stands relative to the review schedule at one moment.
///
/// The three states are disjoint and exhaustive over a position's whole life,
/// and the split exists because a position nobody has ever been shown cannot be
/// overdue: the SRS ladder only starts once a position has actually been
/// presented and answered. Treating "no record" as "due" reported thousands of
/// recall obligations for material the user had not been asked a single time,
/// which is what a bulk import of a whole library produced (INV-068).
enum DueStatus {
  /// Never presented. Not recall work: introduced gradually and counted apart.
  fresh,

  /// Presented before, and the scheduled date has arrived.
  due,

  /// Presented before, and the scheduled date is still in the future.
  scheduled;

  /// Whether this position is recall work the user is answerable for right now.
  bool get isDue => this == DueStatus.due;

  /// Whether this position has never been presented.
  bool get isFresh => this == DueStatus.fresh;
}

/// Classifies a position by its review [state] at [now].
///
/// [state] is null for a position with no SRS record at all, which is exactly
/// the "never presented" case. Note this is deliberately *not* the same question
/// as "should the session stop and ask this?" — auto-traversal asks a fresh
/// position because it is unlearned, but does not call it due.
DueStatus dueStatusOf(ReviewState? state, DateTime now) {
  if (state == null) return DueStatus.fresh;
  return state.isDueAt(now) ? DueStatus.due : DueStatus.scheduled;
}
