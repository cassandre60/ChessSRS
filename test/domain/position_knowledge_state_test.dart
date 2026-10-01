// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-015, INV-016, INV-017.

import 'package:chess_srs/src/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PositionKnowledgeState & canonicalKey', () {
    test('canonicalKey produces deterministic SHA-1 hash for FEN4 and UCI move', () {
      const fenKey = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3';
      const uci = 'e7e5';

      final key1 = canonicalKey(fenKey, uci);
      final key2 = canonicalKey(fenKey, uci);

      expect(key1, equals(key2));
      expect(key1.length, 40); // SHA-1 hex string
    });

    test('canonicalKey differs when FEN or move differs', () {
      const fen1 = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3';
      const fen2 = 'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq d3';

      expect(canonicalKey(fen1, 'e7e5'), isNot(equals(canonicalKey(fen2, 'e7e5'))));
      expect(canonicalKey(fen1, 'e7e5'), isNot(equals(canonicalKey(fen1, 'c7c5'))));
    });

    group('canonicalKeyForPosition', () {
      const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';

      test('is deterministic and a SHA-1 hex string', () {
        final a = canonicalKeyForPosition(start, ['e2e4']);
        final b = canonicalKeyForPosition(start, ['e2e4']);

        expect(a, equals(b));
        expect(a.length, 40);
      });

      test('ignores the order the accepted moves are listed in', () {
        expect(
          canonicalKeyForPosition(start, ['e2e4', 'd2d4', 'g1f3']),
          equals(canonicalKeyForPosition(start, ['g1f3', 'd2d4', 'e2e4'])),
          reason: 'reordered branches must not fork the same repertoire',
        );
      });

      test('differs when the accepted set differs even if the first move matches', () {
        // This is the collision the first-child key could not see.
        expect(
          canonicalKeyForPosition(start, ['e2e4']),
          isNot(equals(canonicalKeyForPosition(start, ['e2e4', 'd2d4']))),
        );
        expect(
          canonicalKeyForPosition(start, ['e2e4', 'd2d4']),
          isNot(equals(canonicalKeyForPosition(start, ['e2e4', 'c2c4']))),
        );
      });

      test('differs when the position differs even if the accepted set matches', () {
        const elsewhere = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3';
        expect(
          canonicalKeyForPosition(start, ['e7e5']),
          isNot(equals(canonicalKeyForPosition(elsewhere, ['e7e5']))),
          reason: 'distinct positions must never share SRS memory',
        );
      });

      test('a single-move set agrees with no other set', () {
        // Regression guard: an earlier attempt hashed the moves alone, dropping the position
        // entirely, which merged every position offering the same move.
        const elsewhereFEN = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3';
        expect(
          canonicalKeyForPosition(start, ['e2e4']),
          isNot(equals(canonicalKeyForPosition(elsewhereFEN, ['e2e4']))),
        );
      });
    });

    test('PositionKnowledgeState cold defaults and due calculation', () {
      final now = DateTime(2026, 9, 18, 12);
      final cold = PositionKnowledgeState.cold('canonical-123');

      expect(cold.canonicalId, 'canonical-123');
      expect(cold.isNew, isTrue);
      expect(cold.isLearned, isFalse);
      expect(cold.isDueAt(now), isTrue);
      expect(cold.stability, 0.0);
      expect(cold.difficulty, 0.0);
      expect(cold.latencySampleCount, 0);
    });

    test('converts cleanly to ReviewState', () {
      final now = DateTime(2026, 9, 18, 12);
      final kState = PositionKnowledgeState(
        canonicalId: 'c-1',
        firstReviewedAt: now,
        lastReviewedAt: now,
        nextDueAt: now.add(const Duration(days: 2)),
        repetitionCount: 3,
        lapseCount: 1,
        stability: 172800000.0,
        difficulty: 4.5,
      );

      final rState = kState.toReviewState('dec-custom-id');
      expect(rState.decisionId, 'dec-custom-id');
      expect(rState.repetitionCount, 3);
      expect(rState.lapseCount, 1);
      expect(rState.stability, 172800000.0);
      expect(rState.difficulty, 4.5);
    });
  });
}
