// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math';

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
        expect(
          () => rawChildren.add(rawChildren.first),
          throwsUnsupportedError,
          reason: 'serialized children must be non-growable',
        );

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
        expect(
          () => decoded.children.add(decoded.children.first),
          throwsUnsupportedError,
          reason: 'decoded children must be non-growable',
        );

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

    test('INV-010: nags survive a round trip', () {
      const node = RepertoireNode(
        id: 'node-nags',
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        fenKey: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
        nags: [1, 3, 42],
        children: [],
      );
      final json = repertoireNodeToJson(node);
      expect(json['nags'], [1, 3, 42]);

      final decoded = repertoireNodeFromJson(json);
      expect(decoded.nags, [1, 3, 42]);
      expect(
        () => decoded.nags.add(5),
        throwsUnsupportedError,
        reason: 'decoded nags must be non-growable',
      );
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
      expect(
        () => decodedMulti.add(const RepertoireMove(from: 'e2', to: 'e4', san: 'e4')),
        throwsUnsupportedError,
        reason: 'decoded expected moves must be non-growable',
      );
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

    test(
      'decodeExpectedMoves does not fast-path misparse a JSON array that only looks like a single move',
      () {
        // The fast path is an optimization gated on every field marker being
        // present. Dropping any gate must fall back to the general parser (and
        // therefore to a TypeError here) rather than slicing garbage.
        const malformed = '[{"from":"e2","padding":"ABCDEFGHIJKLMNOP"}]';
        expect(() => decodeExpectedMoves(malformed), throwsA(isA<TypeError>()));
      },
    );

    test('decodeExpectedMoves validates expected format and does not misparse non-move JSON', () {
      expect(
        () => decodeExpectedMoves('[{"other":"something_long_enough_to_be_35_chars"}]'),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('property-based date parser and JSON adapter round-trips', () {
    test('parseUtcIso matches DateTime.parse().toUtc() across 600 random ISO-8601 timestamps', () {
      final rng = Random(20261117);
      for (var i = 0; i < 600; i++) {
        final year = 1970 + rng.nextInt(130);
        final month = 1 + rng.nextInt(12);
        final day = 1 + rng.nextInt(28);
        final hour = rng.nextInt(24);
        final minute = rng.nextInt(60);
        final second = rng.nextInt(60);
        final millis = rng.nextInt(1000);

        String two(int n) => n.toString().padLeft(2, '0');
        String three(int n) => n.toString().padLeft(3, '0');
        final base =
            '${year.toString().padLeft(4, '0')}-${two(month)}-${two(day)}'
            'T${two(hour)}:${two(minute)}:${two(second)}';

        final mode = i % 4;
        final String iso;
        if (mode == 0) {
          // 20-char fast path: YYYY-MM-DDTHH:MM:SSZ
          iso = '${base}Z';
        } else if (mode == 1) {
          // 24-char fast path: YYYY-MM-DDTHH:MM:SS.mmmZ
          iso = '$base.${three(millis)}Z';
        } else if (mode == 2) {
          // 6-digit microsecond fallback path
          final micros = rng.nextInt(1000);
          iso = '$base.${three(millis)}${three(micros)}Z';
        } else {
          // Explicit timezone offset fallback path (+HH:MM / -HH:MM)
          final sign = rng.nextBool() ? '+' : '-';
          final offH = two(rng.nextInt(12));
          final offM = rng.nextBool() ? '00' : '30';
          iso = '$base.${three(millis)}$sign$offH:$offM';
        }

        final actual = parseUtcIso(iso);
        final expected = DateTime.parse(iso).toUtc();
        expect(actual.isUtc, isTrue, reason: 'trial $i ($iso) must be UTC');
        expect(actual, equals(expected), reason: 'trial $i ($iso) mismatch');
      }
    });

    test('encodeExpectedMoves / decodeExpectedMoves round-trips across 500 random move sets', () {
      final rng = Random(774411);
      const files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
      const ranks = ['1', '2', '3', '4', '5', '6', '7', '8'];
      const promos = [null, null, null, 'q', 'r', 'b', 'n'];
      const sanSamples = [
        'e4',
        'Nf3',
        'Bxc6+',
        'O-O',
        'O-O-O',
        'e8=Q#',
        'Raxd1',
        'Qh4+',
        'cxd5',
        null,
        'move "quoted"',
        r'move \slash',
      ];

      String randomSquare() => '${files[rng.nextInt(8)]}${ranks[rng.nextInt(8)]}';

      for (var trial = 0; trial < 500; trial++) {
        final count = trial < 250 ? 1 : (1 + rng.nextInt(5));
        final moves = List.generate(count, (_) {
          final from = randomSquare();
          var to = randomSquare();
          if (to == from) {
            to = 'e4' == from ? 'd4' : 'e4';
          }
          final promo = promos[rng.nextInt(promos.length)];
          final san = sanSamples[rng.nextInt(sanSamples.length)];
          return RepertoireMove(from: from, to: to, promotion: promo, san: san);
        });

        final encoded = encodeExpectedMoves(moves);
        final decoded = decodeExpectedMoves(encoded);

        expect(decoded.length, equals(moves.length), reason: 'trial $trial length');
        for (var j = 0; j < moves.length; j++) {
          expect(decoded[j].from, equals(moves[j].from), reason: 'trial $trial move $j from');
          expect(decoded[j].to, equals(moves[j].to), reason: 'trial $trial move $j to');
          expect(
            decoded[j].promotion,
            equals(moves[j].promotion),
            reason: 'trial $trial move $j promotion',
          );
          expect(decoded[j].san, equals(moves[j].san), reason: 'trial $trial move $j san');
        }
      }
    });

    test('reviewState and reviewEvent JSON adapters round-trip across 250 random states', () {
      final rng = Random(991122);
      final epoch = DateTime.utc(2025, 1, 1);

      DateTime randomInstant() {
        final ms = rng.nextInt(365 * 5 * 86400) * 1000 + rng.nextInt(1000);
        final utc = epoch.add(Duration(milliseconds: ms));
        return rng.nextBool() ? utc : utc.toLocal();
      }

      ReviewState randomState(String id) {
        return ReviewState(
          decisionId: id,
          firstReviewedAt: rng.nextBool() ? randomInstant() : null,
          lastReviewedAt: rng.nextBool() ? randomInstant() : null,
          nextDueAt: rng.nextBool() ? randomInstant() : null,
          repetitionCount: rng.nextInt(30),
          lapseCount: rng.nextInt(15),
          stability: rng.nextDouble() * 365 * 86400000,
          difficulty: 1.0 + rng.nextDouble() * 9.0,
        );
      }

      for (var i = 0; i < 250; i++) {
        final s = randomState('dec-$i');
        final json = reviewStateToJson(s);
        final decoded = reviewStateFromJson(json);

        expect(decoded.decisionId, equals(s.decisionId));
        expect(decoded.firstReviewedAt, equals(s.firstReviewedAt?.toUtc()));
        expect(decoded.lastReviewedAt, equals(s.lastReviewedAt?.toUtc()));
        expect(decoded.nextDueAt, equals(s.nextDueAt?.toUtc()));
        expect(decoded.repetitionCount, equals(s.repetitionCount));
        expect(decoded.lapseCount, equals(s.lapseCount));
        expect(decoded.stability, closeTo(s.stability, 1e-6));
        expect(decoded.difficulty, closeTo(s.difficulty, 1e-6));

        final ev = ReviewEvent(
          decisionId: s.decisionId,
          when: randomInstant(),
          result: rng.nextBool() ? ReviewResult.correct : ReviewResult.incorrect,
          oldState: s,
          newState: randomState('dec-$i'),
        );
        final evJson = reviewEventToJson(ev);
        final evDecoded = reviewEventFromJson(evJson);
        expect(evDecoded.decisionId, equals(ev.decisionId));
        expect(evDecoded.when, equals(ev.when.toUtc()));
        expect(evDecoded.result, equals(ev.result));
        expect(evDecoded.oldState.repetitionCount, equals(ev.oldState.repetitionCount));
        expect(evDecoded.newState.repetitionCount, equals(ev.newState.repetitionCount));
      }
    });

    test('INV-010: repertoireNodeToJson / repertoireNodeFromJson round-trips 100 random trees', () {
      // SPEC INV-010.
      final rng = Random(314159);
      var idCounter = 0;

      RepertoireNode buildRandomTree(int depth) {
        final id = 'n-${idCounter++}';
        final childCount = depth >= 3 ? 0 : rng.nextInt(4);
        final hasComment = rng.nextBool();
        final nagCount = rng.nextInt(4);
        final nags = List.generate(nagCount, (_) => 1 + rng.nextInt(20));
        return RepertoireNode(
          id: id,
          fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 ${depth + 1}',
          fenKey: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
          incomingMove: depth == 0
              ? null
              : RepertoireMove(
                  from: 'e2',
                  to: 'e4',
                  promotion: rng.nextInt(5) == 0 ? 'q' : null,
                  san: 'e4',
                ),
          comment: hasComment ? 'Comment at $id with "quotes" & symbols' : null,
          nags: nags,
          children: List.generate(childCount, (_) => buildRandomTree(depth + 1)),
        );
      }

      void expectTreesEqual(RepertoireNode a, RepertoireNode b) {
        expect(a.id, equals(b.id));
        expect(a.fen, equals(b.fen));
        expect(a.fenKey, equals(b.fenKey));
        expect(a.comment, equals(b.comment));
        expect(a.nags, equals(b.nags));
        expect(a.incomingMove?.from, equals(b.incomingMove?.from));
        expect(a.incomingMove?.to, equals(b.incomingMove?.to));
        expect(a.incomingMove?.promotion, equals(b.incomingMove?.promotion));
        expect(a.incomingMove?.san, equals(b.incomingMove?.san));
        expect(a.children.length, equals(b.children.length));
        for (var i = 0; i < a.children.length; i++) {
          expectTreesEqual(a.children[i], b.children[i]);
        }
      }

      for (var trial = 0; trial < 100; trial++) {
        final root = buildRandomTree(0);
        final json = repertoireNodeToJson(root);
        final decoded = repertoireNodeFromJson(json);
        expectTreesEqual(decoded, root);
      }
    });
  });
}
