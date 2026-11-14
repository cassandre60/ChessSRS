import 'package:chess_srs/src/styles/lichess_colors.dart';
import 'package:chess_srs/src/styles/styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('darken', () {
    test('returns same color when amount is 0', () {
      const color = Color(0xFF336699);
      expect(darken(color, 0), equals(color));
    });

    test('returns black when amount is 1', () {
      expect(darken(const Color(0xFF336699), 1), equals(Colors.black));
    });

    test('interpolates toward black for middle amount', () {
      const color = Colors.white;
      final result = darken(color, 0.5);
      expect(result, equals(Color.lerp(Colors.white, Colors.black, 0.5)));
    });
  });

  group('lighten', () {
    test('returns same color when amount is 0', () {
      const color = Color(0xFF336699);
      expect(lighten(color, 0), equals(color));
    });

    test('returns white when amount is 1', () {
      expect(lighten(const Color(0xFF336699), 1), equals(Colors.white));
    });

    test('interpolates toward white for middle amount', () {
      const color = Colors.black;
      final result = lighten(color, 0.25);
      expect(result, equals(Color.lerp(Colors.black, Colors.white, 0.25)));
    });
  });

  group('LichessCustomColors', () {
    const base = LichessCustomColors(
      cyan: Color(0xFF000001),
      brag: Color(0xFF000002),
      good: Color(0xFF000003),
      error: Color(0xFF000004),
      fancy: Color(0xFF000005),
      purple: Color(0xFF000006),
      primary: Color(0xFF000007),
    );

    test('copyWith overrides only provided fields', () {
      final copy = base.copyWith(
        good: const Color(0xFFABCDEF),
        primary: const Color(0xFF111111),
      );
      expect(copy.cyan, base.cyan);
      expect(copy.brag, base.brag);
      expect(copy.good, const Color(0xFFABCDEF));
      expect(copy.error, base.error);
      expect(copy.fancy, base.fancy);
      expect(copy.purple, base.purple);
      expect(copy.primary, const Color(0xFF111111));
    });

    test('copyWith with no args preserves values', () {
      final copy = base.copyWith();
      expect(copy.cyan, base.cyan);
      expect(copy.brag, base.brag);
      expect(copy.good, base.good);
      expect(copy.error, base.error);
      expect(copy.fancy, base.fancy);
      expect(copy.purple, base.purple);
      expect(copy.primary, base.primary);
    });

    test(
      'lerp returns same instance values when other is not LichessCustomColors',
      () {
        final result = base.lerp(null, 0.5);
        expect(result.cyan, base.cyan);
        expect(result.primary, base.primary);
      },
    );

    test('lerp interpolates colors when other is LichessCustomColors', () {
      const other = LichessCustomColors(
        cyan: Color(0xFFFFFFFF),
        brag: Color(0xFFFFFFFF),
        good: Color(0xFFFFFFFF),
        error: Color(0xFFFFFFFF),
        fancy: Color(0xFFFFFFFF),
        purple: Color(0xFFFFFFFF),
        primary: Color(0xFFFFFFFF),
      );
      final result = base.lerp(other, 0.5);
      expect(result.cyan, Color.lerp(base.cyan, other.cyan, 0.5));
      expect(result.brag, Color.lerp(base.brag, other.brag, 0.5));
      expect(result.good, Color.lerp(base.good, other.good, 0.5));
      expect(result.error, Color.lerp(base.error, other.error, 0.5));
      expect(result.fancy, Color.lerp(base.fancy, other.fancy, 0.5));
      expect(result.purple, Color.lerp(base.purple, other.purple, 0.5));
      expect(result.primary, Color.lerp(base.primary, other.primary, 0.5));
    });
  });

  group('lichessCustomColors', () {
    test('uses LichessColors palette values', () {
      expect(lichessCustomColors.cyan, LichessColors.cyan);
      expect(lichessCustomColors.brag, LichessColors.brag);
      expect(lichessCustomColors.good, LichessColors.good);
      expect(lichessCustomColors.error, LichessColors.error);
      expect(lichessCustomColors.fancy, LichessColors.fancy);
      expect(lichessCustomColors.purple, LichessColors.purple);
      expect(lichessCustomColors.primary, LichessColors.primary);
    });
  });
}
