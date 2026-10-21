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

    test('all review state fields round-trip with defaults for missing numeric fields', () {
      final now = DateTime(2026, 10, 20, 14, 30).toUtc();
      final state = ReviewState(
        decisionId: 'dec-full',
        firstReviewedAt: now,
        lastReviewedAt: now,
        nextDueAt: now.add(const Duration(days: 3)),
        repetitionCount: 4,
        lapseCount: 1,
        stability: 3.5,
        difficulty: 6.2,
      );

      final json = reviewStateToJson(state);
      expect(json['decisionId'], 'dec-full');
      expect(json['repetitionCount'], 4);
      expect(json['lapseCount'], 1);
      expect(json['stability'], 3.5);
      expect(json['difficulty'], 6.2);

      final read = reviewStateFromJson(json);
      expect(read.decisionId, 'dec-full');
      expect(read.firstReviewedAt, now);
      expect(read.lastReviewedAt, now);
      expect(read.nextDueAt, now.add(const Duration(days: 3)));
      expect(read.repetitionCount, 4);
      expect(read.lapseCount, 1);
      expect(read.stability, 3.5);
      expect(read.difficulty, 6.2);

      // Defaults when numeric fields are null in json
      final minimalRead = reviewStateFromJson({'decisionId': 'dec-min'});
      expect(minimalRead.decisionId, 'dec-min');
      expect(minimalRead.firstReviewedAt, isNull);
      expect(minimalRead.lastReviewedAt, isNull);
      expect(minimalRead.nextDueAt, isNull);
      expect(minimalRead.repetitionCount, 0);
      expect(minimalRead.lapseCount, 0);
      expect(minimalRead.stability, 0.0);
      expect(minimalRead.difficulty, 5.0);
    });

    test('review event all fields round-trip', () {
      final localWhen = DateTime(2026, 10, 8, 10);
      const oldState = ReviewState(decisionId: 'e-utc', repetitionCount: 1);
      const newState = ReviewState(decisionId: 'e-utc', repetitionCount: 2);
      final event = ReviewEvent(
        decisionId: 'e-utc',
        when: localWhen,
        result: ReviewResult.correct,
        oldState: oldState,
        newState: newState,
      );

      final json = reviewEventToJson(event);
      expect(json['when'] as String, endsWith('Z'));
      expect(json['decisionId'], 'e-utc');
      expect(json['result'], 'correct');

      final read = reviewEventFromJson(json);
      expect(read.decisionId, 'e-utc');
      expect(read.when.toUtc().toIso8601String(), localWhen.toUtc().toIso8601String());
      expect(read.when.isUtc, isTrue);
      expect(read.result, ReviewResult.correct);
      expect(read.oldState.repetitionCount, 1);
      expect(read.newState.repetitionCount, 2);
    });
  });

  group('repertoire node serialization', () {
    test(
      'INV-010: repertoireNodeToJson and fromJson preserve tree structure, comments and variations',
      () {
        // SPEC INV-010: variation preservation — multiple children are first-class
        // siblings and must never be flattened or dropped during serialization.
        const root = RepertoireNode(
          id: 'node-root',
          fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
          fenKey: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
          comment: 'Starting position',
          children: [
            RepertoireNode(
              id: 'node-e4',
              fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
              fenKey: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3',
              incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
              comment: 'Mainline e4',
            ),
            RepertoireNode(
              id: 'node-d4',
              fen: 'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq d3 0 1',
              fenKey: 'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq d3',
              incomingMove: RepertoireMove(from: 'd2', to: 'd4', san: 'd4'),
            ),
          ],
        );

        final json = repertoireNodeToJson(root);
        expect(json['id'], 'node-root');
        expect(json['comment'], 'Starting position');
        expect(json['incomingMove'], isNull);
        final rawChildren = json['children'] as List<dynamic>;
        expect(rawChildren.length, 2);

        final firstChildJson = rawChildren[0] as Map<String, dynamic>;
        expect(firstChildJson['incomingMove'], isNotNull);
        final firstIncoming = firstChildJson['incomingMove'] as Map<String, dynamic>;
        expect(firstIncoming['san'], 'e4');
        expect(firstChildJson['comment'], 'Mainline e4');
        expect(firstChildJson.containsKey('children'), isFalse);

        final decoded = repertoireNodeFromJson(json);
        expect(decoded.id, 'node-root');
        expect(decoded.fen, root.fen);
        expect(decoded.fenKey, root.fenKey);
        expect(decoded.comment, 'Starting position');
        expect(decoded.incomingMove, isNull);
        expect(decoded.children.length, 2);

        final c0 = decoded.children[0];
        expect(c0.id, 'node-e4');
        expect(c0.incomingMove, isNotNull);
        expect(c0.incomingMove!.from, 'e2');
        expect(c0.incomingMove!.to, 'e4');
        expect(c0.incomingMove!.san, 'e4');
        expect(c0.comment, 'Mainline e4');
        expect(c0.children, isEmpty);

        final c1 = decoded.children[1];
        expect(c1.id, 'node-d4');
        expect(c1.incomingMove!.san, 'd4');
        expect(c1.comment, isNull);
        expect(c1.children, isEmpty);
      },
    );
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

    test('decodeExpectedMoves handles move with null SAN', () {
      const moveNoSan = RepertoireMove(from: 'e2', to: 'e4');
      final encoded = encodeExpectedMoves([moveNoSan]);
      final decoded = decodeExpectedMoves(encoded);
      expect(decoded.length, 1);
      expect(decoded.first.from, 'e2');
      expect(decoded.first.to, 'e4');
      expect(decoded.first.san, isNull);
    });

    test('decodeExpectedMoves validates expected format and does not misparse non-move JSON', () {
      expect(
        () => decodeExpectedMoves('[{"other":"something_long_enough_to_be_35_chars"}]'),
        throwsA(isA<TypeError>()),
      );
    });
  });
}
