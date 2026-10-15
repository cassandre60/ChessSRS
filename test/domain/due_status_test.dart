// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 15, 12);

  ReviewState stateDueAt(DateTime? nextDueAt, {int repetitions = 1}) => ReviewState(
    decisionId: 'd1',
    nextDueAt: nextDueAt,
    repetitionCount: repetitions,
    firstReviewedAt: DateTime.utc(2026, 10, 1),
  );

  group('dueStatusOf', () {
    // SPEC INV-068. The reported defect: a bulk import writes no review state,
    // and "no record" used to classify every position as due.
    test('a position with no review state is fresh, never due', () {
      final status = dueStatusOf(null, now);

      expect(status, DueStatus.fresh);
      expect(status.isDue, isFalse);
      expect(status.isFresh, isTrue);
    });

    test('a state whose scheduled date has passed is due', () {
      final status = dueStatusOf(stateDueAt(now.subtract(const Duration(hours: 1))), now);

      expect(status, DueStatus.due);
      expect(status.isDue, isTrue);
      expect(status.isFresh, isFalse);
    });

    test('a state due exactly now is due, not scheduled', () {
      expect(dueStatusOf(stateDueAt(now), now), DueStatus.due);
    });

    test('a state whose scheduled date is still ahead is scheduled', () {
      final status = dueStatusOf(stateDueAt(now.add(const Duration(days: 1))), now);

      expect(status, DueStatus.scheduled);
      expect(status.isDue, isFalse);
      expect(status.isFresh, isFalse);
    });

    test('a state with no scheduled date is due, because it was presented', () {
      // The row exists, so the position has been put in front of the user at
      // least once. Deliberately not fresh: a traversal-only write must not
      // put the position back in the introduction queue forever.
      final status = dueStatusOf(stateDueAt(null, repetitions: 0), now);

      expect(status, DueStatus.due);
    });

    test('a lapsed position is due while still unlearned', () {
      // repetitionCount 0 with a real date: shown, missed, scheduled to return.
      final lapsed = ReviewState(
        decisionId: 'd1',
        nextDueAt: now.subtract(const Duration(minutes: 5)),
        repetitionCount: 0,
        lapseCount: 2,
        firstReviewedAt: DateTime.utc(2026, 10, 1),
      );

      expect(dueStatusOf(lapsed, now), DueStatus.due);
    });
  });

  group('RepertoireProgress partitions its positions', () {
    // SPEC INV-068. Before it, the three memory-bar segments were computed as
    // retained/learning/new from `learned` and `due`, which double-counted every
    // due-but-unlearned position.
    test('fresh, due and scheduled sum to the total', () {
      const p = RepertoireProgress(
        totalDecisions: 100,
        learnedDecisions: 20,
        dueDecisions: 15,
        freshDecisions: 60,
      );

      expect(p.scheduledDecisions, 25);
      expect(p.freshDecisions + p.dueDecisions + p.scheduledDecisions, p.totalDecisions);
    });

    test('a freshly imported scope is all fresh and nothing due', () {
      const p = RepertoireProgress(
        totalDecisions: 5310,
        learnedDecisions: 0,
        dueDecisions: 0,
        freshDecisions: 5310,
      );

      expect(p.scheduledDecisions, 0);
      expect(p.progressFraction, 0.0);
    });

    test('scheduled never goes negative when due and fresh overlap the total', () {
      const p = RepertoireProgress(
        totalDecisions: 10,
        learnedDecisions: 10,
        dueDecisions: 10,
        freshDecisions: 10,
      );

      expect(p.scheduledDecisions, 0);
    });
  });
}
