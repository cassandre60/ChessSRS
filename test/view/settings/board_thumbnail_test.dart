// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/tokens.dart';
import 'package:chess_srs/src/model/settings/board_preferences.dart';
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
    for (final theme in [BoardTheme.blue, BoardTheme.wood, BoardTheme.green]) {
      expect(
        await previewColors(tester, theme),
        contains(theme.colors.lightSquare),
        reason: theme.name,
      );
    }
  });
}
