// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:chess_srs/src/domain/review_result.dart';
import 'package:chess_srs/src/domain/review_state.dart';
import 'package:chess_srs/src/domain/scheduler.dart';
import 'package:logging/logging.dart';

final Logger _logger = Logger('FsrsScheduler');

/// Rating outcome for binary FSRS recall in chess (Decision D015).
///
/// In chess, thinking time reflects candidate move verification and calculation,
/// not weak memory. Therefore, ratings collapse strictly to binary Pass/Fail:
/// - [again]: incorrect move, hint used, or corrected false-start attempt.
/// - [good]: first committed move was correct (regardless of calculation time).
///
/// All three [again] cases arrive as a single [ReviewResult.incorrect]. The
/// review session is what recognises a hint or a corrected false-start and grades
/// it once; this class never sees them separately.
enum FsrsRating { again, good }

int _g(FsrsRating r) => r == FsrsRating.again ? 1 : 3;

/// Parameters for the domain-adapted ChessFSRS binary DSR model.
class ChessFsrsParams {
  const ChessFsrsParams({
    this.w0 = 0.35,
    this.w2 = 2.20,
    this.w4 = 4.93,
    this.w5 = 0.94,
    this.w6 = 1.05,
    this.w7 = 0.01,
    this.w8 = 1.49,
    this.w9 = 0.14,
    this.w10 = 0.94,
    this.w11 = 2.18,
    this.w12 = 0.09,
    this.w13 = 0.34,
    this.w14 = 1.26,
    this.sameDayThresholdDays = 1 / 24, // 1 hour
    this.sameDayGainFactor = 1.02,
    this.sameDayLapseFactor = 0.85,
    this.minStabilityDays = 0.02, // ~30 minutes floor
    this.maxStabilityDays = 365 * 5, // 5 years cap
  });

  const ChessFsrsParams.chessDefaults() : this();

  // Initial stability per rating (days)
  final double w0; // S0(Again)
  final double w2; // S0(Good)

  // Difficulty formulas
  final double w4; // D0 base
  final double w5; // D0 slope
  final double w6; // D responsiveness
  final double w7; // D mean reversion

  // Stability success formula
  final double w8;
  final double w9;
  final double w10;

  // Stability lapse formula
  final double w11;
  final double w12;
  final double w13;
  final double w14;

  // Guard parameters for rapid re-reviews
  final double sameDayThresholdDays;
  final double sameDayGainFactor;
  final double sameDayLapseFactor;

  final double minStabilityDays;
  final double maxStabilityDays;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChessFsrsParams &&
          w0 == other.w0 &&
          w2 == other.w2 &&
          w4 == other.w4 &&
          w5 == other.w5 &&
          w6 == other.w6 &&
          w7 == other.w7 &&
          w8 == other.w8 &&
          w9 == other.w9 &&
          w10 == other.w10 &&
          w11 == other.w11 &&
          w12 == other.w12 &&
          w13 == other.w13 &&
          w14 == other.w14 &&
          sameDayThresholdDays == other.sameDayThresholdDays &&
          sameDayGainFactor == other.sameDayGainFactor &&
          sameDayLapseFactor == other.sameDayLapseFactor &&
          minStabilityDays == other.minStabilityDays &&
          maxStabilityDays == other.maxStabilityDays;

  @override
  int get hashCode => Object.hash(
    w0,
    w2,
    w4,
    w5,
    w6,
    w7,
    w8,
    w9,
    w10,
    w11,
    w12,
    w13,
    w14,
    sameDayThresholdDays,
    sameDayGainFactor,
    sameDayLapseFactor,
    minStabilityDays,
    maxStabilityDays,
  );
}

const double kFsrsDecay = -0.5;
final double kFsrsFactor = math.pow(0.9, 1 / kFsrsDecay).toDouble() - 1; // 19 / 81 ≈ 0.2345679

/// Calculates retrievability probability R(t, S) given elapsed time and stability in days.
double fsrsRetrievability(double elapsedDays, double stabilityDays) {
  if (stabilityDays <= 0) return 0.0;
  final t = elapsedDays < 0 ? 0.0 : elapsedDays;
  return math.pow(1 + kFsrsFactor * t / stabilityDays, kFsrsDecay).toDouble();
}

