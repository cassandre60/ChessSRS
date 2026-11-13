// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/tokens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SrsAccent and SrsColors', () {
    test('kSrsDefaultAccent is ultramarine', () {
      expect(kSrsDefaultAccent, SrsAccent.ultramarine);
    });

    test('every accent has light and dark pairs used by palettes', () {
      for (final accent in SrsAccent.values) {
        expect(kSrsAccents.containsKey(accent), isTrue);
        final pair = kSrsAccents[accent]!;
        final light = SrsColors.light(accent);
        final dark = SrsColors.dark(accent);
        expect(light.accentId, accent);
        expect(dark.accentId, accent);
        expect(light.brightness, Brightness.light);
        expect(dark.brightness, Brightness.dark);
        expect(light.accent, pair.light);
        expect(dark.accent, pair.dark);
        expect(light.isDark, isFalse);
        expect(dark.isDark, isTrue);
      }
    });

    test('forBrightness selects the matching factory', () {
      for (final accent in SrsAccent.values) {
        expect(SrsColors.forBrightness(Brightness.light, accent), SrsColors.light(accent));
        expect(SrsColors.forBrightness(Brightness.dark, accent), SrsColors.dark(accent));
      }
    });

    test('equality and hashCode depend on brightness and accent only', () {
      final a = SrsColors.light(SrsAccent.ultramarine);
      final b = SrsColors.light(SrsAccent.ultramarine);
      final c = SrsColors.dark(SrsAccent.ultramarine);
      final d = SrsColors.light(SrsAccent.violet);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
    });

    test('board squares keep light above dark in luminance (dark mode)', () {
      final dark = SrsColors.dark(kSrsDefaultAccent);
      expect(dark.squareLight.computeLuminance(), greaterThan(dark.squareDark.computeLuminance()));
    });
  });

  group('SrsMotion', () {
    testWidgets('resolve returns Duration.zero when animations are disabled', (tester) async {
      late Duration resolved;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              resolved = SrsMotion.resolve(context, SrsMotion.pieceMove);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved, Duration.zero);
    });

    testWidgets('resolve preserves duration when animations are enabled', (tester) async {
      late Duration resolved;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: Builder(
            builder: (context) {
              resolved = SrsMotion.resolve(context, SrsMotion.pieceMove);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved, SrsMotion.pieceMove);
    });
  });

  group('SrsLayout', () {
    test('isWide uses the breakpoint', () {
      expect(SrsLayout.isWide(SrsLayout.wideBreakpoint - 0.01), isFalse);
      expect(SrsLayout.isWide(SrsLayout.wideBreakpoint), isTrue);
      expect(SrsLayout.isWide(900), isTrue);
    });

    test('boardSize clamps to non-negative values', () {
      expect(SrsLayout.boardSize(const Size(300, 400)), greaterThanOrEqualTo(0));
      expect(SrsLayout.boardSize(const Size(50, 50)), 0);
      expect(SrsLayout.boardSize(const Size(1200, 900)), greaterThan(0));
    });

    test('minTouchTarget meets platform guidance', () {
      expect(SrsLayout.minTouchTarget, greaterThanOrEqualTo(48));
    });
  });

  group('SrsText', () {
    test('lineSize clamps wide sizes and returns narrow default', () {
      expect(SrsText.lineSize(wide: false), 24);
      expect(SrsText.lineSize(wide: true, wideWidth: 100), 23);
      expect(SrsText.lineSize(wide: true, wideWidth: 2000), 31);
    });

    test('typography helpers produce styles with expected families/weights', () {
      const c = Color(0xFF000000);
      expect(SrsText.scopeName(c).fontFamily, SrsText.ui);
      expect(SrsText.scopeName(c).fontWeight, FontWeight.w600);
      expect(SrsText.note(c).fontFamily, SrsText.read);
      expect(SrsText.dueNumber(c).fontFeatures, SrsText.tabular);
      expect(SrsText.answerMove(true, c).fontSize, 52);
      expect(SrsText.answerMove(false, c).fontSize, 38);
    });
  });
}
