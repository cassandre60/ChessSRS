import 'package:chess_srs/src/model/offline_computer/offline_computer_game_preferences.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SideChoice', () {
    test('toSide returns fixed sides and null for random', () {
      expect(SideChoice.white.toSide(), Side.white);
      expect(SideChoice.black.toSide(), Side.black);
      expect(SideChoice.random.toSide(), isNull);
    });

    test('toSide(nextToPlay) resolves side to move from FEN', () {
      expect(
        SideChoice.nextToPlay.toSide(
          fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        ),
        Side.white,
      );
      expect(
        SideChoice.nextToPlay.toSide(
          fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
        ),
        Side.black,
      );
    });

    test('toSide(nextToPlay) returns null when no FEN is provided', () {
      expect(SideChoice.nextToPlay.toSide(), isNull);
      expect(SideChoice.nextToPlay.toSide(fen: null), isNull);
    });

    test('fromSide maps sides and null to choices', () {
      expect(SideChoice.fromSide(Side.white), SideChoice.white);
      expect(SideChoice.fromSide(Side.black), SideChoice.black);
      expect(SideChoice.fromSide(null), SideChoice.random);
    });
  });
}
