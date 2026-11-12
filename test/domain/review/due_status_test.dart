// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/review/due_status.dart';
import 'package:chess_srs/src/domain/review_state.dart';
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
      final status = dueStatusOf(stateDueAt(null, repetitions: 0), now);

      expect(status, DueStatus.due);
    });
  });
}
