// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-010, INV-033.

import 'package:chess_srs/src/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Study', () {
    test('Study.create generates a unique ID and sets timestamps', () {
      final now = DateTime(2026, 9, 16, 10);
      final s = Study.create(title: 'Sicilian Najdorf', createdAt: now);
      expect(s.id, isNotEmpty);
      expect(s.title, equals('Sicilian Najdorf'));
      expect(s.createdAt, equals(now));
      expect(s.updatedAt, equals(now));
    });

    test('Two Study.create calls produce different IDs', () {
      final a = Study.create(title: 'A');
      final b = Study.create(title: 'B');
      expect(a.id, isNot(equals(b.id)));
    });

    test('copyWith updates only the specified fields', () {
      const s = Study(id: 'id-1', title: 'Original');
      final updated = s.copyWith(title: 'Updated');
      expect(updated.id, equals('id-1'));
      expect(updated.title, equals('Updated'));
    });

    test('equality is by value', () {
      const a = Study(id: 'x', title: 'X');
      const b = Study(id: 'x', title: 'X');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('Chapter', () {
    test('Chapter.create generates a unique ID', () {
      final c = Chapter.create(studyId: 's1', sourceOrder: 0, title: 'Ch1');
      expect(c.id, isNotEmpty);
      expect(c.studyId, equals('s1'));
      expect(c.sourceOrder, equals(0));
      expect(c.title, equals('Ch1'));
    });

    test('startingFen is null for standard start', () {
      final c = Chapter.create(studyId: 's1', sourceOrder: 0);
      expect(c.startingFen, isNull);
    });

    test('startingFen is preserved for custom starting positions', () {
      const fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';
      final c = Chapter.create(studyId: 's1', sourceOrder: 0, startingFen: fen);
      expect(c.startingFen, equals(fen));
    });
  });

  group('RepertoireMove', () {
    test('uci encodes from/to correctly', () {
      const m = RepertoireMove(from: 'e2', to: 'e4');
      expect(m.uci, equals('e2e4'));
    });

    test('uci includes promotion character', () {
      const m = RepertoireMove(from: 'e7', to: 'e8', promotion: 'q');
      expect(m.uci, equals('e7e8q'));
    });

    test('matches() ignores san field', () {
      const a = RepertoireMove(from: 'e2', to: 'e4', san: 'e4');
      const b = RepertoireMove(from: 'e2', to: 'e4', san: null);
      expect(a.matches(b), isTrue);
      expect(b.matches(a), isTrue);
    });

    test('matches() handles castling equivalence (e1g1 matches e1h1, e1c1 matches e1a1)', () {
      // White Kingside
      const standardOO = RepertoireMove(from: 'e1', to: 'g1', san: 'O-O');
      const chess960OO = RepertoireMove(from: 'e1', to: 'h1', san: 'O-O');
      expect(standardOO.matches(chess960OO), isTrue);
      expect(chess960OO.matches(standardOO), isTrue);

      // White Queenside
      const standardOOO = RepertoireMove(from: 'e1', to: 'c1', san: 'O-O-O');
      const chess960OOO = RepertoireMove(from: 'e1', to: 'a1', san: 'O-O-O');
      expect(standardOOO.matches(chess960OOO), isTrue);
      expect(chess960OOO.matches(standardOOO), isTrue);

      // Black Kingside
      const blackOO = RepertoireMove(from: 'e8', to: 'g8', san: 'O-O');
      const black960OO = RepertoireMove(from: 'e8', to: 'h8', san: 'O-O');
      expect(blackOO.matches(black960OO), isTrue);
      expect(black960OO.matches(blackOO), isTrue);

      // Black Queenside
      const blackOOO = RepertoireMove(from: 'e8', to: 'c8', san: 'O-O-O');
      const black960OOO = RepertoireMove(from: 'e8', to: 'a8', san: 'O-O-O');
      expect(blackOOO.matches(black960OOO), isTrue);
      expect(black960OOO.matches(blackOOO), isTrue);
    });

    test('equality ignores san field', () {
      const a = RepertoireMove(from: 'e2', to: 'e4', san: 'e4');
      const b = RepertoireMove(from: 'e2', to: 'e4');
      expect(a, equals(b));
    });

    test('different moves are not equal', () {
      const a = RepertoireMove(from: 'e2', to: 'e4');
      const b = RepertoireMove(from: 'd2', to: 'd4');
      expect(a, isNot(equals(b)));
    });
  });

  group('RepertoireNode', () {
    const startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    const startKey = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';

    test('root node has no incomingMove', () {
      final root = RepertoireNode.root(fen: startFen, fenKey: startKey);
      expect(root.incomingMove, isNull);
      expect(root.isLeaf, isTrue);
    });

    test('addChild returns updated node with child appended', () {
      final root = RepertoireNode.root(fen: startFen, fenKey: startKey);
      const move = RepertoireMove(from: 'e2', to: 'e4', san: 'e4');
      const childFen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';
      const childKey = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3';
      final child = RepertoireNode.child(fen: childFen, fenKey: childKey, incomingMove: move);
      final updated = root.addChild(child);
      expect(updated.children, hasLength(1));
      expect(updated.children.first.incomingMove, equals(move));
    });

    test('multiple children are preserved (RAV preservation)', () {
      final root = RepertoireNode.root(fen: startFen, fenKey: startKey);
      const m1 = RepertoireMove(from: 'e2', to: 'e4');
      const m2 = RepertoireMove(from: 'd2', to: 'd4');
      final c1 = RepertoireNode.child(fen: 'fen1', fenKey: 'key1', incomingMove: m1);
      final c2 = RepertoireNode.child(fen: 'fen2', fenKey: 'key2', incomingMove: m2);
      final updated = root.addChild(c1).addChild(c2);
      expect(updated.children, hasLength(2));
    });

    test('childForMove returns correct child', () {
      const move = RepertoireMove(from: 'e2', to: 'e4');
      final root = RepertoireNode.root(fen: startFen, fenKey: startKey);
      final child = RepertoireNode.child(fen: 'fen1', fenKey: 'key1', incomingMove: move);
      final updated = root.addChild(child);
      expect(updated.childForMove(move), isNotNull);
    });

    test('childForMove returns null for unknown move', () {
      const move = RepertoireMove(from: 'e2', to: 'e4');
      final root = RepertoireNode.root(fen: startFen, fenKey: startKey);
      final child = RepertoireNode.child(fen: 'fen1', fenKey: 'key1', incomingMove: move);
      final updated = root.addChild(child);
      const unknown = RepertoireMove(from: 'd2', to: 'd4');
      expect(updated.childForMove(unknown), isNull);
    });

    test('original node is unchanged after addChild (immutability)', () {
      final root = RepertoireNode.root(fen: startFen, fenKey: startKey);
      const move = RepertoireMove(from: 'e2', to: 'e4');
      final child = RepertoireNode.child(fen: 'fen1', fenKey: 'key1', incomingMove: move);
      root.addChild(child);
      expect(root.children, isEmpty);
    });
  });

  group('RepertoireDecision', () {
    test('create generates a unique ID', () {
      final d = RepertoireDecision.create(
        studyId: 's1',
        chapterId: 'c1',
        nodeId: 'n1',
        expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4')],
      );
      expect(d.id, isNotEmpty);
    });

    test('accepts() returns true for matching move', () {
      final d = RepertoireDecision.create(
        studyId: 's1',
        chapterId: 'c1',
        nodeId: 'n1',
        expectedMoves: const [
          RepertoireMove(from: 'e2', to: 'e4'),
          RepertoireMove(from: 'd2', to: 'd4'),
        ],
      );
      expect(d.accepts(const RepertoireMove(from: 'e2', to: 'e4')), isTrue);
      expect(d.accepts(const RepertoireMove(from: 'd2', to: 'd4')), isTrue);
    });

    test('accepts() returns false for non-repertoire move', () {
      final d = RepertoireDecision.create(
        studyId: 's1',
        chapterId: 'c1',
        nodeId: 'n1',
        expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4')],
      );
      expect(d.accepts(const RepertoireMove(from: 'c2', to: 'c4')), isFalse);
    });

    test('expectedMoves list is unmodifiable', () {
      final d = RepertoireDecision.create(
        studyId: 's1',
        chapterId: 'c1',
        nodeId: 'n1',
        expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4')],
      );
      expect(
        () => (d.expectedMoves as List).add(const RepertoireMove(from: 'd2', to: 'd4')),
        throwsUnsupportedError,
      );
    });
  });
}
