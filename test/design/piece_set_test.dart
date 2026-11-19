import 'package:chess_srs/src/design/piece_set.dart';
import 'package:dartchess/dartchess.dart' show PieceKind;
import 'package:flutter/widgets.dart' show AssetImage;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('srsPieceAssets', () {
    test('returns all 12 piece kinds for light theme', () {
      final assets = srsPieceAssets(dark: false);

      expect(assets.keys, hasLength(12));
      expect(assets.keys.toSet(), PieceKind.values.toSet());
    });

    test('returns all 12 piece kinds for dark theme', () {
      final assets = srsPieceAssets(dark: true);

      expect(assets.keys, hasLength(12));
      expect(assets.keys.toSet(), PieceKind.values.toSet());
    });

    test('uses light asset paths', () {
      final assets = srsPieceAssets(dark: false);

      expect(assets[PieceKind.whitePawn], const AssetImage('assets/pieces/light/png-512/wP.png'));
      expect(assets[PieceKind.whiteKnight], const AssetImage('assets/pieces/light/png-512/wN.png'));
      expect(assets[PieceKind.whiteBishop], const AssetImage('assets/pieces/light/png-512/wB.png'));
      expect(assets[PieceKind.whiteRook], const AssetImage('assets/pieces/light/png-512/wR.png'));
      expect(assets[PieceKind.whiteQueen], const AssetImage('assets/pieces/light/png-512/wQ.png'));
      expect(assets[PieceKind.whiteKing], const AssetImage('assets/pieces/light/png-512/wK.png'));
      expect(assets[PieceKind.blackPawn], const AssetImage('assets/pieces/light/png-512/bP.png'));
      expect(assets[PieceKind.blackKnight], const AssetImage('assets/pieces/light/png-512/bN.png'));
      expect(assets[PieceKind.blackBishop], const AssetImage('assets/pieces/light/png-512/bB.png'));
      expect(assets[PieceKind.blackRook], const AssetImage('assets/pieces/light/png-512/bR.png'));
      expect(assets[PieceKind.blackQueen], const AssetImage('assets/pieces/light/png-512/bQ.png'));
      expect(assets[PieceKind.blackKing], const AssetImage('assets/pieces/light/png-512/bK.png'));
    });

    test('uses dark asset paths', () {
      final assets = srsPieceAssets(dark: true);

      expect(assets[PieceKind.whitePawn], const AssetImage('assets/pieces/dark/png-512/wP.png'));
      expect(assets[PieceKind.whiteKing], const AssetImage('assets/pieces/dark/png-512/wK.png'));
      expect(assets[PieceKind.blackQueen], const AssetImage('assets/pieces/dark/png-512/bQ.png'));
      expect(assets[PieceKind.blackKnight], const AssetImage('assets/pieces/dark/png-512/bN.png'));
    });
  });
}
