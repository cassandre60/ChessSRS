import 'package:chess_srs/src/model/common/chess960.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chess960Position', () {
    test('returns a Chess960 setup for valid indices', () {
      for (var i = 0; i < 960; i++) {
        final pos = chess960Position(i);
        expect(pos, isA<Chess>());
        expect(pos.turn, Side.white);
        expect(pos.castles.rookOf(Side.white, CastlingSide.king), isNotNull);
        expect(pos.castles.rookOf(Side.white, CastlingSide.queen), isNotNull);
        expect(pos.castles.rookOf(Side.black, CastlingSide.king), isNotNull);
        expect(pos.castles.rookOf(Side.black, CastlingSide.queen), isNotNull);
      }
    });

    test('index 518 is the standard chess starting position', () {
      final pos = chess960Position(518);
      expect(pos.fen, Chess.initial.fen);
    });

    test('known indices produce the expected back-rank FEN', () {
      expect(chess960Position(0).fen, 'bbqnnrkr/pppppppp/8/8/8/8/PPPPPPPP/BBQNNRKR w KQkq - 0 1');
      expect(chess960Position(959).fen, 'rkrnnqbb/pppppppp/8/8/8/8/PPPPPPPP/RKRNNQBB w KQkq - 0 1');
    });

    test('back ranks are mirrored upper/lower case with standard pawns', () {
      final pos = chess960Position(123);
      final parts = pos.fen.split(' ');
      final ranks = parts[0].split('/');
      expect(ranks[1], 'pppppppp');
      expect(ranks[6], 'PPPPPPPP');
      expect(ranks[7], ranks[0].toUpperCase());
      expect(parts[1], 'w');
      expect(parts[2], 'KQkq');
      expect(parts[3], '-');
    });

    test('throws ArgumentError for out-of-range indices', () {
      expect(() => chess960Position(-1), throwsArgumentError);
      expect(() => chess960Position(960), throwsArgumentError);
      expect(() => chess960Position(1000), throwsArgumentError);
    });
  });

  group('randomChess960Position', () {
    test('returns a valid Chess960 position', () {
      for (var i = 0; i < 20; i++) {
        final pos = randomChess960Position();
        expect(pos, isA<Chess>());
        expect(pos.turn, Side.white);
        expect(pos.castles.rookOf(Side.white, CastlingSide.king), isNotNull);
      }
    });
  });
}
