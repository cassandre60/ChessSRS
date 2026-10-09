// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/tokens.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/settings/board_preferences.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';

/// The theme menu preview must show what the board will actually draw.
///
/// Owner report 2026-09-29: the pictures in the theme menu did not match the
/// board — System previewed system colours and Brown a stock photo while both
/// render the SRS hatched board, and every other theme previewed a jpg that
/// drifted from its real squares.
void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  test('SRS-backed themes share one render decision with the board', () {
    for (final theme in BoardTheme.values) {
      expect(
        theme.usesSrsBoard,
        theme == BoardTheme.diagram || theme == BoardTheme.system || theme == BoardTheme.brown,
        reason: '${theme.name} must agree with toBoardSettings',
      );
    }
  });

  Future<Set<Color>> previewColors(WidgetTester tester, BoardTheme theme) async {
    await tester.pumpWidget(await makeTestProviderScopeApp(tester, home: theme.thumbnail));
    await tester.pumpAndSettle();
    return tester.widgetList<ColoredBox>(find.byType(ColoredBox)).map((b) => b.color).toSet();
  }

  testWidgets('no theme previews a stock photo', (tester) async {
    for (final theme in BoardTheme.values) {
      await tester.pumpWidget(await makeTestProviderScopeApp(tester, home: theme.thumbnail));
      await tester.pumpAndSettle();
      expect(
        find.byType(Image),
        findsNothing,
        reason: '${theme.name} must live-render, not load assets/board-thumbnails',
      );
    }
  });

  testWidgets('SRS-backed themes preview the SRS squares', (tester) async {
    final srsLight = SrsColors.light(kSrsDefaultAccent).squareLight;
    for (final theme in [BoardTheme.diagram, BoardTheme.system, BoardTheme.brown]) {
      expect(await previewColors(tester, theme), contains(srsLight), reason: theme.name);
    }
  });

  testWidgets('other themes preview their own squares', (tester) async {
    for (final theme in [
      BoardTheme.blue,
      BoardTheme.wood,
      BoardTheme.green,
      BoardTheme.paper,
      BoardTheme.slate,
    ]) {
      expect(
        await previewColors(tester, theme),
        contains(theme.colors.lightSquare),
        reason: theme.name,
      );
    }
  });

  testWidgets('folio themes use the demo board colours', (tester) async {
    // The exact fills from the look-judge demo (visual-demo.html board switch). A drift
    // here means the picker and the demo disagree about what Paper/Slate are.
    expect(BoardTheme.paper.colors.lightSquare, const Color(0xfffff9f1));
    expect(BoardTheme.paper.colors.darkSquare, const Color(0xffeee6d3));
    expect(BoardTheme.slate.colors.lightSquare, const Color(0xffe9eef3));
    expect(BoardTheme.slate.colors.darkSquare, const Color(0xffd6dee8));
  });

  test('piece sets rendered on the board agree with the piece set assets', () {
    // Owner report 2026-10-09: Colin Burnett piece set preview in settings
    // differed from the active review board because toBoardSettings previously
    // overrode cburnett with srsPieceAssets.
    const basePrefs = BoardPrefs.defaults;
    for (final set in PieceSet.values) {
      final prefs = basePrefs.copyWith(pieceSet: set);
      final boardSettings = prefs.toBoardSettings(
        Variant.standard,
        srsColors: SrsColors.light(kSrsDefaultAccent),
      );
      expect(
        boardSettings.pieceAssets,
        equals(set.assets),
        reason: '${set.name} board settings must match the piece set preview assets',
      );
    }
  });
}
