// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-030.

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/design/top_bar.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_provider_scope.dart';

/// Owner request 2026-10-06: the opener is a white box and a black box, not a
/// text label.
///
/// The bar used to print the current scope's name, which meant the string had to
/// change as the user moved between scopes — `All studies`, an opening, a study
/// title. The squares say the same two things forever, which is what makes them
/// a switch rather than a label.
void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    Side? activeSide,
    void Function(Side)? onSidePressed,
    String? wordmark,
    Size size = const Size(390, 844),
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        surfaceSize: size,
        brightness: brightness,
        home: Center(
          child: SrsTopBar(
            activeSide: activeSide,
            onSidePressed: onSidePressed,
            wordmark: wordmark,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder square(Side side) {
    final label = side == Side.white ? 'White repertoire' : 'Black repertoire';
    return find.byWidgetPredicate((w) => w is Tooltip && w.message == label);
  }

  testWidgets('both squares are offered', (tester) async {
    await pumpBar(tester, activeSide: Side.white, onSidePressed: (_) {});

    expect(square(Side.white), findsOneWidget);
    expect(square(Side.black), findsOneWidget);
  });

  testWidgets('no text names the scope', (tester) async {
    await pumpBar(tester, activeSide: Side.white, onSidePressed: (_) {});

    // The failure this guards is a regression to the old bar, which printed the
    // scope's name: the labels exist as tooltips and semantics, so finding them
    // as visible text would mean they leaked onto the bar.
    expect(find.text('White repertoire'), findsNothing);
    expect(find.text('Black repertoire'), findsNothing);
    expect(find.text('All studies'), findsNothing);
  });

  testWidgets('the two squares sit side by side', (tester) async {
    await pumpBar(tester, activeSide: Side.white, onSidePressed: (_) {});

    final white = tester.getRect(square(Side.white));
    final black = tester.getRect(square(Side.black));

    expect(white.center.dy, closeTo(black.center.dy, 4.0));
    expect(white.right, lessThanOrEqualTo(black.left));
  });

  testWidgets('each square reaches the 44px minimum target', (tester) async {
    await pumpBar(tester, activeSide: Side.white, onSidePressed: (_) {});

    for (final side in [Side.white, Side.black]) {
      final box = tester.getRect(square(side));
      expect(box.width, greaterThanOrEqualTo(44.0), reason: '$side width');
      expect(box.height, greaterThanOrEqualTo(44.0), reason: '$side height');
    }
  });

  testWidgets('tapping a square reports that colour', (tester) async {
    final tapped = <Side>[];
    await pumpBar(tester, activeSide: Side.white, onSidePressed: tapped.add);

    await tester.tap(square(Side.black));
    await tester.pumpAndSettle();

    expect(tapped, [Side.black]);
  });

  testWidgets('the active colour is the one marked selected', (tester) async {
    await pumpBar(tester, activeSide: Side.black, onSidePressed: (_) {});

    bool toggled(Side side) => tester
        .widgetList<Semantics>(find.descendant(of: square(side), matching: find.byType(Semantics)))
        .any((s) => s.properties.toggled == true);

    expect(toggled(Side.black), isTrue, reason: 'Black is the active colour');
    expect(toggled(Side.white), isFalse);
  });

  testWidgets('a wordmark replaces the squares when there is no scope to switch', (tester) async {
    await pumpBar(tester, wordmark: 'ChessSRS');

    expect(find.text('ChessSRS'), findsOneWidget);
    expect(square(Side.white), findsNothing);
    expect(square(Side.black), findsNothing);
  });

  testWidgets('White square is light and Black square is dark in dark mode (not flipped)', (
    tester,
  ) async {
    await pumpBar(tester, activeSide: Side.white, brightness: Brightness.dark);

    BoxDecoration decoration(Side side) {
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: square(side), matching: find.byType(DecoratedBox)).last,
      );
      return box.decoration as BoxDecoration;
    }

    final whiteLum = decoration(Side.white).color!.computeLuminance();
    final blackLum = decoration(Side.black).color!.computeLuminance();

    expect(
      whiteLum,
      greaterThan(blackLum),
      reason: 'White square must be brighter than Black square in dark mode, not flipped',
    );
    expect(whiteLum, greaterThan(0.5));
    expect(blackLum, lessThan(0.1));
  });

  testWidgets('White square is light and Black square is dark in light mode', (tester) async {
    await pumpBar(tester, activeSide: Side.white, brightness: Brightness.light);

    BoxDecoration decoration(Side side) {
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: square(side), matching: find.byType(DecoratedBox)).last,
      );
      return box.decoration as BoxDecoration;
    }

    final whiteLum = decoration(Side.white).color!.computeLuminance();
    final blackLum = decoration(Side.black).color!.computeLuminance();

    expect(whiteLum, greaterThan(blackLum));
    expect(whiteLum, greaterThan(0.8));
    expect(blackLum, lessThan(0.1));
  });
}
