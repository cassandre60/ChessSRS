// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Review scheduling and traversal engine.
library;

import 'dart:math';

import 'package:chess_srs/src/domain/chapter.dart';
import 'package:chess_srs/src/domain/clock.dart';
import 'package:chess_srs/src/domain/graph_aware_review_coordinator.dart';
import 'package:chess_srs/src/domain/repertoire_decision.dart';
import 'package:chess_srs/src/domain/review/review_mode.dart';
import 'package:chess_srs/src/domain/review/review_order.dart';
import 'package:chess_srs/src/domain/review/review_scope.dart';
import 'package:chess_srs/src/domain/review/review_session.dart';
import 'package:chess_srs/src/domain/review/transpose_scope.dart';
import 'package:chess_srs/src/domain/review_state.dart';
import 'package:chess_srs/src/domain/scheduler.dart';
import 'package:chess_srs/src/domain/study.dart';

/// Factory and configuration engine for [ReviewSession]s.
class ReviewEngine {
  const ReviewEngine({
    this.scheduler = const SimpleScheduler(),
    this.clock = const SystemClock(),
    this.random,
  });

  final Scheduler scheduler;
  final Clock clock;
  final Random? random;

  ReviewSession createSession({
    required List<Study> studies,
    required List<Chapter> chapters,
    required List<RepertoireDecision> decisions,
    required Map<String, ReviewState> reviewStates,
    ReviewScope scope = const ReviewScope.all(),
    ReviewMode mode = ReviewMode.srs,
    ReviewOrder order = ReviewOrder.dueDate,
    TransposeScope transposeScope = TransposeScope.inScope,
    int? prefetchBatchSize = 25,
    int prefetchRefillThreshold = 3,
    int? remainingDailyQuota,
    GraphAwareReviewCoordinator? coordinator,
    Map<String, DateTime>? initialExposureThrottle,
    Random? random,
  }) {
    return ReviewSession(
      studies: studies,
      chapters: chapters,
      decisions: decisions,
      reviewStates: reviewStates,
      scope: scope,
      mode: mode,
      order: order,
      transposeScope: transposeScope,
      scheduler: scheduler,
      clock: clock,
      prefetchBatchSize: prefetchBatchSize,
      prefetchRefillThreshold: prefetchRefillThreshold,
      remainingDailyQuota: remainingDailyQuota,
      coordinator: coordinator,
      initialExposureThrottle: initialExposureThrottle,
      random: random ?? this.random,
    );
  }
}
