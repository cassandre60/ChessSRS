import 'package:chess_srs/src/design/srs_board_color_scheme.dart';
import 'package:chess_srs/src/design/tokens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('srsBoardColorScheme', () {
    test('uses transparent squares and accent-derived highlights', () {
      final c = SrsColors.light(SrsAccent.ultramarine);
      final scheme = srsBoardColorScheme(c);

      expect(scheme.lightSquare, const Color(0x00000000));
      expect(scheme.darkSquare, const Color(0x00000000));
      expect(scheme.validMoves, c.accent.withValues(alpha: 0.28));
      expect(scheme.validPremoves, c.accent.withValues(alpha: 0.18));
      expect(scheme.lastMove.solidColor, c.accentSoft);
      expect(scheme.selected.solidColor, c.accentMid);
    });

    test('background delegates square colors to the token palette', () {
      final c = SrsColors.dark(SrsAccent.verdigris);
      final scheme = srsBoardColorScheme(c);

      expect(scheme.background.lightSquare, c.squareLight);
      expect(scheme.background.darkSquare, c.squareDark);
      expect(scheme.whiteCoordBackground.lightSquare, c.squareLight);
      expect(scheme.whiteCoordBackground.darkSquare, c.squareDark);
      expect(scheme.blackCoordBackground.lightSquare, c.squareLight);
      expect(scheme.blackCoordBackground.darkSquare, c.squareDark);
    });
  });
}
