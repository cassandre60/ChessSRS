// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Scheduler contract and interface definitions.
library;

import 'package:chess_srs/src/domain/clock.dart';
import 'package:chess_srs/src/domain/review_result.dart';
import 'package:chess_srs/src/domain/review_state.dart';

/// Replaceable scheduling algorithm contract.
///
/// The MVP ships [SimpleScheduler] (exponential interval ladder). The contract
/// is designed to allow a future FSRS or SM-2 implementation without changing
/// the Review UI or any other domain code (ARCHITECTURE.md §3, QUALITY.md §1).
abstract class Scheduler {
  /// Returns whether an item with [state] is due at [now].
  bool isDue(ReviewState state, DateTime now);

  /// Computes the next [ReviewState] after a review answered with [result].
  ///
  /// [now] is always injected (never calls [DateTime.now] directly).
  ReviewState schedule({
    required ReviewState previous,
    required ReviewResult result,
    required DateTime now,
  });
}

/// Simple exponential interval-ladder scheduler.
///
/// Successful recalls grow the interval by [intervalMultiplier]. A lapse
/// resets the repetition count and shrinks the interval back to [firstInterval].
///
/// There is no artificial maximum interval: items can disappear from daily
/// review for a long time and return when due (QUALITY.md §2.4 — no permanent
/// exclusion). The [maximumInterval] cap prevents absurdly long intervals but
/// is set very high by default (10 years).
///
/// Behavioral reference: adapted from chessrs SpacedRepetitionService logic
/// (GPL-3.0, ZackMurry/chessrs); reimplemented in Dart.
class SimpleScheduler implements Scheduler {
  const SimpleScheduler({
    this.firstInterval = const Duration(days: 1),
    this.baseInterval = const Duration(days: 2),
    this.intervalMultiplier = 2.0,
    this.maximumInterval = const Duration(days: 3650),
  });

  /// The interval assigned after the very first successful recall.
  final Duration firstInterval;

  /// The starting interval for the second successful recall.
  final Duration baseInterval;

  /// Multiplied with the current interval on each subsequent success.
  final double intervalMultiplier;

  /// Hard cap on any single interval.
  final Duration maximumInterval;

  Duration _clamp(Duration d) =>
      d.inMilliseconds > maximumInterval.inMilliseconds ? maximumInterval : d;

  @override
  bool isDue(ReviewState state, DateTime now) => state.isDueAt(now);

