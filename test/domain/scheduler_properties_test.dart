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
  });
}
