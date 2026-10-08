// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-024, INV-025, INV-026, INV-030, INV-041.

import 'package:chess_srs/src/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 9, 16, 10);

  group('ReviewState', () {
    test('initial state is new and due', () {
      final s = ReviewState.initial(decisionId: 'd1');
      expect(s.isNew, isTrue);
      expect(s.isLearned, isFalse);
      expect(s.isDueAt(t0), isTrue);
      expect(s.repetitionCount, equals(0));
      expect(s.lapseCount, equals(0));
    });

    test('copyWith updates only specified fields', () {
      final s = ReviewState.initial(decisionId: 'd1');
      final updated = s.copyWith(repetitionCount: 3, lapseCount: 1);
      expect(updated.decisionId, equals('d1'));
      expect(updated.repetitionCount, equals(3));
      expect(updated.lapseCount, equals(1));
    });

    test('isDueAt returns false when nextDueAt is in the future', () {
      final s = ReviewState(decisionId: 'd1', nextDueAt: t0.add(const Duration(days: 1)));
      expect(s.isDueAt(t0), isFalse);
    });

    test('isDueAt returns true when nextDueAt is now', () {
      final s = ReviewState(decisionId: 'd1', nextDueAt: t0);
      expect(s.isDueAt(t0), isTrue);
    });

    test('isDueAt returns true when nextDueAt is in the past', () {
      final s = ReviewState(decisionId: 'd1', nextDueAt: t0.subtract(const Duration(hours: 1)));
      expect(s.isDueAt(t0), isTrue);
    });
  });

  group('Clock', () {
    test('FixedClock returns injected value', () {
      final clock = FixedClock(t0);
      expect(clock.now(), equals(t0));
    });

    test('FixedClock.advance moves time forward', () {
      final clock = FixedClock(t0);
      clock.advance(const Duration(days: 1));
      expect(clock.now(), equals(t0.add(const Duration(days: 1))));
    });
  });

  group('SimpleScheduler', () {
    const scheduler = SimpleScheduler();

    test('first correct recall sets nextDueAt to firstInterval', () {
      final s0 = ReviewState.initial(decisionId: 'd1');
      final s1 = scheduler.schedule(previous: s0, result: ReviewResult.correct, now: t0);
      expect(s1.repetitionCount, equals(1));
      expect(s1.lapseCount, equals(0));
      expect(s1.firstReviewedAt, equals(t0));
      expect(s1.lastReviewedAt, equals(t0));
      expect(s1.nextDueAt, equals(t0.add(const Duration(days: 1))));
    });

    test('second correct recall sets nextDueAt to baseInterval', () {
      final s0 = ReviewState.initial(decisionId: 'd1');
      final s1 = scheduler.schedule(previous: s0, result: ReviewResult.correct, now: t0);
      final t1 = t0.add(const Duration(days: 1));
      final s2 = scheduler.schedule(previous: s1, result: ReviewResult.correct, now: t1);
      expect(s2.repetitionCount, equals(2));
      expect(s2.nextDueAt, equals(t1.add(const Duration(days: 2))));
    });

    test('interval grows exponentially after third recall', () {
      var state = ReviewState.initial(decisionId: 'd1');
      var now = t0;
      // review 1 → 1 day
      state = scheduler.schedule(previous: state, result: ReviewResult.correct, now: now);
      now = now.add(const Duration(days: 1));
      // review 2 → 2 days
      state = scheduler.schedule(previous: state, result: ReviewResult.correct, now: now);
      now = now.add(const Duration(days: 2));
      // review 3 → 2 * 2 = 4 days
      state = scheduler.schedule(previous: state, result: ReviewResult.correct, now: now);
      expect(state.nextDueAt, equals(now.add(const Duration(days: 4))));
    });

    test('incorrect recall resets repetitions and records a lapse', () {
      final s0 = ReviewState.initial(decisionId: 'd1');
      final s1 = scheduler.schedule(previous: s0, result: ReviewResult.correct, now: t0);
      final t1 = t0.add(const Duration(days: 1));
      final s2 = scheduler.schedule(previous: s1, result: ReviewResult.incorrect, now: t1);
      expect(s2.repetitionCount, equals(0));
      expect(s2.lapseCount, equals(1));
      expect(s2.nextDueAt, equals(t1.add(const Duration(days: 1))));
    });

    test('a lapsed item recovers correctly after a correct recall', () {
      var state = ReviewState.initial(decisionId: 'd1');
      var now = t0;
      state = scheduler.schedule(previous: state, result: ReviewResult.correct, now: now);
      now = now.add(const Duration(days: 1));
      state = scheduler.schedule(previous: state, result: ReviewResult.correct, now: now);
      now = now.add(const Duration(days: 2));
      // Lapse
      state = scheduler.schedule(previous: state, result: ReviewResult.incorrect, now: now);
      expect(state.lapseCount, equals(1));
      expect(state.repetitionCount, equals(0));
      // Recovery — next correct should be firstInterval again
      now = now.add(const Duration(days: 1));
      state = scheduler.schedule(previous: state, result: ReviewResult.correct, now: now);
      expect(state.repetitionCount, equals(1));
      expect(state.nextDueAt, equals(now.add(const Duration(days: 1))));
    });

    test('isDue returns true for new items', () {
      final s = ReviewState.initial(decisionId: 'd1');
      expect(scheduler.isDue(s, t0), isTrue);
    });

    test('isDue returns false for future items', () {
      final s = ReviewState(
        decisionId: 'd1',
        nextDueAt: t0.add(const Duration(days: 5)),
        repetitionCount: 2,
      );
      expect(scheduler.isDue(s, t0), isFalse);
    });

    test('interval is capped at maximumInterval', () {
      const tiny = SimpleScheduler(
        firstInterval: Duration(days: 1),
        baseInterval: Duration(days: 2),
        intervalMultiplier: 100.0,
        maximumInterval: Duration(days: 30),
      );
      var state = ReviewState.initial(decisionId: 'd1');
      var now = t0;
      // Pump through several reviews to hit the cap
      for (var i = 0; i < 10; i++) {
        state = tiny.schedule(previous: state, result: ReviewResult.correct, now: now);
        now = state.nextDueAt!;
      }
      final interval = state.nextDueAt!.difference(state.lastReviewedAt!);
      expect(interval.inDays, lessThanOrEqualTo(30));
    });

    test('dueItems filters correctly', () {
      final states = [
        ReviewState(
          decisionId: 'd1',
          nextDueAt: t0.subtract(const Duration(hours: 1)),
          repetitionCount: 1,
        ),
        ReviewState(
          decisionId: 'd2',
          nextDueAt: t0.add(const Duration(hours: 1)),
          repetitionCount: 1,
        ),
        ReviewState.initial(decisionId: 'd3'), // new = always due
      ];
      final clock = FixedClock(t0);
      final due = dueItems(states, clock);
      expect(due.map((s) => s.decisionId).toList(), containsAll(['d1', 'd3']));
      expect(due.map((s) => s.decisionId).toList(), isNot(contains('d2')));
    });
  });

  group('EaseScalingScheduler', () {
    const scheduler = EaseScalingScheduler(
      firstInterval: Duration(days: 1),
      ease: 2.5,
      scaling: 1.5,
    );

    test('first correct recall sets nextDueAt to firstInterval (1 day)', () {
      final s0 = ReviewState.initial(decisionId: 'd1');
      final s1 = scheduler.schedule(previous: s0, result: ReviewResult.correct, now: t0);
      expect(s1.repetitionCount, 1);
      expect(s1.lapseCount, 0);
      expect(s1.firstReviewedAt, t0);
      expect(s1.lastReviewedAt, t0);
      expect(s1.nextDueAt, t0.add(const Duration(days: 1)));
      expect(s1.stability, const Duration(days: 1).inMilliseconds.toDouble());
    });

    test('second correct recall scales by ease factor (2.5 days)', () {
      final s0 = ReviewState.initial(decisionId: 'd1');
      final s1 = scheduler.schedule(previous: s0, result: ReviewResult.correct, now: t0);
      final t1 = t0.add(const Duration(days: 1));
      final s2 = scheduler.schedule(previous: s1, result: ReviewResult.correct, now: t1);
      expect(s2.repetitionCount, 2);
      expect(s2.lapseCount, 0);
      final intervalMs = (const Duration(days: 1).inMilliseconds * 2.5).round();
      expect(s2.nextDueAt, t1.add(Duration(milliseconds: intervalMs)));
    });

    test('subsequent recalls grow geometrically by scaling factor (1.5x)', () {
      var state = ReviewState.initial(decisionId: 'd1');
      var now = t0;
      // Rep 1: 1 day
      state = scheduler.schedule(previous: state, result: ReviewResult.correct, now: now);
      now = state.nextDueAt!;
      // Rep 2: 1 day * 2.5 = 2.5 days (60 hours)
      state = scheduler.schedule(previous: state, result: ReviewResult.correct, now: now);
      now = state.nextDueAt!;
      expect(state.repetitionCount, 2);
      // Rep 3: 2.5 days * 1.5 = 3.75 days (90 hours)
      state = scheduler.schedule(previous: state, result: ReviewResult.correct, now: now);
      now = state.nextDueAt!;
      expect(state.repetitionCount, 3);
      final expectedRep3Ms = (const Duration(hours: 60).inMilliseconds * 1.5).round();
      expect(state.stability, expectedRep3Ms.toDouble());

      // Rep 4: 3.75 days * 1.5 = 5.625 days (135 hours)
      state = scheduler.schedule(previous: state, result: ReviewResult.correct, now: now);
      expect(state.repetitionCount, 4);
      final expectedRep4Ms = (expectedRep3Ms * 1.5).round();
      expect(state.stability, expectedRep4Ms.toDouble());
    });

    test('incorrect recall resets repetitions and records a lapse', () {
      final s0 = ReviewState.initial(decisionId: 'd1');
      final s1 = scheduler.schedule(previous: s0, result: ReviewResult.correct, now: t0);
      final t1 = t0.add(const Duration(days: 1));
      final s2 = scheduler.schedule(previous: s1, result: ReviewResult.incorrect, now: t1);
      expect(s2.repetitionCount, 0);
      expect(s2.lapseCount, 1);
      expect(s2.nextDueAt, t1.add(const Duration(days: 1)));
    });

    test('lapsed item recovers correctly after subsequent correct recall', () {
      var state = ReviewState.initial(decisionId: 'd1');
      var now = t0;
      state = scheduler.schedule(previous: state, result: ReviewResult.correct, now: now);
      now = state.nextDueAt!;
      state = scheduler.schedule(previous: state, result: ReviewResult.incorrect, now: now);
      expect(state.repetitionCount, 0);
      expect(state.lapseCount, 1);

      // Recovery
      now = state.nextDueAt!;
      state = scheduler.schedule(previous: state, result: ReviewResult.correct, now: now);
      expect(state.repetitionCount, 1);
      expect(state.nextDueAt, now.add(const Duration(days: 1)));
    });

    test('interval is clamped at maximumInterval', () {
      const capped = EaseScalingScheduler(
        firstInterval: Duration(days: 1),
        ease: 10.0,
        scaling: 10.0,
        maximumInterval: Duration(days: 14),
      );
      var state = ReviewState.initial(decisionId: 'd1');
      var now = t0;
      for (var i = 0; i < 5; i++) {
        state = capped.schedule(previous: state, result: ReviewResult.correct, now: now);
        now = state.nextDueAt!;
      }
      final interval = state.nextDueAt!.difference(state.lastReviewedAt!);
      expect(interval.inDays, lessThanOrEqualTo(14));
    });

    test('isDue delegates to state.isDueAt', () {
      final sDue = ReviewState(decisionId: 'd1', nextDueAt: t0.subtract(const Duration(hours: 1)));
      final sFuture = ReviewState(decisionId: 'd2', nextDueAt: t0.add(const Duration(hours: 1)));
      expect(scheduler.isDue(sDue, t0), isTrue);
      expect(scheduler.isDue(sFuture, t0), isFalse);
    });

    test('falls back to baseMs when stability is zero for repetitionCount >= 2', () {
      final state = ReviewState(decisionId: 'd1', repetitionCount: 2, stability: 0);
      final sNext = scheduler.schedule(previous: state, result: ReviewResult.correct, now: t0);
      expect(sNext.repetitionCount, 3);
      // baseMs = (1 day * 2.5) = 2.5 days. scaled by 1.5 = 3.75 days (90 hours)
      final expectedMs = (Duration(days: 1).inMilliseconds * 2.5 * 1.5).round();
      expect(sNext.stability, expectedMs.toDouble());
    });

    test('equality and hashCode work correctly', () {
      const s1 = EaseScalingScheduler(ease: 2.5, scaling: 1.5);
      const s2 = EaseScalingScheduler(ease: 2.5, scaling: 1.5);
      const s3 = EaseScalingScheduler(ease: 3.0, scaling: 1.5);
      expect(s1, equals(s2));
      expect(s1.hashCode, equals(s2.hashCode));
      expect(s1, isNot(equals(s3)));
    });
  });

  group('SimpleScheduler equality', () {
    test('equality and hashCode work correctly', () {
      const s1 = SimpleScheduler();
      const s2 = SimpleScheduler();
      const s3 = SimpleScheduler(intervalMultiplier: 3.0);
      expect(s1, equals(s2));
      expect(s1.hashCode, equals(s2.hashCode));
      expect(s1, isNot(equals(s3)));
    });
  });
}
