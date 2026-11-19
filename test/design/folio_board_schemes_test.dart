import 'package:chess_srs/src/design/folio_board_schemes.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('paperBoardScheme', () {
    test('uses warm paper/stone square colors', () {
      expect(paperBoardScheme.lightSquare, const Color(0xfffff9f1));
      expect(paperBoardScheme.darkSquare, const Color(0xffeee6d3));
    });

    test('uses solid backgrounds matching squares', () {
      final background = paperBoardScheme.background as SolidColorChessboardBackground;
      expect(background.lightSquare, paperBoardScheme.lightSquare);
      expect(background.darkSquare, paperBoardScheme.darkSquare);

      final whiteCoords = paperBoardScheme.whiteCoordBackground as SolidColorChessboardBackground;
      expect(whiteCoords.coordinates, isTrue);
      expect(whiteCoords.orientation, Side.white);

      final blackCoords = paperBoardScheme.blackCoordBackground as SolidColorChessboardBackground;
      expect(blackCoords.coordinates, isTrue);
      expect(blackCoords.orientation, Side.black);
    });

    test('defines highlight and move hint colors', () {
      expect(paperBoardScheme.lastMove, const HighlightDetails(solidColor: Color(0x809cc700)));
      expect(paperBoardScheme.selected, const HighlightDetails(solidColor: Color(0x6014551e)));
      expect(paperBoardScheme.validMoves, const Color(0x4014551e));
      expect(paperBoardScheme.validPremoves, const Color(0x40203085));
    });
  });

  group('slateBoardScheme', () {
    test('uses cooler square colors', () {
      expect(slateBoardScheme.lightSquare, const Color(0xffe9eef3));
      expect(slateBoardScheme.darkSquare, const Color(0xffd6dee8));
    });

    test('uses solid backgrounds matching squares', () {
      final background = slateBoardScheme.background as SolidColorChessboardBackground;
      expect(background.lightSquare, slateBoardScheme.lightSquare);
      expect(background.darkSquare, slateBoardScheme.darkSquare);

      final whiteCoords = slateBoardScheme.whiteCoordBackground as SolidColorChessboardBackground;
      expect(whiteCoords.coordinates, isTrue);
      expect(whiteCoords.orientation, Side.white);

      final blackCoords = slateBoardScheme.blackCoordBackground as SolidColorChessboardBackground;
      expect(blackCoords.coordinates, isTrue);
      expect(blackCoords.orientation, Side.black);
    });

    test('shares highlight and move hint colors with paper scheme', () {
      expect(slateBoardScheme.lastMove, paperBoardScheme.lastMove);
      expect(slateBoardScheme.selected, paperBoardScheme.selected);
      expect(slateBoardScheme.validMoves, paperBoardScheme.validMoves);
      expect(slateBoardScheme.validPremoves, paperBoardScheme.validPremoves);
    });
  });
}
