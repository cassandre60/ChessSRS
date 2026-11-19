// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-024, INV-025, INV-026, INV-030.

import 'dart:math';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final baseTime = DateTime.utc(2026, 1, 1, 12);

  // Property: repeated correct recalls produce non-decreasing intervals
  // (capped at maximumInterval). Catches cap-removal mutants.
  group('scheduler properties (property)', () {
    test('INV-025/026 monotonic growth on repeated correct (Simple)', () {
      const scheduler = SimpleScheduler(
        firstInterval: Duration(days: 1),
        baseInterval: Duration(days: 2),
        intervalMultiplier: 2.0,
        maximumInterval: Duration(days: 30),
      );
      for (var seed = 0; seed < 25; seed++) {
        var state = ReviewState.initial(decisionId: 'p-$seed');
        var now = baseTime.add(Duration(days: seed));
        Duration? prevInterval;
        for (var i = 0; i < 8; i++) {
          final next = scheduler.schedule(previous: state, result: ReviewResult.correct, now: now);
          // INV-024 deterministic: same input yields same output
          final replay = scheduler.schedule(
            previous: state,
            result: ReviewResult.correct,
            now: now,
          );
          expect(replay, equals(next), reason: 'schedule must be pure (seed $seed step $i)');

          final interval = next.nextDueAt!.difference(now);
          expect(interval.inMilliseconds, greaterThan(0), reason: 'interval must be positive');
          expect(
            interval.inMilliseconds,
            lessThanOrEqualTo(scheduler.maximumInterval.inMilliseconds),
            reason: 'INV-026 cap breached (seed $seed step $i)',
          );
          if (prevInterval != null) {
            // Once capped, further growth stays at cap; otherwise non-decreasing
            final capped = prevInterval.inMilliseconds == scheduler.maximumInterval.inMilliseconds;
            if (!capped) {
              expect(
                interval.inMilliseconds,
                greaterThanOrEqualTo(prevInterval.inMilliseconds),
                reason: 'interval must not shrink on correct (seed $seed step $i)',
              );
            } else {
              expect(interval.inMilliseconds, equals(scheduler.maximumInterval.inMilliseconds));
            }
          }
          prevInterval = interval;
          expect(next.repetitionCount, equals(state.repetitionCount + 1));
          expect(next.lapseCount, equals(state.lapseCount));
          state = next;
          now = next.nextDueAt!;
        }
      }
    });

    test('INV-025 lapse resets repetition and records exactly one lapse', () {
      const scheduler = SimpleScheduler();
      final rng = Random(42);
      for (var i = 0; i < 50; i++) {
        // Build a random learned state (1..5 correct recalls)
        var state = ReviewState.initial(decisionId: 'l-$i');
        var now = baseTime;
        final reps = 1 + rng.nextInt(5);
        for (var r = 0; r < reps; r++) {
          state = scheduler.schedule(previous: state, result: ReviewResult.correct, now: now);
          now = state.nextDueAt!;
        }
        final beforeReps = state.repetitionCount;
        final beforeLapses = state.lapseCount;
        now = now.add(const Duration(days: 1));
        final after = scheduler.schedule(previous: state, result: ReviewResult.incorrect, now: now);
        expect(after.repetitionCount, equals(0), reason: 'lapse must reset reps (case $i)');
        expect(after.lapseCount, equals(beforeLapses + 1), reason: 'lapse must add exactly 1');
        expect(
          after.lapseCount,
          isNot(equals(beforeLapses + 2)),
          reason: 'double-count mutant must be caught',
        );
        expect(beforeReps, greaterThan(0));
        expect(after.nextDueAt, equals(now.add(scheduler.firstInterval)));
        expect(after.stability, equals(scheduler.firstInterval.inMilliseconds.toDouble()));
      }
    });

    test('INV-030 dueItems partition is disjoint and complete', () {
      final clock = FixedClock(baseTime);
      final rng = Random(99);
      for (var trial = 0; trial < 20; trial++) {
        final states = List.generate(30, (i) {
          final offsetDays = rng.nextInt(21) - 10; // -10..+10
          final rep = rng.nextInt(4);
          return ReviewState(
            decisionId: 's-$trial-$i',
            nextDueAt: offsetDays == 0 && rep == 0
                ? null
                : baseTime.add(Duration(days: offsetDays)),
            repetitionCount: rep,
          );
        });
        final due = dueItems(states, clock);
        final dueIds = due.map((s) => s.decisionId).toSet();
        final allIds = states.map((s) => s.decisionId).toSet();

        // No due item is missing from all, and due is subset of all
        expect(dueIds.difference(allIds), isEmpty);
        // Due and not-due are disjoint
        final notDueIds = allIds.difference(dueIds);
        expect(dueIds.intersection(notDueIds), isEmpty);
        // Union covers all
        expect(dueIds.length + notDueIds.length, equals(allIds.length));
        // Each due satisfies isDueAt, each not-due does not
        for (final s in due) {
          expect(s.isDueAt(clock.now()), isTrue, reason: '${s.decisionId} in due but not due');
        }
        for (final s in states.where((s) => !dueIds.contains(s.decisionId))) {
          expect(s.isDueAt(clock.now()), isFalse, reason: '${s.decisionId} not in due but due');
        }

        // Negation mutant: flipping the predicate would invert the partition.
        // The complement has size `all - due`. We assert that so a negated
        // `dueItems` predicate (returning not-due) would be caught by the
        // expect on `due.length` itself. The sizes can be equal when exactly
        // half the items are due, so no `isNot(equals)` assertion here.
        final inverted = states.where((s) => !s.isDueAt(clock.now())).toList();
        expect(inverted.length, equals(states.length - due.length));
      }
    });

    test('INV-025 EaseScaling second interval equals firstInterval * ease', () {
      const first = Duration(days: 1);
      const ease = 2.5;
      const scheduler = EaseScalingScheduler(firstInterval: first, ease: ease, scaling: 1.5);
      final s0 = ReviewState.initial(decisionId: 'e');
      final s1 = scheduler.schedule(previous: s0, result: ReviewResult.correct, now: baseTime);
      final s2 = scheduler.schedule(previous: s1, result: ReviewResult.correct, now: s1.nextDueAt!);
      final expectedMs = (first.inMilliseconds * ease).round();
      expect(s2.nextDueAt!.difference(s1.nextDueAt!).inMilliseconds, equals(expectedMs));
      // Off-by-one mutant: if first-recall branch checked rep==1 instead of 0,
      // the first interval would be ease-scaled rather than firstInterval
      expect(s1.nextDueAt!.difference(baseTime).inMilliseconds, equals(first.inMilliseconds));
    });

    test('INV-024 schedule is pure: wall-clock never consulted', () {
      const scheduler = SimpleScheduler();
      const state = ReviewState(decisionId: 'pure', repetitionCount: 2, stability: 172800000.0);
      final t = DateTime.utc(2026, 6, 15, 9, 30);
      final a = scheduler.schedule(previous: state, result: ReviewResult.correct, now: t);
      final b = scheduler.schedule(previous: state, result: ReviewResult.correct, now: t);
      expect(a, equals(b));
      // Different now yields different nextDueAt but same relative interval
      final t2 = t.add(const Duration(days: 10));
      final c = scheduler.schedule(previous: state, result: ReviewResult.correct, now: t2);
      expect(c.nextDueAt!.difference(t2), equals(a.nextDueAt!.difference(t)));
    });

    test(
      'INV-024/025/026 EaseScalingScheduler monotonic growth, cap, and lapse reset across random parameter spaces',
      () {
        // SPEC INV-024.
        // SPEC INV-025.
        // SPEC INV-026.
        final rng = Random(202601);
        for (var trial = 0; trial < 40; trial++) {
          final firstHours = 6 + rng.nextInt(48);
          final ease = 1.2 + rng.nextDouble() * 2.5;
          final scaling = 1.1 + rng.nextDouble() * 2.0;
          final maxDays = 10 + rng.nextInt(300);
          final scheduler = EaseScalingScheduler(
            firstInterval: Duration(hours: firstHours),
            ease: ease,
            scaling: scaling,
            maximumInterval: Duration(days: maxDays),
          );

          var state = ReviewState.initial(decisionId: 'ease-$trial');
          var now = baseTime.add(Duration(hours: trial));
          Duration? prevInterval;

          for (var step = 0; step < 10; step++) {
            final next = scheduler.schedule(
              previous: state,
              result: ReviewResult.correct,
              now: now,
            );
            final replay = scheduler.schedule(
              previous: state,
              result: ReviewResult.correct,
              now: now,
            );
            expect(replay, equals(next), reason: 'INV-024 deterministic (trial $trial step $step)');

            final interval = next.nextDueAt!.difference(now);
            expect(interval.inMilliseconds, greaterThan(0));
            expect(
              interval.inMilliseconds,
              lessThanOrEqualTo(scheduler.maximumInterval.inMilliseconds),
              reason: 'INV-026 cap respected (trial $trial step $step)',
            );
            if (prevInterval != null) {
              expect(
                interval.inMilliseconds,
                greaterThanOrEqualTo(prevInterval.inMilliseconds),
                reason: 'INV-025 monotonic growth (trial $trial step $step)',
              );
            }
            prevInterval = interval;
            expect(next.repetitionCount, equals(state.repetitionCount + 1));
            state = next;
            now = next.nextDueAt!;
          }

          // Lapse resets repetitionCount to 0 and clamps retry interval to maximumInterval
          final lapsed = scheduler.schedule(
            previous: state,
            result: ReviewResult.incorrect,
            now: now,
          );
          expect(lapsed.repetitionCount, equals(0));
          expect(lapsed.lapseCount, equals(state.lapseCount + 1));
          final retryInterval = lapsed.nextDueAt!.difference(now);
          expect(
            retryInterval.inMilliseconds,
            lessThanOrEqualTo(scheduler.maximumInterval.inMilliseconds),
          );
        }
      },
    );

    test(
      'INV-024/025/026 ChessFsrsScheduler targetRetention clamping, DSR bounds, and rapid re-review guard',
      () {
        // SPEC INV-024.
        // SPEC INV-025.
        // SPEC INV-026.
        final rng = Random(202602);
        const dayMs = 86400000;

        // 1. Target retention clamping outside [0.70, 0.99]
        const belowMin = ChessFsrsScheduler(targetRetention: 0.50);
        const atMin = ChessFsrsScheduler(targetRetention: kMinTargetRetention);
        const aboveMax = ChessFsrsScheduler(targetRetention: 1.05);
        const atMax = ChessFsrsScheduler(targetRetention: kMaxTargetRetention);

        final cold = ReviewState.initial(decisionId: 'clamp-check');
        expect(
          belowMin.schedule(previous: cold, result: ReviewResult.correct, now: baseTime),
          equals(atMin.schedule(previous: cold, result: ReviewResult.correct, now: baseTime)),
          reason: 'targetRetention < 0.70 must clamp to kMinTargetRetention',
        );
        expect(
          aboveMax.schedule(previous: cold, result: ReviewResult.correct, now: baseTime),
          equals(atMax.schedule(previous: cold, result: ReviewResult.correct, now: baseTime)),
          reason: 'targetRetention > 0.99 must clamp to kMaxTargetRetention',
        );

        // 2. Random FSRS trajectories across varying target retentions
        for (var trial = 0; trial < 50; trial++) {
          final retention = 0.55 + rng.nextDouble() * 0.50; // spans [0.55, 1.05]
          final maxDays = 60.0 + rng.nextInt(1000);
          final scheduler = ChessFsrsScheduler(
            targetRetention: retention,
            maxIntervalDays: maxDays,
          );

          var state = ReviewState.initial(decisionId: 'fsrs-$trial');
          var now = baseTime;

          for (var step = 0; step < 12; step++) {
            final isCorrect = step == 0 || rng.nextDouble() > 0.25;
            final result = isCorrect ? ReviewResult.correct : ReviewResult.incorrect;
            final next = scheduler.schedule(previous: state, result: result, now: now);
            final replay = scheduler.schedule(previous: state, result: result, now: now);
            expect(replay, equals(next), reason: 'INV-024 pure FSRS schedule');

            // Difficulty bounded in [1.0, 10.0]
            expect(next.difficulty, inInclusiveRange(1.0, 10.0));
            // Stability bounded in [minStabilityDays, maxStabilityDays]
            final stabilityDays = next.stability / dayMs;
            expect(
              stabilityDays,
              inInclusiveRange(
                scheduler.params.minStabilityDays - 1e-9,
                scheduler.params.maxStabilityDays + 1e-9,
              ),
            );
            // Interval bounded in [minIntervalDays, maxIntervalDays] (INV-026)
            final intervalMs = next.nextDueAt!.difference(now).inMilliseconds;
            expect(intervalMs, greaterThanOrEqualTo((scheduler.minIntervalDays * dayMs).round()));
            expect(intervalMs, lessThanOrEqualTo((scheduler.maxIntervalDays * dayMs).round()));

            if (isCorrect) {
              expect(next.repetitionCount, equals(state.repetitionCount + 1));
              expect(next.lapseCount, equals(state.lapseCount));
            } else {
              // ChessFSRS preserves repetitionCount and increments lapseCount
              expect(next.repetitionCount, equals(state.repetitionCount));
              expect(next.lapseCount, equals(state.lapseCount + 1));
            }

            state = next;
            // Advance either rapidly (<1h) or normally (>=1d)
            if (rng.nextInt(4) == 0) {
              final rapidNow = now.add(Duration(minutes: 5 + rng.nextInt(40)));
              final rapidRes = rng.nextBool() ? ReviewResult.correct : ReviewResult.incorrect;
              final afterRapid = scheduler.schedule(
                previous: state,
                result: rapidRes,
                now: rapidNow,
              );
              // Rapid re-review (<1h) freezes difficulty and applies sameDayGainFactor / sameDayLapseFactor
              expect(
                afterRapid.difficulty,
                equals(state.difficulty),
                reason: 'rapid re-review must freeze difficulty',
              );
              final expectedFactor = rapidRes == ReviewResult.correct
                  ? scheduler.params.sameDayGainFactor
                  : scheduler.params.sameDayLapseFactor;
              final expectedStabilityDays = ((state.stability / dayMs) * expectedFactor).clamp(
                scheduler.params.minStabilityDays,
                scheduler.params.maxStabilityDays,
              );
              expect(afterRapid.stability / dayMs, closeTo(expectedStabilityDays, 1e-6));
              state = afterRapid;
              now = state.nextDueAt!;
            } else {
              now = state.nextDueAt!;
            }
          }
        }

        // 3. Higher target retention produces shorter or equal intervals for identical state
        final learnedState = const ChessFsrsScheduler().schedule(
          previous: cold,
          result: ReviewResult.correct,
          now: baseTime,
        );
        final reviewTime = baseTime.add(const Duration(days: 3));
        final lowRetDue = const ChessFsrsScheduler(targetRetention: 0.75)
            .schedule(previous: learnedState, result: ReviewResult.correct, now: reviewTime)
            .nextDueAt!;
        final highRetDue = const ChessFsrsScheduler(targetRetention: 0.95)
            .schedule(previous: learnedState, result: ReviewResult.correct, now: reviewTime)
            .nextDueAt!;
        expect(
          highRetDue.isBefore(lowRetDue) || highRetDue.isAtSameMomentAs(lowRetDue),
          isTrue,
          reason: 'higher target retention requires reviewing sooner',
        );
      },
    );
  });
}
