import 'package:chess_srs/src/utils/chessboard.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('atomicExplosionSquares', () {
    test('returns null when move is null', () {
      const position = Atomic.initial;

      expect(atomicExplosionSquares(position, null), isNull);
    });

    test('returns null for a non-atomic position', () {
      const position = Chess.initial;
      final move = Move.parse('e2e4');

      expect(atomicExplosionSquares(position, move), isNull);
    });

    test('returns null for a non-capture move in atomic', () {
      const position = Atomic.initial;
      final move = Move.parse('g1f3');

      expect(atomicExplosionSquares(position, move), isNull);
    });

    test('returns explosion squares for an atomic capture', () {
      final position = Position.setupPosition(
        Rule.atomic,
        Setup.parseFen('rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2'),
      );
      final move = Move.parse('e4d5')!;

      final squares = atomicExplosionSquares(position, move);

      expect(squares, equals({Square.d5}));
    });
  });
}
