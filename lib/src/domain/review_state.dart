// Copyright (C) 2024 ChessSRS contributors
library chess_srs.domain.review_state;

// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/review_result.dart';

/// The SRS state for one [RepertoireDecision].
///
/// Tracks recall history so the [Scheduler] can compute the next due date.
/// All fields are immutable; state transitions produce new instances.
///
/// The [stability] field encodes the scheduler's internal interval growth
/// factor (e.g. current interval in days for [SimpleScheduler]). It is opaque
/// to the Review UI.
///
/// Invariant: [isDueAt] must be deterministic given an injected [Clock]
/// (QUALITY.md §3.2).
class ReviewState {
  const ReviewState({
    required this.decisionId,
    this.firstReviewedAt,
    this.lastReviewedAt,
    this.nextDueAt,
    this.repetitionCount = 0,
    this.lapseCount = 0,
    this.stability = 0.0,
    this.difficulty = 0.0,
  });

  /// Creates an initial (never-reviewed) state for [decisionId].
  factory ReviewState.initial({required String decisionId}) {
    return ReviewState(decisionId: decisionId);
  }

  /// The [RepertoireDecision.id] this state belongs to.
  final String decisionId;

  final DateTime? firstReviewedAt;
  final DateTime? lastReviewedAt;

  /// The wall-clock instant at which this item is next due for review.
  /// Null means "due immediately" (new item, never reviewed).
  final DateTime? nextDueAt;

  /// Successful recall streak / lifetime count (semantics depend on scheduler).
  final int repetitionCount;

  /// How many times the user has failed to recall this item.
  final int lapseCount;

  /// Scheduler-internal interval growth factor.
  final double stability;

  /// Intrinsic difficulty rating on the FSRS scale (1.0 to 10.0).
  final double difficulty;

  /// True when this item has never been reviewed.
  bool get isNew => repetitionCount == 0 && nextDueAt == null;

  /// True when this item has been reviewed at least once.
  bool get isLearned => repetitionCount > 0;

  /// Returns whether this item is due at [now].
  ///
  /// New items (never reviewed) are always due.
  bool isDueAt(DateTime now) => nextDueAt == null || !nextDueAt!.isAfter(now);

  ReviewState copyWith({
    DateTime? firstReviewedAt,
    DateTime? lastReviewedAt,
    DateTime? nextDueAt,
    int? repetitionCount,
    int? lapseCount,
    double? stability,
    double? difficulty,
  }) {
    return ReviewState(
      decisionId: decisionId,
      firstReviewedAt: firstReviewedAt ?? this.firstReviewedAt,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      nextDueAt: nextDueAt ?? this.nextDueAt,
      repetitionCount: repetitionCount ?? this.repetitionCount,
      lapseCount: lapseCount ?? this.lapseCount,
      stability: stability ?? this.stability,
      difficulty: difficulty ?? this.difficulty,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewState &&
          other.decisionId == decisionId &&
          other.firstReviewedAt == firstReviewedAt &&
          other.lastReviewedAt == lastReviewedAt &&
          other.nextDueAt == nextDueAt &&
          other.repetitionCount == repetitionCount &&
          other.lapseCount == lapseCount &&
          other.stability == stability &&
          other.difficulty == difficulty;

  @override
  int get hashCode => Object.hash(
    decisionId,
    firstReviewedAt,
    lastReviewedAt,
    nextDueAt,
    repetitionCount,
    lapseCount,
    stability,
    difficulty,
  );

  @override
  String toString() =>
      'ReviewState(decisionId: $decisionId, reps: $repetitionCount, '
      'lapses: $lapseCount, nextDue: $nextDueAt)';
}

/// Immutable historical record of one review attempt.
///
/// Kept for debugging and future analytics. Not used in the critical review
/// loop path (QUALITY.md §1.3).
class ReviewEvent {
  const ReviewEvent({
    required this.decisionId,
    required this.when,
    required this.result,
    required this.oldState,
    required this.newState,
  });

  final String decisionId;
  final DateTime when;
  final ReviewResult result;
  final ReviewState oldState;
  final ReviewState newState;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewEvent &&
          other.decisionId == decisionId &&
          other.when == when &&
          other.result == result &&
          other.oldState == oldState &&
          other.newState == newState;

  @override
  int get hashCode => Object.hash(decisionId, when, result, oldState, newState);

  @override
  String toString() => 'ReviewEvent(decisionId: $decisionId, when: $when, result: $result)';
}
