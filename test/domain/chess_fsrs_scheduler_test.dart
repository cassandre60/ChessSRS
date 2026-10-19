// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-024, INV-025, INV-026.

import 'package:chess_srs/src/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 9, 18, 12, 0);

  group('ChessFSRS Math Functions', () {
    test('retrievability is 1.0 at t=0 and exactly 0.9 at t=S', () {
      const s = 10.0; // 10 days stability
      expect(fsrsRetrievability(0.0, s), equals(1.0));
      expect(fsrsRetrievability(s, s), closeTo(0.9, 0.001));
      expect(fsrsRetrievability(s * 2, s), lessThan(0.9));
    });

    test('intervalForTarget produces S days at target retention 90%', () {
      const s = 10.0;
      final intervalAt90 = fsrsIntervalForTarget(s, 0.90);
      expect(intervalAt90, closeTo(s, 0.05));

      // 95% retention requires shorter interval
      final intervalAt95 = fsrsIntervalForTarget(s, 0.95);
      expect(intervalAt95, lessThan(intervalAt90));

      // 80% retention allows longer interval
      final intervalAt80 = fsrsIntervalForTarget(s, 0.80);
      expect(intervalAt80, greaterThan(intervalAt90));
    });

    test('difficulty updates: lapse increases difficulty, success gently mean-reverts', () {
      const p = ChessFsrsParams.chessDefaults();
      final d0Good = fsrsInitialDifficulty(FsrsRating.good, p);
      final d0Again = fsrsInitialDifficulty(FsrsRating.again, p);

      expect(d0Good, closeTo(4.93, 0.01));
      expect(d0Again, greaterThan(d0Good)); // lapses start with higher difficulty

      // Lapse increases difficulty
      final dAfterLapse = fsrsNextDifficulty(d0Good, FsrsRating.again, p);
      expect(dAfterLapse, greaterThan(d0Good));

      // Success slightly mean-reverts
      final dAfterSuccess = fsrsNextDifficulty(dAfterLapse, FsrsRating.good, p);
      expect(dAfterSuccess, lessThanOrEqualTo(dAfterLapse));
    });

    // SPEC INV-025. Zero or negative stability means "no memory": the curve must return 0.0
    // rather than divide by stability (0/0 -> NaN at t=0, and a negative ratio under a
    // fractional exponent is NaN too).
    test('INV-025 retrievability treats zero and negative stability as no memory', () {
      expect(fsrsRetrievability(0.0, 0.0), 0.0);
      expect(fsrsRetrievability(5.0, 0.0), 0.0);
      expect(fsrsRetrievability(0.0, -1.0), 0.0);
      expect(fsrsRetrievability(5.0, -1.0), 0.0);
    });

    // SPEC INV-025. The solver accepts whatever callers pass; for a non-positive stability
    // the linear term turns negative and it must fall back to 0.0 (schedule() then clamps to
    // minIntervalDays) instead of handing back a negative interval.
    test('INV-025 interval solver refuses non-positive stability', () {
      expect(fsrsIntervalForTarget(0.0, 0.90), 0.0);
      expect(fsrsIntervalForTarget(-5.0, 0.90), 0.0);
      expect(fsrsIntervalForTarget(-5.0, 0.99), 0.0);
    });

    // SPEC INV-025. The success update reads s through pow(s, -w9); a zero stability must
    // floor to minStabilityDays or the update computes 0 * Infinity = NaN. Pinned because
    // the guard's direction is the only thing standing between a floored row and a poisoned
    // one.
    test('INV-025 zero stability floors inside the success update', () {
      const p = ChessFsrsParams.chessDefaults();
      final s = fsrsNextStabilitySuccess(4.93, 0.0, 0.9, p);
      expect(s, greaterThan(0));
      expect(s, closeTo(fsrsNextStabilitySuccess(4.93, p.minStabilityDays, 0.9, p), 1e-9));
    });

    // SPEC INV-025. Same floor in the lapse update: with s = 0 the (S+1)^w13 term collapses
    // to 0 and the lapse would return exactly 0.0, i.e. an unlearned item.
    test('INV-025 zero stability floors inside the lapse update', () {
      const p = ChessFsrsParams.chessDefaults();
      final s = fsrsNextStabilityLapse(4.93, 0.0, 0.9, p);
      expect(s, greaterThan(0));
      expect(s, closeTo(fsrsNextStabilityLapse(4.93, p.minStabilityDays, 0.9, p), 1e-12));
    });
  });

  group('ChessFsrsScheduler', () {
    const scheduler = ChessFsrsScheduler(targetRetention: 0.88);

    test('first correct recall on cold start sets initial stability and target interval', () {
      final s0 = ReviewState.initial(decisionId: 'd1');
      final s1 = scheduler.schedule(previous: s0, result: ReviewResult.correct, now: t0);

      expect(s1.repetitionCount, 1);
      expect(s1.lapseCount, 0);
      expect(s1.firstReviewedAt, t0);
      expect(s1.lastReviewedAt, t0);
      expect(s1.stability, closeTo(2.20 * 86400000, 1000)); // w2 days in ms
      expect(s1.difficulty, closeTo(4.93, 0.01));

      // At R=0.88, interval for S=2.2 days is slightly longer than S (~2.6 days)
      final intervalDays = s1.nextDueAt!.difference(t0).inMilliseconds / 86400000;
      expect(intervalDays, greaterThan(2.0));
      expect(intervalDays, lessThan(4.0));
    });

    test('subsequent correct recall grows stability via power-law curve', () {
      final s0 = ReviewState.initial(decisionId: 'd1');
      final s1 = scheduler.schedule(previous: s0, result: ReviewResult.correct, now: t0);

      // Review when due
      final t1 = s1.nextDueAt!;
      final s2 = scheduler.schedule(previous: s1, result: ReviewResult.correct, now: t1);

      expect(s2.repetitionCount, 2);
      expect(s2.lapseCount, 0);
      expect(s2.stability, greaterThan(s1.stability));
      expect(s2.nextDueAt!.isAfter(t1), isTrue);
    });

    test('lapse regresses stability, increases difficulty, and increments lapseCount', () {
      final s0 = ReviewState.initial(decisionId: 'd1');
      final s1 = scheduler.schedule(previous: s0, result: ReviewResult.correct, now: t0);
      final t1 = s1.nextDueAt!;

      final s2 = scheduler.schedule(previous: s1, result: ReviewResult.incorrect, now: t1);

      expect(s2.repetitionCount, 1); // doesn't erase lifetime repetitions
      expect(s2.lapseCount, 1);
      expect(s2.difficulty, greaterThan(s1.difficulty));
      expect(s2.stability, lessThan(s1.stability));
    });

    // SPEC INV-025. Pins a property that is surprising rather than desired: the lapse
    // formula is not monotone in S, so a low-stability item reviewed long past due ends
    // up *more* stable after failing. Inherited from FSRS and specified in §C.6, so it is
    // pinned, not fixed — but a weight retune must not be able to widen the window
    // silently.
    test('INV-025 lapse may exceed prior stability for long-overdue items', () {
      final coldFail = scheduler.schedule(
        previous: ReviewState.initial(decisionId: 'd1'),
        result: ReviewResult.incorrect,
        now: t0,
      );
      // S0(Again) = w0 = 0.35 d; D0(Again) = w4 + 2*w5 = 6.81.
      expect(coldFail.stability, closeTo(0.35 * 86400000, 1000));
      expect(coldFail.difficulty, closeTo(6.81, 0.001));

      // Still regressing while the item is only a little overdue.
      final at3 = scheduler.schedule(
        previous: coldFail,
        result: ReviewResult.incorrect,
        now: t0.add(const Duration(days: 3)),
      );
      expect(at3.stability, lessThan(coldFail.stability));

      // Past the ~3.9 day crossover the formula inverts.
      final at5 = scheduler.schedule(
        previous: coldFail,
        result: ReviewResult.incorrect,
        now: t0.add(const Duration(days: 5)),
      );
      // Second lapse overall: the cold-start Again above was the first.
      expect(at5.lapseCount, 2);
      expect(at5.stability, greaterThan(coldFail.stability));
      expect(at5.stability / coldFail.stability, closeTo(1.059, 0.002));
    });

    test('same-day re-review applies damped factor avoiding division blowup', () {
      final s0 = ReviewState.initial(decisionId: 'd1');
      final s1 = scheduler.schedule(previous: s0, result: ReviewResult.correct, now: t0);

      // Same-day review 10 minutes later
      final t1 = t0.add(const Duration(minutes: 10));
      final s2 = scheduler.schedule(previous: s1, result: ReviewResult.correct, now: t1);

      expect(s2.stability, closeTo(s1.stability * 1.02, 100));
    });

    // SPEC INV-025. Architecture §C.7: a rapid re-review skips the full DSR update, and
    // difficulty is part of that update.
    test('INV-025 rapid re-review freezes difficulty instead of ratcheting it', () {
      final mature = ReviewState(
        decisionId: 'd1',
        stability: 10.0 * 86400000,
        difficulty: 4.93,
        repetitionCount: 3,
        firstReviewedAt: t0.subtract(const Duration(days: 30)),
        lastReviewedAt: t0,
        nextDueAt: t0.add(const Duration(days: 10)),
      );

      // One lapse 5 minutes later: stability still shrinks, but D must not move.
      final afterLapse = scheduler.schedule(
        previous: mature,
        result: ReviewResult.incorrect,
        now: t0.add(const Duration(minutes: 5)),
      );
      expect(afterLapse.lapseCount, 1);
      expect(afterLapse.stability, closeTo(mature.stability * 0.85, 1000));
      expect(afterLapse.difficulty, closeTo(mature.difficulty, 1e-9));

      // A failed decision is re-queued and re-tested in the same session, so three
      // misses inside one session are reachable. They must not push D to the ceiling.
      var state = mature;
      var now = t0;
      for (var i = 0; i < 3; i++) {
        now = now.add(const Duration(minutes: 5));
        state = scheduler.schedule(previous: state, result: ReviewResult.incorrect, now: now);
      }
      expect(state.lapseCount, 3);
      expect(state.difficulty, closeTo(mature.difficulty, 1e-9));
      expect(state.difficulty, lessThan(10.0));

      // A rapid re-review that succeeds must not mean-revert D either — §C.7 skips the
      // whole update, in both directions. Use a D that is not the fixed point of the
      // success update (w7*w4/(1-(1-w7)) == D0(good) == 4.93), or the assertion is vacuous.
      final strained = mature.copyWith(difficulty: 7.0);
      final afterSuccess = scheduler.schedule(
        previous: strained,
        result: ReviewResult.correct,
        now: t0.add(const Duration(minutes: 5)),
      );
      expect(afterSuccess.difficulty, closeTo(7.0, 1e-9));
      expect(afterSuccess.stability, closeTo(mature.stability * 1.02, 1000));
    });

    // SPEC INV-025. The freeze is bounded by sameDayThresholdDays: once the item is
    // genuinely overdue, the full DSR update resumes and D responds to the rating again.
    test('INV-025 difficulty updates resume past the same-day threshold', () {
      final mature = ReviewState(
        decisionId: 'd1',
        stability: 10.0 * 86400000,
        difficulty: 4.93,
        repetitionCount: 3,
        firstReviewedAt: t0.subtract(const Duration(days: 30)),
        lastReviewedAt: t0,
        nextDueAt: t0.add(const Duration(days: 10)),
      );

      final afterLapse = scheduler.schedule(
        previous: mature,
        result: ReviewResult.incorrect,
        now: t0.add(const Duration(days: 10)),
      );
      expect(afterLapse.difficulty, greaterThan(mature.difficulty));
      expect(afterLapse.difficulty, closeTo(7.009, 0.001));
    });

    // SPEC INV-025. The same-day shortcut is bounded to elapsed < sameDayThresholdDays, so
    // exactly one hour of delay is already the overdue regime. A full lapse on a 10-day item
    // cuts stability below half and raises difficulty; the rapid path would only shave 15%
    // and freeze difficulty. Distinguishes the boundary from the rapid side.
    test('INV-025 exactly the same-day threshold gets the full DSR update', () {
      final mature = ReviewState(
        decisionId: 'd1',
        stability: 10.0 * 86400000,
        difficulty: 4.93,
        repetitionCount: 3,
        firstReviewedAt: t0.subtract(const Duration(days: 30)),
        lastReviewedAt: t0,
        nextDueAt: t0.add(const Duration(days: 10)),
      );

      final afterLapse = scheduler.schedule(
        previous: mature,
        result: ReviewResult.incorrect,
        now: t0.add(const Duration(minutes: 60)),
      );
      expect(afterLapse.stability, lessThan(mature.stability * 0.5));
      expect(afterLapse.difficulty, greaterThan(mature.difficulty));
    });

    test('tournament mode target retention produces tighter review intervals', () {
      const normalScheduler = ChessFsrsScheduler(targetRetention: 0.88);
      const tournamentScheduler = ChessFsrsScheduler(targetRetention: 0.95);

      final s0 = ReviewState.initial(decisionId: 'd1');
      final sNormal = normalScheduler.schedule(previous: s0, result: ReviewResult.correct, now: t0);
      final sTournament = tournamentScheduler.schedule(
        previous: s0,
        result: ReviewResult.correct,
        now: t0,
      );

      // Tournament mode requires 95% retention, so interval must be shorter
      final normalInterval = sNormal.nextDueAt!.difference(t0);
      final tournamentInterval = sTournament.nextDueAt!.difference(t0);

      expect(tournamentInterval.inHours, lessThan(normalInterval.inHours));
    });

    test('fsrsIntervalProgressionPreview generates monotonically growing intervals', () {
      final intervals90 = fsrsIntervalProgressionPreview(targetRetention: 0.90);
      expect(intervals90.length, 5);
      for (var i = 1; i < intervals90.length; i++) {
        expect(intervals90[i], greaterThan(intervals90[i - 1]));
      }

      final intervals95 = fsrsIntervalProgressionPreview(targetRetention: 0.95);
      expect(intervals95.length, 5);
      // Higher target retention produces shorter intervals for equal stability
      expect(intervals95[0], lessThan(intervals90[0]));
    });

    // SPEC INV-026. The preview must not advertise intervals the scheduler would
    // never emit. It used to skip maxIntervalDays, so a 10-step ladder ran away to
    // 1697 days at step 6 and past 14000 by step 9 while the scheduler capped at 1095.
    test('INV-026 interval preview respects the cap and tracks the scheduler', () {
      const capped = ChessFsrsScheduler(targetRetention: 0.88);
      final preview = fsrsIntervalProgressionPreview(targetRetention: 0.88, steps: 10);

      expect(preview.length, 10);
      for (final interval in preview) {
        expect(interval, lessThanOrEqualTo(365 * 3.0));
      }

      // Replay the real scheduler over the same run of clean successes. Tolerance is
      // the accumulated millisecond rounding of nextDueAt across the replay.
      var state = ReviewState.initial(decisionId: 'd1');
      var now = t0;
      for (var i = 0; i < preview.length; i++) {
        state = capped.schedule(previous: state, result: ReviewResult.correct, now: now);
        final scheduledDays = state.nextDueAt!.difference(now).inMilliseconds / 86400000;
        expect(scheduledDays, closeTo(preview[i], 1e-5));
        now = state.nextDueAt!;
      }

      expect(fsrsIntervalProgressionPreview(targetRetention: 0.88, steps: 0), isEmpty);
      expect(fsrsIntervalProgressionPreview(targetRetention: 0.88, steps: -3), isEmpty);
    });

    test('schedulers differing only in params compare unequal', () {
      const base = ChessFsrsScheduler(targetRetention: 0.88);
      const tuned = ChessFsrsScheduler(targetRetention: 0.88, params: ChessFsrsParams(w2: 3.5));
      // The provider reload gate depends on this: a params change must fire it.
      expect(base == tuned, isFalse);
      expect(base.hashCode == tuned.hashCode, isFalse);
      expect(base == const ChessFsrsScheduler(targetRetention: 0.88), isTrue);
    });

    test('params with identical values compare equal', () {
      const a = ChessFsrsParams(w2: 2.2);
      const b = ChessFsrsParams(w2: 2.2);
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    // SPEC INV-026. The test above is vacuous for the field chain: two `const` expressions
    // with identical arguments are canonicalized to one instance, so `identical(this, other)`
    // short-circuits and no field comparison runs. Build both sides at runtime (distinct
    // instances, equal values) so the chain is what decides equality — this is the case the
    // provider reload gate actually depends on, since a settings change always arrives as a
    // new instance.
    test('INV-026 runtime-equal params compare by value, not identity', () {
      // Constructed through a helper so the arguments are runtime values: literal-only
      // invocations would be constant expressions, and Dart would canonicalize them into a
      // single instance again — reintroducing the very blind spot this test closes.
      ChessFsrsParams params(double w2, double w8) => ChessFsrsParams(w2: w2, w8: w8);
      final a = params(22 / 10, 149 / 100);
      final b = params(44 / 20, 298 / 200);
      expect(identical(a, b), isFalse);
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    // SPEC INV-026. Same canonicalization, same stakes for the scheduler itself: a target
    // retention or cap change arrives as a new instance, never as the same object.
    test('INV-026 runtime-equal schedulers compare by value, not identity', () {
      ChessFsrsScheduler withCaps(double retention, double maxDays) =>
          ChessFsrsScheduler(targetRetention: retention, maxIntervalDays: maxDays);
      final a = withCaps(88 / 100, 2190 / 2);
      final b = withCaps(176 / 200, 4380 / 4);
      expect(identical(a, b), isFalse);
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    // A stability that has decayed to a sub-millisecond positive value — reachable through
    // repeated lapse contagion, which multiplies stability by a factor clamped to [0, 1] but
    // never reaching exactly zero — must still schedule as a reviewable interval rather than
    // collapsing to nothing and re-presenting the position indefinitely. The input is deliberately
    // *not* floored (it is only used for the retrievability curve, which is smooth there); the
    // guarantee is on the output, which is clamped unconditionally in schedule(). Pinning it
    // because that clamp is the only thing standing between a retune and a collapsed interval.
    test('a sub-millisecond stability still schedules a real interval', () {
      const params = ChessFsrsParams.chessDefaults();
      const scheduler = ChessFsrsScheduler(params: params, targetRetention: 0.90);

      for (final stability in [1e-4, 0.01, 0.5, 1.0]) {
        final scheduled = scheduler.schedule(
          previous: ReviewState(
            decisionId: 'd',
            stability: stability,
            difficulty: 5.0,
            repetitionCount: 3,
            lastReviewedAt: t0.subtract(const Duration(days: 10)),
            nextDueAt: t0,
          ),
          result: ReviewResult.correct,
          now: t0,
        );

        expect(
          scheduled.stability,
          closeTo(params.minStabilityDays * 86400000.0, 1.0),
          reason: 'stability $stability must floor to minStabilityDays, not collapse',
        );
        expect(
          scheduled.nextDueAt!.isAfter(t0),
          isTrue,
          reason: 'stability $stability must still come back later, not immediately',
        );
      }
    });

    // SPEC INV-025. A row that has repetitions but a zeroed stability (bad import, foreign
    // state) must schedule exactly as if its stability were minStabilityDays: the floor in
    // schedule() feeds the same number the curve would, keeping the retrievability argument
    // positive. Without that outer floor the curve is evaluated at S = 0 and the row
    // overshoots this answer.
    test('INV-025 a zero stability on a learned row schedules as minStabilityDays', () {
      const params = ChessFsrsParams.chessDefaults();
      const scheduler = ChessFsrsScheduler(params: params, targetRetention: 0.90);
      final zeroed = ReviewState(
        decisionId: 'd',
        stability: 0.0,
        difficulty: 5.0,
        repetitionCount: 3,
        lastReviewedAt: t0.subtract(const Duration(days: 10)),
        nextDueAt: t0,
      );
      final floored = zeroed.copyWith(stability: params.minStabilityDays * 86400000.0);

      final fromZero = scheduler.schedule(previous: zeroed, result: ReviewResult.correct, now: t0);
      final fromFloor = scheduler.schedule(
        previous: floored,
        result: ReviewResult.correct,
        now: t0,
      );

      expect(fromZero.stability, closeTo(fromFloor.stability, 1000));
      expect(fromZero.difficulty, closeTo(fromFloor.difficulty, 1e-9));
    });

    // SPEC INV-025. Same fallback for a zeroed difficulty: schedule() substitutes the initial
    // good difficulty instead of running the update from 0.0, which mean-reverts to the 1.0
    // clamp and takes hundreds of reviews to unwind.
    test('INV-025 a zero difficulty on a learned row schedules as initial good difficulty', () {
      const params = ChessFsrsParams.chessDefaults();
      const scheduler = ChessFsrsScheduler(params: params, targetRetention: 0.90);
      final zeroed = ReviewState(
        decisionId: 'd',
        stability: 5.0 * 86400000,
        difficulty: 0.0,
        repetitionCount: 3,
        lastReviewedAt: t0.subtract(const Duration(days: 10)),
        nextDueAt: t0,
      );
      final reference = zeroed.copyWith(difficulty: fsrsInitialDifficulty(FsrsRating.good, params));

      final fromZero = scheduler.schedule(previous: zeroed, result: ReviewResult.correct, now: t0);
      final fromReference = scheduler.schedule(
        previous: reference,
        result: ReviewResult.correct,
        now: t0,
      );

      expect(fromZero.difficulty, closeTo(fromReference.difficulty, 1e-9));
    });
  });
}
