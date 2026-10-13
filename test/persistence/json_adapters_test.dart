// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('review state JSON round-trip', () {
    test('timestamps are UTC so a timezone change cannot shift due dates', () {
      // review-4 C2 / QUALITY §3.2: stored instants are absolute (UTC `Z`),
      // not local wall times, so a device zone change cannot shift them.
      final localDue = DateTime(2026, 10, 8, 10);
      final state = ReviewState(
        decisionId: 'r-utc',
        firstReviewedAt: localDue,
        lastReviewedAt: localDue,
        nextDueAt: localDue,
        repetitionCount: 2,
      );

      final json = reviewStateToJson(state);
      expect(json['firstReviewedAt'] as String, endsWith('Z'));
      expect(json['lastReviewedAt'] as String, endsWith('Z'));
      expect(json['nextDueAt'] as String, endsWith('Z'));

      final read = reviewStateFromJson(json);
      expect(read.firstReviewedAt!.isUtc, isTrue);
      expect(read.nextDueAt!.toUtc().toIso8601String(), localDue.toUtc().toIso8601String());
    });

    test('review event when is UTC', () {
      final localWhen = DateTime(2026, 10, 8, 10);
      const state = ReviewState(decisionId: 'e-utc');
      final event = ReviewEvent(
        decisionId: 'e-utc',
        when: localWhen,
        result: ReviewResult.correct,
        oldState: state,
        newState: state,
      );

      final json = reviewEventToJson(event);
      expect(json['when'] as String, endsWith('Z'));

      final read = reviewEventFromJson(json);
      expect(read.when.toUtc().toIso8601String(), localWhen.toUtc().toIso8601String());
      expect(read.when.isUtc, isTrue);
    });
  });
}
