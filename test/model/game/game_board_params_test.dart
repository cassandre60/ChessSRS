import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/game/game_board_params.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameBoardParams', () {
    const position = Chess.initial;

    test('readonly exposes position fen, pockets and no player side', () {
      const params = GameBoardParams.readonly(variant: Variant.standard, position: position);

      expect(params.variant, Variant.standard);
      expect(params.fen, position.fen);
      expect(params.pockets, position.pockets);
      expect(params.playerSide, PlayerSide.none);
    });

    test('interactive exposes position fen, pockets and player side', () {
      var moved = false;
      final params = GameBoardParams.interactive(
        variant: Variant.atomic,
        position: position,
        playerSide: PlayerSide.white,
        onMove: (move, {bool? viaDragAndDrop}) {
          moved = true;
        },
      );

      expect(params.variant, Variant.atomic);
      expect(params.fen, position.fen);
      expect(params.pockets, position.pockets);
      expect(params.playerSide, PlayerSide.white);

      final move = position.parseSan('e4');
      expect(move, isNotNull);
      params.mapOrNull(interactive: (p) => p.onMove(move!, viaDragAndDrop: true));
      expect(moved, isTrue);
    });

    test('empty uses empty fen and no player side or pockets', () {
      const params = GameBoardParams.empty(variant: Variant.crazyhouse);

      expect(params.variant, Variant.crazyhouse);
      expect(params.fen, kEmptyFEN);
      expect(params.pockets, isNull);
      expect(params.playerSide, PlayerSide.none);
    });

    test('emptyBoard defaults to standard empty params', () {
      expect(GameBoardParams.emptyBoard, GameBoardParams.emptyBoard);
      expect(GameBoardParams.emptyBoard.variant, Variant.standard);
      expect(GameBoardParams.emptyBoard.fen, kEmptyFEN);
      expect(GameBoardParams.emptyBoard.playerSide, PlayerSide.none);
      expect(GameBoardParams.emptyBoard.pockets, isNull);
    });
  });
}