  @override
  ReviewState schedule({
    required ReviewState previous,
    required ReviewResult result,
    required DateTime now,
  }) {
    final firstSeen = previous.firstReviewedAt ?? now;

    switch (result) {
      case ReviewResult.correct:
        final Duration nextInterval;
        if (previous.repetitionCount == 0) {
          nextInterval = _clamp(firstInterval);
        } else if (previous.repetitionCount == 1) {
          nextInterval = _clamp(baseInterval);
        } else {
          // stability encodes current interval in milliseconds
          final current = previous.stability > 0
              ? Duration(milliseconds: previous.stability.round())
              : baseInterval;
          nextInterval = _clamp(
            Duration(
              milliseconds: (current.inMilliseconds * intervalMultiplier)
                  .round(),
            ),
          );
        }
        return previous.copyWith(
          firstReviewedAt: firstSeen,
          lastReviewedAt: now,
          nextDueAt: now.add(nextInterval),
          repetitionCount: previous.repetitionCount + 1,
          stability: nextInterval.inMilliseconds.toDouble(),
        );

      case ReviewResult.incorrect:
        return previous.copyWith(
          firstReviewedAt: firstSeen,
          lastReviewedAt: now,
          nextDueAt: now.add(firstInterval),
          repetitionCount: 0,
          lapseCount: previous.lapseCount + 1,
          stability: firstInterval.inMilliseconds.toDouble(),
        );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SimpleScheduler &&
          firstInterval == other.firstInterval &&
          baseInterval == other.baseInterval &&
          intervalMultiplier == other.intervalMultiplier &&
          maximumInterval == other.maximumInterval;

  @override
  int get hashCode => Object.hash(
    firstInterval,
    baseInterval,
    intervalMultiplier,
    maximumInterval,
  );
}

/// Parametric spaced repetition scheduler adapted from chessrs SpacedRepetitionService.
///
/// Computes intervals using an initial [ease] multiplier and geometric
/// [scaling] factor:
/// - First correct recall (repetition 0 -> 1): [firstInterval] (default 1 day)
/// - Second correct recall (repetition 1 -> 2): [firstInterval] * [ease] (default 2.5 days)
/// - Subsequent successes (repetition n >= 2): previous_interval * [scaling] (default 1.5x)
///
/// Upon a lapse (incorrect answer):
/// - [repetitionCount] resets to 0.
/// - [lapseCount] increments by 1.
/// - Interval resets to [firstInterval].
///
/// Attribution: Adapted from ZackMurry/chessrs (GPL-3.0), SpacedRepetitionService.kt.
class EaseScalingScheduler implements Scheduler {
  const EaseScalingScheduler({
    this.firstInterval = const Duration(days: 1),
    this.ease = 2.5,
    this.scaling = 1.5,
    this.maximumInterval = const Duration(days: 3650),
  }) : assert(ease >= 1.0, 'ease must be >= 1.0'),
       assert(scaling >= 1.0, 'scaling must be >= 1.0');

  /// The interval assigned after the very first successful recall.
  final Duration firstInterval;

  /// The multiplier applied to [firstInterval] for the second successful recall.
  final double ease;

  /// The geometric growth multiplier applied on each subsequent successful recall.
  final double scaling;

  /// Hard cap on any single interval.
  final Duration maximumInterval;

  Duration _clamp(Duration d) =>
      d.inMilliseconds > maximumInterval.inMilliseconds ? maximumInterval : d;

  @override
  bool isDue(ReviewState state, DateTime now) => state.isDueAt(now);

  @override
  ReviewState schedule({
    required ReviewState previous,
    required ReviewResult result,
    required DateTime now,
  }) {
    final firstSeen = previous.firstReviewedAt ?? now;

    switch (result) {
      case ReviewResult.correct:
        final Duration nextInterval;
        if (previous.repetitionCount == 0) {
          nextInterval = _clamp(firstInterval);
        } else if (previous.repetitionCount == 1) {
          nextInterval = _clamp(
            Duration(
              milliseconds: (firstInterval.inMilliseconds * ease).round(),
            ),
          );
        } else {
          final baseMs = (firstInterval.inMilliseconds * ease).round();
          final current = previous.stability > 0
              ? Duration(milliseconds: previous.stability.round())
              : Duration(milliseconds: baseMs);
          nextInterval = _clamp(
            Duration(milliseconds: (current.inMilliseconds * scaling).round()),
          );
        }
        return previous.copyWith(
          firstReviewedAt: firstSeen,
          lastReviewedAt: now,
          nextDueAt: now.add(nextInterval),
          repetitionCount: previous.repetitionCount + 1,
          stability: nextInterval.inMilliseconds.toDouble(),
        );

      case ReviewResult.incorrect:
        return previous.copyWith(
          firstReviewedAt: firstSeen,
          lastReviewedAt: now,
          nextDueAt: now.add(firstInterval),
          repetitionCount: 0,
          lapseCount: previous.lapseCount + 1,
          stability: firstInterval.inMilliseconds.toDouble(),
        );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EaseScalingScheduler &&
          firstInterval == other.firstInterval &&
          ease == other.ease &&
          scaling == other.scaling &&
          maximumInterval == other.maximumInterval;

  @override
  int get hashCode =>
      Object.hash(firstInterval, ease, scaling, maximumInterval);
}

/// Convenience: returns only items that are currently due.
List<ReviewState> dueItems(List<ReviewState> states, Clock clock) =>
    states.where((s) => s.isDueAt(clock.now())).toList(growable: false);