/// Solves for the optimal review interval in days to hit [targetRetention].
double fsrsIntervalForTarget(double stabilityDays, double targetRetention) {
  final r = targetRetention.clamp(0.70, 0.99);
  final raw = stabilityDays / kFsrsFactor * (math.pow(r, 1 / kFsrsDecay) - 1);
  return raw.isFinite && raw > 0 ? raw : 0.0;
}

/// Calculates initial difficulty D0 for a newly introduced move.
double fsrsInitialDifficulty(FsrsRating rating, ChessFsrsParams p) {
  final g = _g(rating);
  return (p.w4 - (g - 3) * p.w5).clamp(1.0, 10.0);
}

/// Calculates next difficulty D' upon recall outcome.
double fsrsNextDifficulty(double d, FsrsRating rating, ChessFsrsParams p) {
  final g = _g(rating);
  final delta = d - p.w6 * (g - 3);
  final reverted = p.w7 * p.w4 + (1 - p.w7) * delta;
  return reverted.clamp(1.0, 10.0);
}

/// Initial stability in days for cold-start.
double fsrsInitialStability(FsrsRating rating, ChessFsrsParams p) =>
    rating == FsrsRating.again ? p.w0 : p.w2;

/// Calculates new stability after successful recall (Rating.good).
double fsrsNextStabilitySuccess(double d, double s, double r, ChessFsrsParams p) {
  final safeS = s <= 0 ? p.minStabilityDays : s;
  final factor =
      math.exp(p.w8) * (11 - d) * math.pow(safeS, -p.w9) * (math.exp((1 - r) * p.w10) - 1);
  return safeS * (1 + factor);
}

/// Calculates regressed stability after a lapse (Rating.again).
double fsrsNextStabilityLapse(double d, double s, double r, ChessFsrsParams p) {
  final safeS = s <= 0 ? p.minStabilityDays : s;
  return p.w11 * math.pow(d, -p.w12) * (math.pow(safeS + 1, p.w13) - 1) * math.exp((1 - r) * p.w14);
}

/// Domain-adapted FSRS-5 spaced repetition scheduler for chess repertoires.
///
/// Implements continuous Difficulty-Stability-Retrievability (DSR) power-law forgetting curves
/// with binary grading (Decision D015) and explicit target retention solving ($R_{\text{target}}$).
class ChessFsrsScheduler implements Scheduler {
  const ChessFsrsScheduler({
    this.params = const ChessFsrsParams.chessDefaults(),
    this.targetRetention = 0.88,
    this.maxIntervalDays = 365 * 3, // 3 years
    this.minIntervalDays = 1 / 1440, // 1 minute
  });

  final ChessFsrsParams params;

  /// Target recall probability (default 88%; 95% in Tournament Mode).
  final double targetRetention;

  final double maxIntervalDays;
  final double minIntervalDays;

  static const int _dayMs = 86400000;

  @override
  bool isDue(ReviewState state, DateTime now) => state.isDueAt(now);

