// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Repertoire mastery and learning progress metrics.
library;

import 'package:meta/meta.dart';

/// Progress metrics for a repertoire study, chapter, or scope.
///
/// Implements Listudy-inspired `tree_progress` semantics (docs/INTEGRATION_MAP.md §From Listudy),
/// tracking total scheduled decisions, learned moves (repetition count > 0), and currently due moves.
@immutable
class RepertoireProgress {
  const RepertoireProgress({
    required this.totalDecisions,
    required this.learnedDecisions,
    required this.dueDecisions,
  });

  /// Empty progress representing zero decisions.
  static const zero = RepertoireProgress(totalDecisions: 0, learnedDecisions: 0, dueDecisions: 0);

  /// Total number of decision points in the study/chapter.
  final int totalDecisions;

  /// Number of decision points that have been recalled at least once with repetition count > 0.
  final int learnedDecisions;

  /// Number of decision points currently due for review.
  final int dueDecisions;

  /// Number of decisions not yet learned (unseen or 0 repetitions).
  int get unlearnedDecisions => totalDecisions - learnedDecisions;

  /// Mastery fraction between 0.0 and 1.0.
  double get progressFraction =>
      totalDecisions == 0 ? 0.0 : (learnedDecisions / totalDecisions).clamp(0.0, 1.0);

  /// Mastery percentage rounded to nearest integer (0 to 100).
  int get progressPercentage => (progressFraction * 100).round();

  /// Combines two progress records.
  RepertoireProgress operator +(RepertoireProgress other) {
    return RepertoireProgress(
      totalDecisions: totalDecisions + other.totalDecisions,
      learnedDecisions: learnedDecisions + other.learnedDecisions,
      dueDecisions: dueDecisions + other.dueDecisions,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RepertoireProgress &&
          runtimeType == other.runtimeType &&
          totalDecisions == other.totalDecisions &&
          learnedDecisions == other.learnedDecisions &&
          dueDecisions == other.dueDecisions;

  @override
  int get hashCode => Object.hash(totalDecisions, learnedDecisions, dueDecisions);

  @override
  String toString() =>
      'RepertoireProgress(total: $totalDecisions, learned: $learnedDecisions, due: $dueDecisions, pct: $progressPercentage%)';
}
