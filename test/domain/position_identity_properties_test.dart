// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-015, INV-016, INV-017, INV-033.

import 'dart:math';

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('position identity & canonical key properties', () {
    test('INV-015 positionIdentity is idempotent and strips only clock counters', () {
      final rng = Random(101);
      for (var gameIdx = 0; gameIdx < 30; gameIdx++) {
        Position pos = Chess.initial;
        for (var ply = 0; ply < 24; ply++) {
          final fullFen = pos.fen;
          final id1 = positionIdentity(fullFen);
          final id2 = positionIdentity(id1);

          // SPEC INV-015. Position identity is the normalized 4-field FEN and is idempotent.
          expect(id2, equals(id1), reason: 'positionIdentity must be idempotent (game $gameIdx)');
          final fields = id1.split(' ');
          expect(fields.length, equals(4), reason: '4-field FEN required');

          // Modifying halfmove and fullmove counters never changes positionIdentity
          final mutatedClockFen = '$id1 ${rng.nextInt(99)} ${1 + rng.nextInt(150)}';
          expect(
            positionIdentity(mutatedClockFen),
            equals(id1),
            reason: 'halfmove/fullmove counters must not affect positionIdentity',
          );

          final nonEmptyEntries = pos.legalMoves.entries
              .where((e) => e.value.squares.isNotEmpty)
              .toList();
          if (nonEmptyEntries.isEmpty) break;
          final fromEntry = nonEmptyEntries[rng.nextInt(nonEmptyEntries.length)];
          final toSquares = fromEntry.value.squares.toList();
          final toSq = toSquares[rng.nextInt(toSquares.length)];
          var move = NormalMove(from: fromEntry.key, to: toSq);
          if (isPromotionPawnMove(pos, move)) {
            move = NormalMove(from: fromEntry.key, to: toSq, promotion: Role.queen);
          }
          pos = pos.play(move);
        }
      }
    });

    test('INV-016/INV-017 canonicalKeyForPosition is permutation-invariant and set-sensitive', () {
      // SPEC INV-016, INV-017. Same position + side + accepted move set (in any order)
      // shares one canonical key; any difference in side, FEN, or move set yields a distinct key.
      final rng = Random(202);
      const candidateMoves = ['e2e4', 'd2d4', 'g1f3', 'c2c4', 'b1c3', 'g2g3', 'b2b3', 'f2f4'];

      for (var trial = 0; trial < 40; trial++) {
        const fen4 = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';
        final subsetSize = 1 + rng.nextInt(5);
        final pool = List<String>.of(candidateMoves)..shuffle(rng);
        final movesA = pool.sublist(0, subsetSize);
        final movesB = List<String>.of(movesA)..shuffle(rng);

        for (final side in Side.values) {
          final keyA = canonicalKeyForPosition(fen4, movesA, repertoireSide: side);
          final keyB = canonicalKeyForPosition(fen4, movesB, repertoireSide: side);
          expect(
            keyB,
            equals(keyA),
            reason: 'permutation of accepted moves must not fork canonical identity (trial $trial)',
          );

          final oppositeKey = canonicalKeyForPosition(fen4, movesA, repertoireSide: side.opposite);
          expect(
            oppositeKey,
            isNot(equals(keyA)),
            reason: 'different repertoireSide must not share canonical identity',
          );

          final extraMove = pool[subsetSize];
          final expandedKey = canonicalKeyForPosition(fen4, [
            ...movesA,
            extraMove,
          ], repertoireSide: side);
          expect(
            expandedKey,
            isNot(equals(keyA)),
            reason: 'different accepted-reply sets must distinguish memories (INV-017)',
          );
        }
      }
    });

    test(
      'INV-033 RepertoireMove.matches treats standard and king-takes-rook castling as equal',
      () {
        // SPEC INV-033. Castling notations are equivalent across both colours and wings.
        const castlingPairs = [
          ('e1', 'g1', 'e1', 'h1'),
          ('e1', 'c1', 'e1', 'a1'),
          ('e8', 'g8', 'e8', 'h8'),
          ('e8', 'c8', 'e8', 'a8'),
        ];

        for (final (f1, t1, f2, t2) in castlingPairs) {
          final standard = RepertoireMove(from: f1, to: t1, san: 'O-O');
          final kingTakesRook = RepertoireMove(from: f2, to: t2, san: 'O-O');

          expect(standard.matches(kingTakesRook), isTrue);
          expect(kingTakesRook.matches(standard), isTrue);
          expect(standard.matches(standard), isTrue);
          expect(kingTakesRook.matches(kingTakesRook), isTrue);

          final decision = RepertoireDecision(
            id: 'd-$f1$t1',
            studyId: 's1',
            chapterId: 'c1',
            nodeId: 'n1',
            expectedMoves: [standard],
          );
          expect(decision.accepts(kingTakesRook), isTrue);
        }
      },
    );
  });
}
