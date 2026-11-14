// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../binding.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  final colors = SrsColors.forBrightness(brightness, SrsAccent.ultramarine);
  return MaterialApp(
    home: Scaffold(
      body: SrsTheme(
        colors: colors,
        child: SizedBox(width: 320, height: 320, child: child),
      ),
    ),
  );
}

void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  group('SrsMoveArrow', () {
    testWidgets('renders an animated arrow and completes drawing', (tester) async {
      await tester.pumpWidget(_wrap(const SrsMoveArrow(from: 'e2', to: 'e4')));

      expect(find.byType(SrsMoveArrow), findsOneWidget);
      expect(find.byType(TweenAnimationBuilder<double>), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      await tester.pumpAndSettle();

      // Still present after animation completes.
      expect(find.byType(SrsMoveArrow), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('renders with black orientation', (tester) async {
      await tester.pumpWidget(
        _wrap(const SrsMoveArrow(from: 'e7', to: 'e5', whiteAtBottom: false)),
      );

      expect(find.byType(SrsMoveArrow), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('rebuilds for a different move key', (tester) async {
      await tester.pumpWidget(_wrap(const SrsMoveArrow(from: 'g1', to: 'f3')));
      await tester.pumpAndSettle();
      expect(find.byType(SrsMoveArrow), findsOneWidget);

      await tester.pumpWidget(_wrap(const SrsMoveArrow(from: 'b1', to: 'c3')));
      await tester.pump();
      expect(find.byType(SrsMoveArrow), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('renders in dark theme', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SrsMoveArrow(from: 'd2', to: 'd4'),
          brightness: Brightness.dark,
        ),
      );

      expect(find.byType(SrsMoveArrow), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
