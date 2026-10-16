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

  group('expected moves serialization', () {
    test('decodeExpectedMoves decodes single move with fast path and round trips', () {
      const moves = [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')];
      final encoded = encodeExpectedMoves(moves);
      expect(encoded, '[{"from":"e2","to":"e4","san":"e4"}]');

      final decoded = decodeExpectedMoves(encoded);
      expect(decoded.length, 1);
      expect(decoded.first.from, 'e2');
      expect(decoded.first.to, 'e4');
      expect(decoded.first.san, 'e4');
      expect(decoded.first.promotion, isNull);
    });

    test('decodeExpectedMoves decodes moves with promotions and multiple moves', () {
      const promoMoves = [RepertoireMove(from: 'e7', to: 'e8', promotion: 'q', san: 'e8=Q')];
      final encodedPromo = encodeExpectedMoves(promoMoves);
      final decodedPromo = decodeExpectedMoves(encodedPromo);
      expect(decodedPromo.length, 1);
      expect(decodedPromo.first.from, 'e7');
      expect(decodedPromo.first.to, 'e8');
      expect(decodedPromo.first.promotion, 'q');
      expect(decodedPromo.first.san, 'e8=Q');

      const multiMoves = [
        RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3'),
        RepertoireMove(from: 'd2', to: 'd4', san: 'd4'),
      ];
      final encodedMulti = encodeExpectedMoves(multiMoves);
      final decodedMulti = decodeExpectedMoves(encodedMulti);
      expect(decodedMulti.length, 2);
      expect(decodedMulti[0].san, 'Nf3');
      expect(decodedMulti[1].san, 'd4');
    });
  });
}