  @override
  ReviewState schedule({
    required ReviewState previous,
    required ReviewResult result,
    required DateTime now,
  }) {
    // Binary rating (Decision D015). "Was this recall independent?" — hint used,
    // or a corrected false-start — is settled upstream by the review session and
    // arrives folded into [result]: a fumbled answer reaches the scheduler as
    // [ReviewResult.incorrect] exactly once, not as a lapse plus a later pass.
    final rating = result == ReviewResult.incorrect ? FsrsRating.again : FsrsRating.good;

    final anchor = previous.lastReviewedAt ?? previous.firstReviewedAt;
    double elapsedDays = 0.0;
    if (anchor != null) {
      final diffMs = now.difference(anchor).inMilliseconds;
      elapsedDays = diffMs <= 0 ? 0.0 : diffMs / _dayMs;
    }

    final bool isColdStart = previous.repetitionCount == 0 && previous.stability <= 0;

    double newDifficulty;
    double newStabilityDays;

    if (isColdStart) {
      newDifficulty = fsrsInitialDifficulty(rating, params);
      newStabilityDays = fsrsInitialStability(rating, params);
    } else {
      final prevStabilityDays = previous.stability <= 0
          ? params.minStabilityDays
          : previous.stability / _dayMs;
      final prevDifficulty = previous.difficulty <= 0
          ? fsrsInitialDifficulty(FsrsRating.good, params)
          : previous.difficulty;

      final bool isRapidReReview = elapsedDays < params.sameDayThresholdDays;

      if (isRapidReReview) {
        // Architecture §C.7: a rapid re-review (elapsed < sameDayThresholdDays) skips the
        // full DSR update and applies only a small linear stability nudge. Difficulty is
        // part of that update, so it freezes too. Updating D here let a burst of
        // intra-session failures ratchet it to the 10.0 clamp — three misses in one session
        // were enough — which then shrank the (11 - D) growth term from 6.07 to 1.00 and
        // took ~390 successful reviews of mean reversion at w7 to unwind.
        newDifficulty = prevDifficulty;
        newStabilityDays = rating == FsrsRating.again
            ? prevStabilityDays * params.sameDayLapseFactor
            : prevStabilityDays * params.sameDayGainFactor;
      } else {
        final r = fsrsRetrievability(elapsedDays, prevStabilityDays);
        newDifficulty = fsrsNextDifficulty(prevDifficulty, rating, params);
        newStabilityDays = rating == FsrsRating.again
            ? fsrsNextStabilityLapse(newDifficulty, prevStabilityDays, r, params)
            : fsrsNextStabilitySuccess(newDifficulty, prevStabilityDays, r, params);
      }
    }

    newStabilityDays = newStabilityDays.clamp(params.minStabilityDays, params.maxStabilityDays);

    final effectiveRetention = targetRetention.clamp(0.70, 0.99);
    final intervalDays = fsrsIntervalForTarget(
      newStabilityDays,
      effectiveRetention,
    ).clamp(minIntervalDays, maxIntervalDays);

    final nextDue = now.add(Duration(milliseconds: (intervalDays * _dayMs).round()));

    _logger.fine(
      'FSRS scheduled decision ${previous.decisionId}: rating=${rating.name}, '
      'D=${newDifficulty.toStringAsFixed(2)}, S=${newStabilityDays.toStringAsFixed(2)}d, '
      'interval=${intervalDays.toStringAsFixed(2)}d (targetRetention=$effectiveRetention)',
    );

    return previous.copyWith(
      firstReviewedAt: previous.firstReviewedAt ?? now,
      lastReviewedAt: now,
      nextDueAt: nextDue,
      repetitionCount: rating == FsrsRating.again
          ? previous.repetitionCount
          : previous.repetitionCount + 1,
      lapseCount: rating == FsrsRating.again ? previous.lapseCount + 1 : previous.lapseCount,
      stability: newStabilityDays * _dayMs,
      difficulty: newDifficulty,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChessFsrsScheduler &&
          params == other.params &&
          targetRetention == other.targetRetention &&
          maxIntervalDays == other.maxIntervalDays &&
          minIntervalDays == other.minIntervalDays;

  @override
  int get hashCode => Object.hash(params, targetRetention, maxIntervalDays, minIntervalDays);
}

/// Generates a preview of the interval ladder (in days) for consecutive successful recalls
/// under [targetRetention].
List<double> fsrsIntervalProgressionPreview({
  required double targetRetention,
  int steps = 5,
  ChessFsrsParams params = const ChessFsrsParams.chessDefaults(),
}) {
  final intervals = <double>[];
  var d = fsrsInitialDifficulty(FsrsRating.good, params);
  var s = params.w2; // Initial stability for Rating.good in days
  final effectiveR = targetRetention.clamp(0.70, 0.99);

  for (var i = 0; i < steps; i++) {
    final intervalDays = fsrsIntervalForTarget(s, effectiveR);
    intervals.add(intervalDays);
    d = fsrsNextDifficulty(d, FsrsRating.good, params);
    s = fsrsNextStabilitySuccess(d, s, effectiveR, params);
  }
  return List.unmodifiable(intervals);
}
