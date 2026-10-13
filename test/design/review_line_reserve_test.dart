// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../binding.dart';
import '../test_provider_scope.dart';

// DESIGN 03 §4: the notation-line region keeps min-height = 2 lines even when history is off,
// so the board never moves between turns.
void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  Widget side({required double lineFontSize, required bool wide, Widget? line}) {
    return SrsReviewSide(
      wide: wide,
      lineFontSize: lineFontSize,
      meta: const Text('meta'),
      line: line,
      slot: const Text('slot'),
      actions: const Text('actions'),
    );
  }

  group('SrsReviewSide notation-line reserve', () {
    testWidgets('history off still reserves the 2-line min-height and gap', (tester) async {
      const lineFontSize = 24.0;
      // Narrow: lineH = 24 * 1.36, reserve = 2 * lineH.
      const expectedMinHeight = lineFontSize * 1.36 * 2;

      final app = await makeTestProviderScopeApp(
        tester,
        home: side(lineFontSize: lineFontSize, wide: false),
      );
      await tester.pumpWidget(app);
      await tester.pump();

      // Before the fix the whole region was behind `if (line != null)`: with history off
      // there was no gap and no ConstrainedBox, so the slot grew and the board jumped.
      final boxes = tester.widgetList<ConstrainedBox>(find.byType(ConstrainedBox));
      final reserves = boxes.where((b) => b.constraints.minHeight == expectedMinHeight);
      expect(
        reserves.length,
        1,
        reason: 'history off must still reserve minHeight 2*lineH ($expectedMinHeight)',
      );

      expect(
        tester
            .widgetList<SizedBox>(find.byType(SizedBox))
            .any((s) => s.height == 10.0 && s.width == null),
        isTrue,
        reason: 'the 10px gap above the reserve must exist with history off',
      );
    });

    testWidgets('history on and off share the same reserve geometry', (tester) async {
      const lineFontSize = 28.0;
      // Wide: lineH = 28 * 1.3, reserve = 2 * lineH.
      const expectedMinHeight = lineFontSize * 1.3 * 2;

      Future<BoxConstraints> reserveFor(Widget? line) async {
        final app = await makeTestProviderScopeApp(
          tester,
          home: side(lineFontSize: lineFontSize, wide: true, line: line),
        );
        await tester.pumpWidget(app);
        await tester.pump();
        final boxes = tester.widgetList<ConstrainedBox>(find.byType(ConstrainedBox));
        return boxes.firstWhere((b) => b.constraints.minHeight == expectedMinHeight).constraints;
      }

      final withLine = await reserveFor(const Text('moves'));
      final withoutLine = await reserveFor(null);
      expect(withoutLine.minHeight, withLine.minHeight);
      expect(withoutLine.minHeight, expectedMinHeight);
    });
  });
}
