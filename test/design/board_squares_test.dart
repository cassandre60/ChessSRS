// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chess_srs/src/design/board_background.dart';
import 'package:chess_srs/src/design/tokens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../binding.dart';

/// The board's square order is a chess fundamental: h1 is light, a1 is dark.
///
/// Owner report 2026-09-29: on a phone in dark mode h1 rendered darker than
/// its neighbours, because the dark tokens were inverted in luminance
/// (`squareLight` #11141A over `squareDark` #161A22). These tests pin the
/// invariant in CI so no future palette edit can silently re-break it: the
/// token order, the painter rule, and the actual painted pixels.
void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  group('square tokens', () {
    for (final brightness in Brightness.values) {
      test('${brightness.name}: light squares read lighter than dark squares', () {
        final colors = SrsColors.forBrightness(brightness, kSrsDefaultAccent);
        expect(colors.squareLight, isNot(colors.squareDark));
        final light = colors.squareLight.computeLuminance();
        final dark = colors.squareDark.computeLuminance();
        expect(light, greaterThan(dark), reason: 'h1 must read as a light square');
        // A strict order with no visible gap still reads as broken on a phone:
        // the old dark pair differed by ~0.002 and was unreadable.
        expect(
          light - dark,
          greaterThan(0.005),
          reason: 'light and dark squares must be visibly distinct',
        );
      });
    }
  });

  group('painter rule', () {
    test('corners follow the chessboard', () {
      // White orientation: top row is rank 8, bottom row rank 1.
      expect(SrsBoardBackgroundPainter.isDarkSquare(0, 0), isFalse, reason: 'a8 is light');
      expect(SrsBoardBackgroundPainter.isDarkSquare(7, 0), isTrue, reason: 'h8 is dark');
      expect(SrsBoardBackgroundPainter.isDarkSquare(0, 7), isTrue, reason: 'a1 is dark');
      expect(SrsBoardBackgroundPainter.isDarkSquare(7, 7), isFalse, reason: 'h1 is light');
    });

    test('every square matches file+rank parity', () {
      for (var f = 0; f < 8; f++) {
        for (var r = 0; r < 8; r++) {
          // Rank number for White orientation, 1-based: rank 8 at the top.
          final rank = 8 - r;
          // a1 (file 0, rank 1) is dark: dark exactly when file+rank is odd.
          expect(
            SrsBoardBackgroundPainter.isDarkSquare(f, r),
            (f + rank).isOdd,
            reason: 'file $f row $r',
          );
        }
      }
    });
  });

  group('painted pixels', () {
    for (final brightness in Brightness.values) {
      // Plain test(), not testWidgets(): image rasterization needs the real
      // async zone, and nothing here pumps a widget.
      test('${brightness.name}: h1 paints light, a1 paints dark', () async {
        final colors = SrsColors.forBrightness(brightness, kSrsDefaultAccent);
        final pixels = await _paintSquares(colors);

        // Light squares carry no hatch: the pixel is the token, exactly.
        expect(pixels.get(7, 7), colors.squareLight, reason: 'h1 is a light square');
        expect(pixels.get(0, 0), colors.squareLight, reason: 'a8 is a light square');
        // Dark squares carry the base plus hatch: either way, never the light token.
        expect(pixels.get(0, 7), isNot(colors.squareLight), reason: 'a1 is a dark square');
        expect(pixels.get(7, 0), isNot(colors.squareLight), reason: 'h8 is a dark square');

        // The whole board, not just the corners.
        for (var f = 0; f < 8; f++) {
          for (var r = 0; r < 8; r++) {
            if (SrsBoardBackgroundPainter.isDarkSquare(f, r)) {
              expect(pixels.get(f, r), isNot(colors.squareLight), reason: 'dark ($f, $r)');
            } else {
              expect(pixels.get(f, r), colors.squareLight, reason: 'light ($f, $r)');
            }
          }
        }
      });
    }
  });
}

/// One pixel per square of an 8px board painted with [colors] (no frame, so
/// edge pixels are square colours rather than the ink border).
Future<_Pixels> _paintSquares(SrsColors colors) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  SrsBoardBackgroundPainter(colors: colors, frame: false).paint(canvas, const Size(8, 8));
  final image = await recorder.endRecording().toImage(8, 8);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return _Pixels(bytes);
}

class _Pixels {
  _Pixels(this.bytes);
  final ByteData bytes;

  Color get(int x, int y) {
    final o = (y * 8 + x) * 4;
    return Color.fromRGBO(bytes.getUint8(o), bytes.getUint8(o + 1), bytes.getUint8(o + 2), 1);
  }
}
