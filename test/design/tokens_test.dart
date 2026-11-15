// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SrsAccent / kSrsAccents', () {
    test('every SrsAccent has an accent pair', () {
      for (final accent in SrsAccent.values) {
        expect(kSrsAccents.containsKey(accent), isTrue);
      }
      expect(kSrsAccents.length, SrsAccent.values.length);
    });

    test('default accent is ultramarine', () {
      expect(kSrsDefaultAccent, SrsAccent.ultramarine);
    });
  });

  group('SrsColors', () {
    test('light() is light, dark() is dark', () {
      expect(SrsColors.light(SrsAccent.ultramarine).brightness, Brightness.light);
      expect(SrsColors.dark(SrsAccent.ultramarine).brightness, Brightness.dark);
      expect(SrsColors.light(SrsAccent.ultramarine).isDark, isFalse);
      expect(SrsColors.dark(SrsAccent.ultramarine).isDark, isTrue);
    });

    test('forBrightness selects by brightness', () {
      expect(
        SrsColors.forBrightness(Brightness.dark, SrsAccent.violet),
        SrsColors.dark(SrsAccent.violet),
      );
      expect(
        SrsColors.forBrightness(Brightness.light, SrsAccent.violet),
        SrsColors.light(SrsAccent.violet),
      );
    });

    test('equality depends on brightness and accentId only', () {
      final a = SrsColors.light(SrsAccent.ultramarine);
      final b = SrsColors.light(SrsAccent.ultramarine);
      final c = SrsColors.light(SrsAccent.violet);
      final d = SrsColors.dark(SrsAccent.ultramarine);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
    });

    test('accentSoft/ accentMid derive from the accent color', () {
      final colors = SrsColors.light(SrsAccent.ochre);
      expect(colors.accentSoft, colors.accent.withValues(alpha: 0.11));
      expect(colors.accentMid, colors.accent.withValues(alpha: 0.24));
      expect(colors.accent, kSrsAccents[SrsAccent.ochre]!.light);
    });
  });

  group('SrsFolioColors', () {
    test('light() is light, dark() is dark', () {
      expect(SrsFolioColors.light(SrsAccent.ultramarine).brightness, Brightness.light);
      expect(SrsFolioColors.dark(SrsAccent.ultramarine).brightness, Brightness.dark);
      expect(SrsFolioColors.light(SrsAccent.ultramarine).isDark, isFalse);
      expect(SrsFolioColors.dark(SrsAccent.ultramarine).isDark, isTrue);
    });

    test('forBrightness selects by brightness', () {
      expect(
        SrsFolioColors.forBrightness(Brightness.dark, SrsAccent.violet),
        SrsFolioColors.dark(SrsAccent.violet),
      );
    });

    test('equality depends on brightness and accentId only', () {
      final a = SrsFolioColors.light(SrsAccent.ultramarine);
      final b = SrsFolioColors.light(SrsAccent.ultramarine);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('SrsLayout', () {
    test('isWide boundary at 720', () {
      expect(SrsLayout.isWide(720), isTrue);
      expect(SrsLayout.isWide(719), isFalse);
    });

    test('minTouchTarget is 48', () {
      expect(SrsLayout.minTouchTarget, 48);
    });

    test('boardSize is non-negative for wide and narrow', () {
      expect(SrsLayout.boardSize(const Size(800, 600)), greaterThanOrEqualTo(0));
      expect(SrsLayout.boardSize(const Size(400, 800)), greaterThanOrEqualTo(0));
    });
  });
}
