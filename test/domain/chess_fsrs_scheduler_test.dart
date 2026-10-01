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

    test('hintUsed or multipleAttempts forces Rating.again even when move was correct', () {
      final s0 = ReviewState.initial(decisionId: 'd1');
      final s1 = scheduler.schedule(
        previous: s0,
        result: ReviewResult.correct,
        now: t0,
        hintUsed: true,
      );

      expect(s1.lapseCount, 1); // treated as lapse because recall was not independent
      expect(s1.repetitionCount, 0);
    });

    test('same-day re-review applies damped factor avoiding division blowup', () {
      final s0 = ReviewState.initial(decisionId: 'd1');
      final s1 = scheduler.schedule(previous: s0, result: ReviewResult.correct, now: t0);

      // Same-day review 10 minutes later
      final t1 = t0.add(const Duration(minutes: 10));
      final s2 = scheduler.schedule(previous: s1, result: ReviewResult.correct, now: t1);

      expect(s2.stability, closeTo(s1.stability * 1.02, 100));
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
  });
}
