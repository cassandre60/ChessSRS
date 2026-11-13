import 'package:chess_srs/src/domain/repertoire_move.dart';
import 'package:chess_srs/src/domain/repertoire_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
  const startFenKey = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';
  const e4Fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';
  const e4FenKey = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3';
  const d4Fen = 'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq d3 0 1';
  const d4FenKey = 'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq d3';

  const e2e4 = RepertoireMove(from: 'e2', to: 'e4', san: 'e4');
  const d2d4 = RepertoireMove(from: 'd2', to: 'd4', san: 'd4');

  group('RepertoireNode.root', () {
    test('creates a leaf root without incoming move', () {
      final root = RepertoireNode.root(fen: startFen, fenKey: startFenKey, comment: 'start');

      expect(root.id, isNotEmpty);
      expect(root.fen, startFen);
      expect(root.fenKey, startFenKey);
      expect(root.incomingMove, isNull);
      expect(root.comment, 'start');
      expect(root.nags, isEmpty);
      expect(root.children, isEmpty);
      expect(root.isLeaf, isTrue);
      expect(root.childMoves, isEmpty);
    });
  });

  group('RepertoireNode.child', () {
    test('creates a child with incoming move and metadata', () {
      final child = RepertoireNode.child(
        fen: e4Fen,
        fenKey: e4FenKey,
        incomingMove: e2e4,
        comment: 'King pawn',
        nags: const [1, 14],
      );

      expect(child.id, isNotEmpty);
      expect(child.fen, e4Fen);
      expect(child.fenKey, e4FenKey);
      expect(child.incomingMove, e2e4);
      expect(child.comment, 'King pawn');
      expect(child.nags, [1, 14]);
      expect(child.children, isEmpty);
      expect(child.isLeaf, isTrue);
    });
  });

  group('tree operations', () {
    test('addChild returns new node preserving identity and appending child', () {
      final root = RepertoireNode.root(fen: startFen, fenKey: startFenKey);
      final e4 = RepertoireNode.child(fen: e4Fen, fenKey: e4FenKey, incomingMove: e2e4);
      final d4 = RepertoireNode.child(fen: d4Fen, fenKey: d4FenKey, incomingMove: d2d4);

      final withE4 = root.addChild(e4);
      final withBoth = withE4.addChild(d4);

      expect(root.children, isEmpty);
      expect(withE4.id, root.id);
      expect(withE4.fen, root.fen);
      expect(withE4.fenKey, root.fenKey);
      expect(withE4.incomingMove, root.incomingMove);
      expect(withE4.children, [e4]);
      expect(withE4.isLeaf, isFalse);
      expect(withBoth.children, [e4, d4]);
      expect(withBoth.childMoves, [e2e4, d2d4]);
    });

    test('childForMove finds matching child including castling notation', () {
      final root = RepertoireNode.root(fen: startFen, fenKey: startFenKey);
      const castle = RepertoireMove(from: 'e1', to: 'g1', san: 'O-O');
      final castleNode = RepertoireNode.child(
        fen: 'rnbqk2r/pppp1ppp/5n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4',
        fenKey: 'rnbqk2r/pppp1ppp/5n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq -',
        incomingMove: castle,
      );
      final tree = root.addChild(castleNode);

      expect(tree.childForMove(const RepertoireMove(from: 'e1', to: 'g1')), same(castleNode));
      expect(tree.childForMove(const RepertoireMove(from: 'e1', to: 'h1')), same(castleNode));
      expect(tree.childForMove(d2d4), isNull);
    });
  });

  group('copyWith', () {
    test('copies selected fields while preserving identity fields', () {
      final root = RepertoireNode.root(fen: startFen, fenKey: startFenKey, comment: 'old');
      final child = RepertoireNode.child(fen: e4Fen, fenKey: e4FenKey, incomingMove: e2e4);

      final copied = root.copyWith(
        children: [child],
        comment: 'new',
        incomingMove: e2e4,
        nags: const [2],
      );

      expect(copied.id, root.id);
      expect(copied.fen, root.fen);
      expect(copied.fenKey, root.fenKey);
      expect(copied.children, [child]);
      expect(copied.comment, 'new');
      expect(copied.incomingMove, e2e4);
      expect(copied.nags, [2]);
    });

    test('keeps existing values when arguments omitted', () {
      final child = RepertoireNode.child(
        fen: e4Fen,
        fenKey: e4FenKey,
        incomingMove: e2e4,
        comment: 'keep',
        nags: const [3],
      );

      final copied = child.copyWith();

      expect(copied.id, child.id);
      expect(copied.fen, child.fen);
      expect(copied.fenKey, child.fenKey);
      expect(copied.incomingMove, child.incomingMove);
      expect(copied.comment, 'keep');
      expect(copied.nags, [3]);
      expect(copied.children, isEmpty);
    });
  });

  group('equality and display', () {
    test('equals and hashes by id and fenKey', () {
      final a = RepertoireNode(id: 'same-id', fen: startFen, fenKey: startFenKey, comment: 'a');
      final b = RepertoireNode(id: 'same-id', fen: e4Fen, fenKey: startFenKey, comment: 'b');
      final differentId = RepertoireNode(id: 'other-id', fen: startFen, fenKey: startFenKey);
      final differentFenKey = RepertoireNode(id: 'same-id', fen: startFen, fenKey: e4FenKey);

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a == differentId, isFalse);
      expect(a == differentFenKey, isFalse);
    });

    test('toString includes id and fenKey', () {
      const node = RepertoireNode(id: 'id-1', fen: startFen, fenKey: startFenKey);

      expect(node.toString(), 'RepertoireNode(id: id-1, fenKey: $startFenKey)');
    });
  });
}
