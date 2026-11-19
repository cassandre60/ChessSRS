import 'package:chess_srs/src/styles/lichess_colors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('LichessColors', () {
    test('exposes primary material swatch and key shades', () {
      expect(LichessColors.primary, isA<MaterialColor>());
      expect(LichessColors.primary.toARGB32(), 0xFF1B78D0);
      expect(LichessColors.primary[500], const Color(0xFF1B78D0));
      expect(LichessColors.primary[50], const Color(0xFFE4EFF9));
      expect(LichessColors.primary[900], const Color(0xFF0848B3));
    });

    test('exposes secondary material swatch and key shades', () {
      expect(LichessColors.secondary.toARGB32(), 0xFF629924);
      expect(LichessColors.secondary[50], const Color(0xFFECF3E5));
      expect(LichessColors.secondary[500], const Color(0xFF629924));
      expect(LichessColors.secondary[900], const Color(0xFF346B0D));
    });

    test('exposes accent and red material swatches', () {
      expect(LichessColors.accent.toARGB32(), 0xFFD64F00);
      expect(LichessColors.accent[100], const Color(0xFFF3CAB3));
      expect(LichessColors.accent[900], const Color(0xFFBC2600));

      expect(LichessColors.red.toARGB32(), 0xFFCC3333);
      expect(LichessColors.red[50], const Color(0xFFF9E7E7));
      expect(LichessColors.red[400], const Color(0xFFD45252));
      expect(LichessColors.red[900], const Color(0xFFAD1414));
    });

    test('defines semantic aliases and standalone colors', () {
      expect(LichessColors.error, same(LichessColors.red));
      expect(LichessColors.green, same(LichessColors.secondary));
      expect(LichessColors.good, same(LichessColors.secondary));
      expect(LichessColors.warn, same(LichessColors.brag));

      expect(LichessColors.brag, const Color(0xFFBF811D));
      expect(LichessColors.fancy, const Color(0xFFB72FC6));
      expect(LichessColors.grey, const Color(0xCCCCCCCC));
      expect(LichessColors.cyan, const Color(0xFF56B4E9));
      expect(LichessColors.blue, const Color(0xFF0072B2));
      expect(LichessColors.purple, const Color(0xFF8572ff));
    });

    test('defines analysis evaluation colors', () {
      expect(LichessColors.inaccuracy, same(LichessColors.cyan));
      expect(LichessColors.mistake, const Color(0xFFe69f00));
      expect(LichessColors.blunder, const Color(0xFFdf5353));
    });
  });
}
