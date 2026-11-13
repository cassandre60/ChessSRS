// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/repertoire_move.dart';
import 'package:chess_srs/src/domain/repertoire_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
  const startKey = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';
  const e4Fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';
  const e4Key = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3';
  const d4Fen = 'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq d3 0 1';
  const d4Key = 'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq d3';

  group('RepertoireNode.root', () {
    test('creates a root with no incoming move, comment, or children', () {
      final root = RepertoireNode.root(
        fen: startFen,
        fenKey: startKey,
        comment: 'Starting position',
      );

      expect(root.id, isNotEmpty);
      expect(root.fen, startFen);
      expect(root.fenKey, startKey);
      expect(root.incomingMove, isNull);
      expect(root.comment, 'Starting position');
      expect(root.nags, isEmpty);
      expect(root.children, isEmpty);
      expect(root.isLeaf, isTrue);
      expect(root.childMoves, isEmpty);
    });
  });

  group('RepertoireNode.child', () {
    test('creates a child reached via an incoming move', () {
      const move = RepertoireMove(from: 'e2', to: 'e4', san: 'e4');
      final child = RepertoireNode.child(
        fen: e4Fen,
        fenKey: e4Key,
        incomingMove: move,
        comment: 'King pawn',
        nags: const [1, 14],
      );

      expect(child.id, isNotEmpty);
      expect(child.fen, e4Fen);
      expect(child.fenKey, e4Key);
      expect(child.incomingMove, move);
      expect(child.comment, 'King pawn');
      expect(child.nags, [1, 14]);
      expect(child.children, isEmpty);
      expect(child.isLeaf, isTrue);
    });
  });

  group('immutability and tree operations', () {
    test('addChild appends children in order without mutating the original', () {
      final root = RepertoireNode.root(fen: startFen, fenKey: startKey);
      const e4 = RepertoireMove(from: 'e2', to: 'e4', san: 'e4');
      const d4 = RepertoireMove(from: 'd2', to: 'd4', san: 'd4');
      final e4Child = RepertoireNode.child(fen: e4Fen, fenKey: e4Key, incomingMove: e4);
      final d4Child = RepertoireNode.child(fen: d4Fen, fenKey: d4Key, incomingMove: d4);

      final withOne = root.addChild(e4Child);
      final withTwo = withOne.addChild(d4Child);

      expect(root.children, isEmpty);
      expect(withOne.children, [e4Child]);
      expect(withTwo.children, [e4Child, d4Child]);
      expect(withTwo.isLeaf, isFalse);
      expect(withTwo.childMoves, [e4, d4]);
      expect(withTwo.id, root.id);
      expect(withTwo.fen, root.fen);
      expect(withTwo.fenKey, root.fenKey);
    });

    test('childForMove finds matching child by move semantics and returns null when absent', () {
      final root = RepertoireNode.root(fen: startFen, fenKey: startKey);
      const e4 = RepertoireMove(from: 'e2', to: 'e4', san: 'e4');
      final e4Child = RepertoireNode.child(fen: e4Fen, fenKey: e4Key, incomingMove: e4);
      final updated = root.addChild(e4Child);

      // Same squares, different SAN/case should still match via RepertoireMove.matches.
      expect(updated.childForMove(const RepertoireMove(from: 'E2', to: 'E4')), same(e4Child));
      expect(updated.childForMove(const RepertoireMove(from: 'd2', to: 'd4')), isNull);
    });

    test('childForMove finds matching child including castling notation', () {
      final root = RepertoireNode.root(fen: startFen, fenKey: startKey);
      const castle = RepertoireMove(from: 'e1', to: 'g1', san: 'O-O');
      final castleNode = RepertoireNode.child(
        fen: 'rnbqk2r/pppp1ppp/5n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4',
        fenKey: 'rnbqk2r/pppp1ppp/5n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq -',
        incomingMove: castle,
      );
      final tree = root.addChild(castleNode);

      expect(tree.childForMove(const RepertoireMove(from: 'e1', to: 'g1')), same(castleNode));
      expect(tree.childForMove(const RepertoireMove(from: 'e1', to: 'h1')), same(castleNode));
      expect(tree.childForMove(const RepertoireMove(from: 'd2', to: 'd4')), isNull);
    });

    test('childMoves returns incoming moves in child order', () {
      const e4 = RepertoireMove(from: 'e2', to: 'e4');
      const d4 = RepertoireMove(from: 'd2', to: 'd4');
      final node = RepertoireNode(
        id: 'node-1',
        fen: startFen,
        fenKey: startKey,
        children: [
          RepertoireNode.child(fen: e4Fen, fenKey: e4Key, incomingMove: e4),
          RepertoireNode.child(fen: d4Fen, fenKey: d4Key, incomingMove: d4),
        ],
      );

      expect(node.childMoves, [e4, d4]);
      expect(node.isLeaf, isFalse);
    });

    test('copyWith replaces provided fields while preserving identity and defaults', () {
      const originalMove = RepertoireMove(from: 'e2', to: 'e4');
      const original = RepertoireNode(
        id: 'node-1',
        fen: e4Fen,
        fenKey: e4Key,
        incomingMove: originalMove,
        comment: 'old',
        nags: [1],
        children: [],
      );
      const replacementMove = RepertoireMove(from: 'd2', to: 'd4');
      final child = RepertoireNode.child(fen: d4Fen, fenKey: d4Key, incomingMove: replacementMove);

      final copied = original.copyWith(
        children: [child],
        comment: 'new',
        incomingMove: replacementMove,
        nags: const [2, 14],
      );

      expect(copied.id, 'node-1');
      expect(copied.fen, e4Fen);
      expect(copied.fenKey, e4Key);
      expect(copied.incomingMove, replacementMove);
      expect(copied.comment, 'new');
      expect(copied.nags, [2, 14]);
      expect(copied.children, [child]);

      final unchanged = original.copyWith();
      expect(unchanged.incomingMove, originalMove);
      expect(unchanged.comment, 'old');
      expect(unchanged.nags, [1]);
      expect(unchanged.children, isEmpty);
    });
  });

  group('equality', () {
    test('nodes are equal by id and fenKey and hash consistently', () {
      const a = RepertoireNode(id: 'same', fen: 'fen-a', fenKey: 'key');
      const b = RepertoireNode(id: 'same', fen: 'fen-b', fenKey: 'key');
      const differentId = RepertoireNode(id: 'other', fen: 'fen-a', fenKey: 'key');
      const differentKey = RepertoireNode(id: 'same', fen: 'fen-a', fenKey: 'other-key');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(differentId)));
      expect(a, isNot(equals(differentKey)));
    });
  });

  group('display', () {
    test('toString includes id and fenKey', () {
      const node = RepertoireNode(id: 'id-1', fen: startFen, fenKey: startKey);

      expect(node.toString(), 'RepertoireNode(id: id-1, fenKey: $startKey)');
    });
  });
}
