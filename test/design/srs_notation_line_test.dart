// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../binding.dart';
import '../test_provider_scope.dart';

void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  // The line renders one RichText per token, moves lowercased, plus a leading ellipsis text
  // when the line is cut. Collecting the plain text is what makes "which plies are on screen"
  // assertable, rather than counting widgets.
  Future<List<String>> render(WidgetTester tester, List<String> moves) async {
    final app = await makeTestProviderScopeApp(tester, home: SrsNotationLine(moves: moves));
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    return tester
        .widgetList<RichText>(find.byType(RichText))
        .map((r) => r.text.toPlainText())
        .toList();
  }

  group('SrsNotationLine', () {
    testWidgets('a line that fits is shown whole, with no ellipsis', (tester) async {
      final tokens = await render(tester, ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6']);

      expect(tokens, containsAll(['e4', 'e5', 'f3', 'c6', 'b5', 'a6']));
      expect(tokens.where((t) => t.contains('…')), isEmpty);
    });

    testWidgets('eight plies are still shown whole, as the design requires', (tester) async {
      // 03-components.md:116: "Long lines: show at least the last 8 plies; if truncated, start
      // with `…`." The line kept 6, so a game at move 5 lost its first move pair.
      final tokens = await render(tester, [
        'e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6', //
        'Ba4', 'Nf6',
      ]);

      expect(tokens, containsAll(['e4', 'e5', 'f3', 'c6', 'b5', 'a6', 'a4', 'f6']));
      expect(tokens.where((t) => t.contains('…')), isEmpty, reason: '8 plies fit');
    });

    testWidgets('a longer line is cut back to eight plies and marked with an ellipsis', (
      tester,
    ) async {
      final tokens = await render(tester, [
        'e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6', // 6
        'Ba4', 'Nf6', 'O-O', 'Be7', // 10
      ]);

      expect(tokens.where((t) => t.contains('…')), isNotEmpty, reason: 'a cut line has to say so');
      expect(tokens, isNot(contains('e4')), reason: 'the first plies were cut');
      expect(tokens, isNot(contains('e5')));
      // The last eight plies are the ones kept.
      expect(tokens, containsAll(['f3', 'c6', 'b5', 'a6', 'a4', 'f6', 'O-O', 'e7']));
    });
  });
}
