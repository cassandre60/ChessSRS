// Copyright (C) 2026 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC INV-026, INV-025.

import 'package:chess_srs/src/domain/review_result.dart';
import 'package:chess_srs/src/domain/review_state.dart';
import 'package:chess_srs/src/domain/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const maximum = Duration(days: 1);
  const intervals = [
    (first: Duration(hours: 12), expected: Duration(hours: 12)),
    (first: Duration(days: 1), expected: Duration(days: 1)),
    (first: Duration(days: 2), expected: Duration(days: 1)),
  ];
  final factories = <String, Scheduler Function(Duration)>{
    'SimpleScheduler': (first) => SimpleScheduler(firstInterval: first, maximumInterval: maximum),
    'EaseScalingScheduler': (first) =>
        EaseScalingScheduler(firstInterval: first, maximumInterval: maximum),
  };
  final now = DateTime.utc(2026, 10, 21, 12);
  final firstReview = now.subtract(const Duration(days: 7));
  final previous = ReviewState(
    decisionId: 'question-1',
    firstReviewedAt: firstReview,
    lastReviewedAt: now.subtract(const Duration(days: 1)),
    nextDueAt: now,
    repetitionCount: 3,
    lapseCount: 2,
    stability: const Duration(days: 5).inMilliseconds.toDouble(),
    difficulty: 6,
  );

  for (final factory in factories.entries) {
    test('${factory.key} lapse intervals respect maximumInterval', () {
      for (final interval in intervals) {
        final next = factory
            .value(interval.first)
            .schedule(previous: previous, result: ReviewResult.incorrect, now: now);
        expect(
          next.nextDueAt,
          now.add(interval.expected),
          reason: 'firstInterval=${interval.first} must respect the $maximum cap on lapse',
        );
        expect(next.stability, interval.expected.inMilliseconds.toDouble());
        expect(next.repetitionCount, 0);
        expect(next.lapseCount, previous.lapseCount + 1);
        expect(next.decisionId, previous.decisionId);
        expect(next.firstReviewedAt, firstReview);
        expect(next.lastReviewedAt, now);
        expect(next.difficulty, previous.difficulty);
      }
    });
  }
}
